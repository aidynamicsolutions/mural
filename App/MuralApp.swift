import CoreAI
import CoreML
import Foundation
import Observation
import OSLog
import SwiftUI
import WhisperKit

@main struct MuralApp: App {
    @State private var store: LearningStore?
    @State private var startupError: String?

    init() {
        let args = ProcessInfo.processInfo.arguments
        let inMemory = args.contains("--preview") || AudioVerification.requested || CoreAIASRProbe.requested
        do { _store = State(initialValue: try LearningStore(inMemory: inMemory)) }
        catch { _startupError = State(initialValue: "Mural couldn’t open its learning record. Your existing data has not been replaced.") }
    }

    var body: some Scene {
        WindowGroup {
            if CoreAIASRProbe.requested {
                CoreAIASRProbeView().preferredColorScheme(.light)
            } else if let store {
                RootView(store: store).preferredColorScheme(.light)
            } else {
                ContentUnavailableView(
                    "Let’s try again",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(startupError ?? "The learning record is unavailable.")
                ).preferredColorScheme(.light)
            }
        }
    }
}

/// Development-only parity runner. Normal Talk/On-device still uses WhisperKit/Core ML.
private actor CoreAIPhoWhisper {
    struct AssetTiming: Codable, Sendable {
        let path: String
        let cacheHit: Bool
        let cacheLookupSeconds: Double
        let specializationSeconds: Double
        let functionLoadSeconds: Double
    }
    struct Preparation: Codable, Sendable {
        let architecture: String
        let supportDirectory: String
        let melLoadSeconds: Double
        let tokenizerLoadSeconds: Double
        let encoder: AssetTiming
        let decoder: AssetTiming
        let totalSeconds: Double
    }
    struct Result: Codable, Sendable {
        let text: String
        let detectedLanguageToken: Int
        let generatedTokenCount: Int
        let melSeconds: Double
        let encoderSeconds: Double
        let languageSeconds: Double
        let decoderSeconds: Double
        let totalSeconds: Double
    }
    struct Config: Sendable {
        let encoderURL: URL
        let decoderURL: URL
        let supportURL: URL

        static func resolve() throws -> Self {
            let args = ProcessInfo.processInfo.arguments
            let arch = AIModel.deviceArchitectureName
            func arg(_ name: String) -> URL? {
                let prefix = "--\(name)="
                guard let raw = args.first(where: { $0.hasPrefix(prefix) }) else { return nil }
                return URL(fileURLWithPath: String(raw.dropFirst(prefix.count)))
            }
            let root = URL.applicationSupportDirectory.appending(
                path: "CoreAI/PhoWhisperSplit", directoryHint: .isDirectory)
            func asset(_ role: String, explicit: URL?) throws -> URL {
                if let explicit {
                    guard FileManager.default.fileExists(atPath: explicit.path) else {
                        throw ProbeError("Missing \(role) asset: \(explicit.path)")
                    }
                    return explicit
                }
                for name in [
                    "phowhisper-cs-fp16-v1.\(role).\(arch).aimodelc",
                    "phowhisper-cs-fp16-v1.\(role).aimodelc",
                    "phowhisper-cs-fp16-v1.\(role).aimodel",
                ] {
                    let url = root.appending(path: name)
                    if FileManager.default.fileExists(atPath: url.path) { return url }
                }
                throw ProbeError("Missing \(role) Core AI asset for \(arch) under \(root.path).")
            }
            let support = arg("coreai-support-dir") ??
                URL.applicationSupportDirectory.appending(
                    path: "PhoWhisperCS/phowhisper-cs-fp16-v1", directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: support.path) else {
                throw ProbeError("Missing accepted PhoWhisper support assets: \(support.path)")
            }
            return Self(
                encoderURL: try asset("encoder", explicit: arg("coreai-encoder-path")),
                decoderURL: try asset("decoder", explicit: arg("coreai-decoder-path")),
                supportURL: support
            )
        }
    }
    struct ProbeError: LocalizedError, Sendable {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    private var featureExtractor: FeatureExtractor?
    private var tokenizer: PhoWhisperTokenizer?
    private var encoderModel: AIModel?
    private var decoderModel: AIModel?
    private var encoderFunction: InferenceFunction?
    private var decoderFunction: InferenceFunction?
    private var suppressTokens = Set<Int>()
    private var maxNewTokens = 224
    private var preparedConfig: Config?
    private var savedPreparation: Preparation?

    func prepare(_ config: Config) async throws -> Preparation {
        if let preparedConfig, preparedConfig.encoderURL == config.encoderURL,
           preparedConfig.decoderURL == config.decoderURL,
           preparedConfig.supportURL == config.supportURL,
           encoderFunction != nil, decoderFunction != nil,
           featureExtractor != nil, tokenizer != nil, let savedPreparation {
            return savedPreparation
        }
        unload()
        let total = ProcessInfo.processInfo.systemUptime
        let melURL = config.supportURL.appending(path: "MelSpectrogram.mlmodelc")
        guard FileManager.default.fileExists(atPath: melURL.path) else {
            throw ProbeError("Missing accepted MelSpectrogram.mlmodelc.")
        }
        let mel = FeatureExtractor()
        let melStart = ProcessInfo.processInfo.systemUptime
        try await mel.loadModel(at: melURL, computeUnits: .cpuAndGPU, prewarmMode: false)
        let melSeconds = ProcessInfo.processInfo.systemUptime - melStart
        guard mel.melCount == 80, mel.windowSamples == 480_000 else {
            throw ProbeError("Accepted PhoWhisper mel contract changed.")
        }

        let tokStart = ProcessInfo.processInfo.systemUptime
        let tok = try await PhoWhisperTokenizer.load(from: config.supportURL)
        let tokSeconds = ProcessInfo.processInfo.systemUptime - tokStart

        struct Generation: Decodable { let suppress_tokens: [Int]?; let max_new_tokens: Int? }
        let gen = try JSONDecoder().decode(
            Generation.self,
            from: Data(contentsOf: config.supportURL.appending(path: "generation_config.json"))
        )
        suppressTokens = Set((gen.suppress_tokens ?? []).filter { (0..<51_865).contains($0) })
        maxNewTokens = min(max(gen.max_new_tokens ?? 224, 1), 444)

        let enc = try await Self.loadAsset(config.encoderURL)
        let dec = try await Self.loadAsset(config.decoderURL)
        try Self.validate(enc.model, role: "encoder")
        try Self.validate(dec.model, role: "decoder")

        featureExtractor = mel
        tokenizer = tok
        encoderModel = enc.model
        decoderModel = dec.model
        encoderFunction = enc.function
        decoderFunction = dec.function
        preparedConfig = config

        let prep = Preparation(
            architecture: AIModel.deviceArchitectureName,
            supportDirectory: config.supportURL.path,
            melLoadSeconds: melSeconds,
            tokenizerLoadSeconds: tokSeconds,
            encoder: enc.timing,
            decoder: dec.timing,
            totalSeconds: ProcessInfo.processInfo.systemUptime - total
        )
        savedPreparation = prep
        return prep
    }

    func transcribe(_ samples: [Float]) async throws -> Result {
        guard let mel = featureExtractor, let tok = tokenizer, let encFn = encoderFunction,
              let decFn = decoderFunction, let encModel = encoderModel,
              let decModel = decoderModel else { throw ProbeError("Prepare first.") }
        guard !samples.isEmpty, samples.count <= 480_000, samples.allSatisfy(\.isFinite) else {
            throw ProbeError("Expected 1–480000 finite 16 kHz mono samples.")
        }
        let total = ProcessInfo.processInfo.systemUptime

        let melStart = ProcessInfo.processInfo.systemUptime
        guard let padded = AudioProcessor.padOrTrimAudio(
            fromArray: samples, startAt: 0, toLength: 480_000, saveSegment: false),
              let feature = try await mel.logMelSpectrogram(fromAudio: padded) as? MLMultiArray else {
            throw ProbeError("Accepted mel extraction failed.")
        }
        let values = try Self.readAcceptedMel(feature)
        let melSeconds = ProcessInfo.processInfo.systemUptime - melStart

        let encDesc = try Self.inputDescriptor(encModel, name: "input_features")
        var input = NDArray(descriptor: encDesc.resolvingDynamicDimensions([1, 80, 3000]))
        try Self.fillFloat(&input, values: values)
        let encStart = ProcessInfo.processInfo.systemUptime
        var encOut = try await encFn.run(inputs: ["input_features": input])
        guard let hidden = encOut.remove("encoder_hidden_states")?.ndArray,
              hidden.shape == [1, 1500, 1280] else {
            throw ProbeError("Unexpected Core AI encoder output.")
        }
        let encSeconds = ProcessInfo.processInfo.systemUptime - encStart

        let langStart = ProcessInfo.processInfo.systemUptime
        let langLogits = try await Self.decode(
            decFn, model: decModel,
            tokens: [Int32(tok.specialTokens.startOfTranscriptToken)], hidden: hidden)
        let language = try Self.argmax(
            langLogits, allowed: tok.allLanguageTokens, suppressed: [])
        let langSeconds = ProcessInfo.processInfo.systemUptime - langStart

        let s = tok.specialTokens
        let sampleBegin = 4
        var tokens = [s.startOfTranscriptToken, language, s.transcribeToken, s.noTimestampsToken]
        let decStart = ProcessInfo.processInfo.systemUptime
        var generated = 0
        while generated < maxNewTokens, tokens.count < 448 {
            let logits = try await Self.decode(
                decFn, model: decModel, tokens: tokens.map(Int32.init), hidden: hidden)
            var suppressed = suppressTokens
            if tokens.count == sampleBegin {
                suppressed.insert(s.whitespaceToken)
                suppressed.insert(s.endToken)
            }
            let next = try Self.argmax(logits, allowed: nil, suppressed: suppressed)
            if next == s.endToken { break }
            tokens.append(next)
            generated += 1
        }
        let decSeconds = ProcessInfo.processInfo.systemUptime - decStart
        let lexical = tokens.dropFirst(sampleBegin).filter { $0 < s.specialTokenBegin }
        let text = tok.decode(tokens: Array(lexical))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Result(
            text: text, detectedLanguageToken: language, generatedTokenCount: generated,
            melSeconds: melSeconds, encoderSeconds: encSeconds,
            languageSeconds: langSeconds, decoderSeconds: decSeconds,
            totalSeconds: ProcessInfo.processInfo.systemUptime - total)
    }

    private func unload() {
        featureExtractor = nil; tokenizer = nil
        encoderFunction = nil; decoderFunction = nil
        encoderModel = nil; decoderModel = nil
        preparedConfig = nil; savedPreparation = nil
        suppressTokens = []; maxNewTokens = 224
    }

    private static func loadAsset(_ url: URL) async throws
      -> (model: AIModel, function: InferenceFunction, timing: AssetTiming) {
        let options = SpecializationOptions.default
        let cache = AIModelCache.default
        let cacheStart = ProcessInfo.processInfo.systemUptime
        let cached = try cache.model(for: url, options: options)
        let lookup = ProcessInfo.processInfo.systemUptime - cacheStart
        let model: AIModel
        let specialization: Double
        if let cached { model = cached; specialization = 0 }
        else {
            let start = ProcessInfo.processInfo.systemUptime
            model = try await AIModel.specialize(
                contentsOf: url, options: options, cachePolicy: .persistent)
            specialization = ProcessInfo.processInfo.systemUptime - start
        }
        let start = ProcessInfo.processInfo.systemUptime
        guard let function = try model.loadFunction(named: "main") else {
            throw ProbeError("Missing main function in \(url.lastPathComponent).")
        }
        return (
            model, function,
            AssetTiming(
                path: url.path, cacheHit: cached != nil, cacheLookupSeconds: lookup,
                specializationSeconds: specialization,
                functionLoadSeconds: ProcessInfo.processInfo.systemUptime - start)
        )
    }

    private static func validate(_ model: AIModel, role: String) throws {
        guard let d = model.functionDescriptor(for: "main") else {
            throw ProbeError("\(role) has no main descriptor.")
        }
        if role == "encoder" {
            guard case .ndArray(let x) = d.inputDescriptor(of: "input_features"),
                  x.shape == [1, 80, 3000] else {
                throw ProbeError("Encoder input must be [1,80,3000].")
            }
        } else {
            guard case .ndArray(let ids) = d.inputDescriptor(of: "decoder_input_ids"),
                  case .ndArray(let hidden) = d.inputDescriptor(of: "encoder_hidden_states"),
                  ids.shape.count == 2, hidden.shape == [1, 1500, 1280] else {
                throw ProbeError("Decoder contract does not match PhoWhisper Large-v2.")
            }
        }
    }

    private static func inputDescriptor(_ model: AIModel, name: String) throws -> NDArrayDescriptor {
        guard let d = model.functionDescriptor(for: "main"),
              case .ndArray(let x) = d.inputDescriptor(of: name) else {
            throw ProbeError("Missing Core AI input \(name).")
        }
        return x
    }

    private static func decode(
        _ function: InferenceFunction, model: AIModel,
        tokens: [Int32], hidden: NDArray
    ) async throws -> NDArray {
        let desc = try inputDescriptor(model, name: "decoder_input_ids")
        var ids = NDArray(descriptor: desc.resolvingDynamicDimensions([1, tokens.count]))
        var view = ids.mutableView(as: Int32.self)
        view.copyElements(fromContentsOf: tokens)
        var outputs = try await function.run(inputs: [
            "decoder_input_ids": ids, "encoder_hidden_states": hidden
        ])
        guard let logits = outputs.remove("logits")?.ndArray,
              logits.shape == [1, tokens.count, 51_865] else {
            throw ProbeError("Unexpected decoder logits shape.")
        }
        return logits
    }

    private static func readAcceptedMel(_ a: MLMultiArray) throws -> [Float] {
        guard a.dataType == .float32 else { throw ProbeError("Mel must remain float32.") }
        let shape = a.shape.map(\.intValue), strides = a.strides.map(\.intValue)
        let p = a.dataPointer.assumingMemoryBound(to: Float.self)
        var out = [Float](repeating: 0, count: 80 * 3000)
        if shape == [1, 80, 3000] {
            for m in 0..<80 { for t in 0..<3000 {
                out[m * 3000 + t] = p[m * strides[1] + t * strides[2]]
            }}
        } else if shape == [1, 80, 1, 3000] {
            for m in 0..<80 { for t in 0..<3000 {
                out[m * 3000 + t] = p[m * strides[1] + t * strides[3]]
            }}
        } else { throw ProbeError("Unexpected mel shape \(shape).") }
        guard out.allSatisfy(\.isFinite) else { throw ProbeError("Non-finite mel.") }
        return out
    }

    private static func fillFloat(_ a: inout NDArray, values: [Float]) throws {
        guard values.count == a.shape.reduce(1, *) else { throw ProbeError("Input size mismatch.") }
        switch a.scalarType {
        case .float16:
            var v = a.mutableView(as: Float16.self)
            v.copyElements(fromContentsOf: values.map(Float16.init))
        case .float32:
            var v = a.mutableView(as: Float.self)
            v.copyElements(fromContentsOf: values)
        default: throw ProbeError("Unsupported Core AI float input \(a.scalarType).")
        }
    }

    private static func argmax(
        _ a: NDArray, allowed: Set<Int>?, suppressed: Set<Int>
    ) throws -> Int {
        let shape = a.shape
        guard shape.count == 3, shape[0] == 1, shape[2] == 51_865, shape[1] > 0 else {
            throw ProbeError("Unexpected logits shape \(shape).")
        }
        let row = shape[1] - 1
        let candidates = allowed?.sorted() ?? Array(0..<51_865)
        var best = -1, bestValue = -Float.infinity
        func scan<T: BinaryFloatingPoint & BitwiseCopyable>(_ type: T.Type) {
            a.view(as: type).withUnsafePointer { p, _, strides in
                for token in candidates where !suppressed.contains(token) && (0..<51_865).contains(token) {
                    let value = Float(p[row * strides[1] + token * strides[2]])
                    if value > bestValue { bestValue = value; best = token }
                }
            }
        }
        switch a.scalarType {
        case .float16: scan(Float16.self)
        case .float32: scan(Float.self)
        default: throw ProbeError("Unsupported logits type \(a.scalarType).")
        }
        guard best >= 0 else { throw ProbeError("No valid token survived filtering.") }
        return best
    }
}

@MainActor @Observable private final class CoreAIASRProbe {
    struct FileResult: Codable, Sendable {
        let file: String
        let sampleCount: Int
        let result: CoreAIPhoWhisper.Result?
        let error: String?
    }
    struct Report: Codable, Sendable {
        var date = Date()
        let architecture: String
        let preparation: CoreAIPhoWhisper.Preparation?
        let fixturesDirectory: String
        let files: [FileResult]
        let error: String?
    }

    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains("--coreai-asr-probe")
    }
    static var autoRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--coreai-asr-auto")
    }

    private(set) var running = false
    private(set) var status = "Ready"
    private(set) var preparation: CoreAIPhoWhisper.Preparation?
    private(set) var results: [FileResult] = []
    private(set) var error: String?
    private(set) var reportPath = ""
    @ObservationIgnored private let recognizer = CoreAIPhoWhisper()

    func run() async {
        guard !running else { return }
        running = true; defer { running = false }
        error = nil; results = []; status = "Preparing split Core AI PhoWhisper…"
        do {
            let config = try CoreAIPhoWhisper.Config.resolve()
            preparation = try await recognizer.prepare(config)
            let directory = try Self.fixturesDirectory()
            let exts = Set(["wav", "m4a", "caf", "mp3"])
            let files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                .filter { exts.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            guard !files.isEmpty else { throw CoreAIPhoWhisper.ProbeError("No fixtures in \(directory.path).") }
            for (i, file) in files.enumerated() {
                status = "Transcribing \(i + 1)/\(files.count): \(file.lastPathComponent)"
                do {
                    let samples = try await Task.detached {
                        try AudioProcessor.loadAudioAsFloatArray(fromPath: file.path)
                    }.value
                    let result = try await recognizer.transcribe(samples)
                    results.append(.init(file: file.lastPathComponent, sampleCount: samples.count, result: result, error: nil))
                } catch {
                    results.append(.init(file: file.lastPathComponent, sampleCount: 0, result: nil, error: error.localizedDescription))
                }
                try writeReport(directory: directory, error: nil)
            }
            status = "Corpus complete: \(results.filter { $0.error == nil }.count)/\(files.count) transcribed"
            try writeReport(directory: directory, error: nil)
        } catch {
            self.error = error.localizedDescription
            status = "Core AI ASR probe failed"
            if let directory = try? Self.fixturesDirectory() {
                try? writeReport(directory: directory, error: error.localizedDescription)
            }
        }
    }

    private func writeReport(directory: URL, error: String?) throws {
        let report = Report(
            architecture: AIModel.deviceArchitectureName, preparation: preparation,
            fixturesDirectory: directory.path, files: results, error: error)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = URL.documentsDirectory.appending(path: "coreai-asr-probe.json")
        try encoder.encode(report).write(to: url, options: .atomic)
        reportPath = url.path
    }

    private static func fixturesDirectory() throws -> URL {
        let prefix = "--coreai-fixtures-dir="
        if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) {
            let url = URL(fileURLWithPath: String(raw.dropFirst(prefix.count)))
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw CoreAIPhoWhisper.ProbeError("Missing fixtures directory \(url.path).")
            }
            return url
        }
        let url = URL.documentsDirectory.appending(
            path: "CoreAI/PhoWhisper/Fixtures", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CoreAIPhoWhisper.ProbeError(
                "Stage frozen fixtures at Documents/CoreAI/PhoWhisper/Fixtures.")
        }
        return url
    }
}

private struct CoreAIASRProbeView: View {
    @State private var probe = CoreAIASRProbe()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("PhoWhisper Core AI transcript parity").font(.title2.bold())
                    Text("Development-only. Normal Mural conversations still use WhisperKit/Core ML.")
                        .foregroundStyle(.secondary)
                    Text(probe.status).font(.headline)
                    if let p = probe.preparation {
                        Text(String(format: "Prepare %.3f s · encoder load %.3f · decoder load %.3f",
                                    p.totalSeconds, p.encoder.functionLoadSeconds, p.decoder.functionLoadSeconds))
                            .font(.caption.monospacedDigit())
                    }
                    if !probe.reportPath.isEmpty {
                        Text("Report: \(probe.reportPath)").font(.caption).textSelection(.enabled)
                    }
                    if let error = probe.error {
                        Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                    }
                    Button(probe.running ? "Working…" : "Run staged corpus") {
                        Task { await probe.run() }
                    }.buttonStyle(.borderedProminent).disabled(probe.running)

                    ForEach(probe.results.indices, id: \.self) { i in
                        let r = probe.results[i]
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.file).font(.headline)
                            if let result = r.result {
                                Text(result.text).textSelection(.enabled)
                                Text(String(format: "total %.3f · mel %.3f · enc %.3f · lang %.3f · dec %.3f",
                                            result.totalSeconds, result.melSeconds, result.encoderSeconds,
                                            result.languageSeconds, result.decoderSeconds))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            } else if let error = r.error {
                                Text(error).font(.caption).foregroundStyle(.red)
                            }
                        }.padding(.vertical, 4)
                    }
                }.padding(24)
            }.navigationTitle("Core AI ASR Probe")
        }.task {
            if CoreAIASRProbe.autoRequested { await probe.run() }
        }
    }
}
