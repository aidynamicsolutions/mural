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
        let totalSeconds: Double
    }
    struct Result: Codable, Sendable {
        let text: String
        let detectedLanguageToken: Int
        let generatedTokenCount: Int
        let encoderLoad: AssetTiming
        let decoderLoad: AssetTiming
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
    private var suppressTokens = Set<Int>()
    private var maxNewTokens = 224
    private var preparedConfig: Config?
    private var savedPreparation: Preparation?

    func prepare(_ config: Config) async throws -> Preparation {
        if let preparedConfig, preparedConfig.encoderURL == config.encoderURL,
           preparedConfig.decoderURL == config.decoderURL,
           preparedConfig.supportURL == config.supportURL,
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

        featureExtractor = mel
        tokenizer = tok
        preparedConfig = config

        let prep = Preparation(
            architecture: AIModel.deviceArchitectureName,
            supportDirectory: config.supportURL.path,
            melLoadSeconds: melSeconds,
            tokenizerLoadSeconds: tokSeconds,
            totalSeconds: ProcessInfo.processInfo.systemUptime - total
        )
        savedPreparation = prep
        return prep
    }

    func transcribe(_ samples: [Float], file: URL) async throws -> Result? {
        guard let mel = featureExtractor, tokenizer != nil,
              let config = preparedConfig else { throw ProbeError("Prepare first.") }
        guard !samples.isEmpty, samples.count <= 480_000, samples.allSatisfy(\.isFinite) else {
            throw ProbeError("Expected 1–480000 finite 16 kHz mono samples.")
        }
        let total = ProcessInfo.processInfo.systemUptime

        if ProcessInfo.processInfo.arguments.contains("--coreai-decode-only") {
            let root = try Self.checkpointURL(file)
            let metadata = try JSONDecoder().decode(EncoderCheckpoint.self,
                from: Data(contentsOf: root.appendingPathExtension("json")))
            guard metadata.file == file.lastPathComponent, metadata.sampleCount == samples.count else {
                throw ProbeError("Encoder checkpoint does not match fixture.")
            }
            let data = try Data(contentsOf: root.appendingPathExtension("fp16"))
            guard data.count == 1500 * 1280 * 2 else { throw ProbeError("Invalid encoder checkpoint size.") }
            let values = data.withUnsafeBytes { bytes in
                stride(from: 0, to: data.count, by: 2).map {
                    Float16(bitPattern: bytes.loadUnaligned(fromByteOffset: $0, as: UInt16.self))
                }
            }
            guard values.allSatisfy(\.isFinite) else { throw ProbeError("Non-finite encoder checkpoint.") }
            VietnameseEnglishRecognizer.logMemory(stage: "fresh-process-before-decoder", model: "coreai-sequential")
            return try await decodeTurn(Encoded(values: values, load: metadata.load, seconds: metadata.seconds),
                config: config, melSeconds: metadata.melSeconds, totalStart: total)
        }

        let melStart = ProcessInfo.processInfo.systemUptime
        guard let padded = AudioProcessor.padOrTrimAudio(
            fromArray: samples, startAt: 0, toLength: 480_000, saveSegment: false),
              let feature = try await mel.logMelSpectrogram(fromAudio: padded) as? MLMultiArray else {
            throw ProbeError("Accepted mel extraction failed.")
        }
        let values = try Self.readAcceptedMel(feature)
        let melSeconds = ProcessInfo.processInfo.systemUptime - melStart
        Logger().notice("Core AI probe: accepted mel ready in \(melSeconds) s")

        VietnameseEnglishRecognizer.logMemory(stage: "before-encoder", model: "coreai-sequential")
        let encoded = try await Self.encode(values, url: config.encoderURL)
        // Only owned FP16 values cross this boundary, never a model-backed NDArray.
        VietnameseEnglishRecognizer.logMemory(stage: "encoder-scope-ended", model: "coreai-sequential")
        if ProcessInfo.processInfo.arguments.contains("--coreai-encode-only") {
            let root = try Self.checkpointURL(file)
            try encoded.values.withUnsafeBytes { try Data($0).write(to: root.appendingPathExtension("fp16"), options: .atomic) }
            let metadata = EncoderCheckpoint(file: file.lastPathComponent, sampleCount: samples.count,
                load: encoded.load, seconds: encoded.seconds, melSeconds: melSeconds)
            try JSONEncoder().encode(metadata).write(to: root.appendingPathExtension("json"), options: .atomic)
            return nil
        }
        let result = try await decodeTurn(encoded, config: config, melSeconds: melSeconds, totalStart: total)
        VietnameseEnglishRecognizer.logMemory(stage: "decoder-scope-ended", model: "coreai-sequential")
        return result
    }

    private struct EncoderCheckpoint: Codable {
        let file: String
        let sampleCount: Int
        let load: AssetTiming
        let seconds: Double
        let melSeconds: Double
    }

    private static func checkpointURL(_ file: URL) throws -> URL {
        let directory = URL.documentsDirectory.appending(path: "CoreAI/PhoWhisper/EncoderCheckpoints")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: file.lastPathComponent)
    }

    private struct Encoded {
        let values: [Float16]
        let load: AssetTiming
        let seconds: Double
    }

    private static func encode(_ values: [Float], url: URL) async throws -> Encoded {
        let encoder = try await loadAsset(url)
        try validate(encoder.model, role: "encoder")
        VietnameseEnglishRecognizer.logMemory(stage: "encoder-loaded", model: "coreai-sequential")
        let desc = try inputDescriptor(encoder.model, name: "input_features")
        var input = NDArray(descriptor: desc.resolvingDynamicDimensions([1, 80, 3000]))
        try fillFloat(&input, values: values)
        let start = ProcessInfo.processInfo.systemUptime
        var outputs = try await encoder.function.run(inputs: ["input_features": input])
        guard let hidden = outputs.remove("encoder_hidden_states")?.ndArray else {
            throw ProbeError("Missing encoder output.")
        }
        let owned = try copyEncoderOutput(hidden)
        let seconds = ProcessInfo.processInfo.systemUptime - start
        Logger().notice("Core AI probe: encoder ready in \(seconds) s")
        VietnameseEnglishRecognizer.logMemory(stage: "encoder-output-copied", model: "coreai-sequential")
        return Encoded(values: owned, load: encoder.timing, seconds: seconds)
    }

    private static func copyEncoderOutput(_ hidden: NDArray) throws -> [Float16] {
        guard hidden.shape == [1, 1500, 1280], hidden.scalarType == .float16 else {
            throw ProbeError("Encoder output must remain FP16 [1,1500,1280].")
        }
        var owned = [Float16](repeating: 0, count: 1500 * 1280)
        hidden.view(as: Float16.self).withUnsafePointer { p, _, strides in
            for t in 0..<1500 { for c in 0..<1280 {
                owned[t * 1280 + c] = p[t * strides[1] + c * strides[2]]
            }}
        }
        guard owned.allSatisfy(\.isFinite) else { throw ProbeError("Non-finite encoder output.") }
        return owned
    }

    private func decodeTurn(_ encoded: Encoded, config: Config, melSeconds: Double,
                            totalStart: Double) async throws -> Result {
        guard let tok = tokenizer else { throw ProbeError("Prepare first.") }
        let decoder = try await Self.loadAsset(config.decoderURL)
        try Self.validate(decoder.model, role: "decoder")
        VietnameseEnglishRecognizer.logMemory(stage: "decoder-loaded", model: "coreai-sequential")
        let desc = try Self.inputDescriptor(decoder.model, name: "encoder_hidden_states")
        var hidden = NDArray(descriptor: desc.resolvingDynamicDimensions([1, 1500, 1280]))
        guard hidden.scalarType == .float16 else { throw ProbeError("Decoder hidden input must remain FP16.") }
        var hiddenView = hidden.mutableView(as: Float16.self)
        hiddenView.copyElements(fromContentsOf: encoded.values)
        guard try Self.copyEncoderOutput(hidden).map(\.bitPattern) == encoded.values.map(\.bitPattern) else {
            throw ProbeError("Encoder/decoder handoff changed FP16 bits.")
        }
        let decFn = decoder.function, decModel = decoder.model
        let langStart = ProcessInfo.processInfo.systemUptime
        let langLogits = try await Self.decode(
            decFn, model: decModel,
            tokens: [Int32(tok.specialTokens.startOfTranscriptToken)], hidden: hidden)
        let language = try Self.argmax(
            langLogits, allowed: tok.allLanguageTokens, suppressed: [])
        let langSeconds = ProcessInfo.processInfo.systemUptime - langStart
        Logger().notice("Core AI probe: language token \(language) in \(langSeconds) s")

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
            encoderLoad: encoded.load, decoderLoad: decoder.timing,
            melSeconds: melSeconds, encoderSeconds: encoded.seconds,
            languageSeconds: langSeconds, decoderSeconds: decSeconds,
            totalSeconds: ProcessInfo.processInfo.systemUptime - totalStart)
    }

    private func unload() {
        featureExtractor = nil; tokenizer = nil
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
        let shape = a.shape.map(\.intValue), strides = a.strides.map(\.intValue)
        guard shape == [1, 80, 3000] || shape == [1, 80, 1, 3000] else {
            throw ProbeError("Unexpected mel shape \(shape).")
        }
        var out = [Float](repeating: 0, count: 80 * 3000)
        func copy<T: BinaryFloatingPoint>(_ type: T.Type) {
            let p = a.dataPointer.assumingMemoryBound(to: type)
            for m in 0..<80 { for t in 0..<3000 {
                out[m * 3000 + t] = Float(p[m * strides[1] + t * strides[shape.count - 1]])
            }}
        }
        switch a.dataType {
        case .float16: copy(Float16.self) // Widening preserves every finite FP16 value exactly.
        case .float32: copy(Float.self)
        default: throw ProbeError("Unsupported mel type \(a.dataType).")
        }
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
        let mode: String
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
            let onlyFile = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--coreai-fixture=") }
                .map { String($0.dropFirst("--coreai-fixture=".count)) }
            let files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                .filter { exts.contains($0.pathExtension.lowercased()) && (onlyFile == nil || $0.lastPathComponent == onlyFile) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            guard !files.isEmpty else { throw CoreAIPhoWhisper.ProbeError("No fixtures in \(directory.path).") }
            try writeReport(directory: directory, error: nil)
            for (i, file) in files.enumerated() {
                status = "Transcribing \(i + 1)/\(files.count): \(file.lastPathComponent)"
                do {
                    let samples = try await Task.detached {
                        try AudioProcessor.loadAudioAsFloatArray(fromPath: file.path)
                    }.value
                    let result = try await recognizer.transcribe(samples, file: file)
                    results.append(.init(file: file.lastPathComponent, sampleCount: samples.count, result: result, error: nil))
                } catch {
                    results.append(.init(file: file.lastPathComponent, sampleCount: 0, result: nil, error: error.localizedDescription))
                }
                try writeReport(directory: directory, error: nil)
            }
            status = "Corpus complete: \(results.filter { $0.result != nil }.count)/\(files.count) transcribed"
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
            architecture: AIModel.deviceArchitectureName,
            mode: ProcessInfo.processInfo.arguments.contains("--coreai-encode-only") ? "encode-only" :
                (ProcessInfo.processInfo.arguments.contains("--coreai-decode-only") ? "decode-only" : "sequential"),
            preparation: preparation,
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
                        Text(String(format: "Frontend/tokenizer %.3f s · models load sequentially per file", p.totalSeconds))
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
