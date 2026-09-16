import CoreAI
import CoreML
import CryptoKit
import Foundation
import Metal
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
        let assetSHA256: [String: String]
        let decoderCompute: String
    }
    struct Result: Codable, Sendable {
        let text: String
        let detectedLanguageToken: Int
        let generatedTokenCount: Int
        let termination: String
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
        let decoderCase: String?
        let cpuOnly: Bool
        let statefulMode: String?

        static func resolve() throws -> Self {
            let args = ProcessInfo.processInfo.arguments
            let arch = AIModel.deviceArchitectureName
            func arg(_ name: String) -> URL? {
                let prefix = "--\(name)="
                guard let raw = args.first(where: { $0.hasPrefix(prefix) }) else { return nil }
                return URL(fileURLWithPath: String(raw.dropFirst(prefix.count)))
            }
            let decoderCase = args.first { $0.hasPrefix("--coreai-decoder-case=") }
                .map { String($0.dropFirst("--coreai-decoder-case=".count)) }
            let cpuOnly = args.contains("--coreai-decoder-cpu-only")
            let statefulMode = args.first { $0.hasPrefix("--coreai-stateful=") }
                .map { String($0.dropFirst("--coreai-stateful=".count)) }
            if let statefulMode {
                guard ["steps", "transcribe"].contains(statefulMode),
                      args.filter({ $0.hasPrefix("--coreai-fixture=") }) == ["--coreai-fixture=001.wav"],
                      args.contains("--coreai-decode-only"), !args.contains("--coreai-encode-only"),
                      arg("coreai-decoder-path") != nil, decoderCase == nil, !cpuOnly else {
                    throw ProbeError("Stateful proof requires fixture 001, decode-only and an explicit stateful asset.")
                }
            }
            if let decoderCase {
                guard ["one-one", "four", "one-four"].contains(decoderCase),
                      args.contains("--coreai-decode-only"),
                      args.contains(where: { $0.hasPrefix("--coreai-fixture=") }),
                      !args.contains("--coreai-encode-only") else {
                    throw ProbeError("Decoder cases require decode-only and one explicit fixture.")
                }
            }
            guard !cpuOnly || decoderCase != nil else {
                throw ProbeError("CPU-only is a bounded decoder diagnostic, not a corpus backend.")
            }
            guard !(args.contains("--coreai-encode-only") && args.contains("--coreai-decode-only")) else {
                throw ProbeError("Choose encode-only or decode-only, not both.")
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
            let decoder = try asset("decoder", explicit: arg("coreai-decoder-path") ??
                (cpuOnly ? root.appending(path: "phowhisper-cs-fp16-v1.decoder.aimodel") : nil))
            guard !cpuOnly || decoder.pathExtension == "aimodel" else {
                throw ProbeError("CPU-only must specialize the source .aimodel, not a default-compute AOT asset.")
            }
            return Self(
                encoderURL: try asset("encoder", explicit: arg("coreai-encoder-path")),
                decoderURL: decoder, supportURL: support,
                decoderCase: decoderCase, cpuOnly: cpuOnly, statefulMode: statefulMode
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
    private var preparedConfig: Config?
    private var assetSHA256: [String: String] = [:]
    private var runDirectory: URL?
    private var callIndex = 0
    private var fixture = ""
    private var encoderInvalidationAttempted = false

    func prepare(_ config: Config, runDirectory: URL) async throws -> Preparation {
        unload()
        self.runDirectory = runDirectory
        callIndex = 0
        let total = ProcessInfo.processInfo.systemUptime
        try event("prepare-before", fields: [
            "decoderCase": config.statefulMode.map { "stateful-\($0)" } ?? config.decoderCase ?? "transcription",
            "decoderCompute": config.cpuOnly ? "cpuOnly" : "default",
            "expectFrequentReshapes": false, "cachePolicy": "persistent",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "architecture": AIModel.deviceArchitectureName,
            "encoderPath": config.encoderURL.path, "decoderPath": config.decoderURL.path
        ])
        for (role, url) in [("encoder", config.encoderURL), ("decoder", config.decoderURL), ("support", config.supportURL)] {
            try event("asset-verification-before", fields: ["role": role])
            assetSHA256[role] = try Self.fingerprint(url)
            try event("asset-verification-after", fields: ["role": role, "sha256": assetSHA256[role]!])
        }
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

        struct Generation: Decodable { let suppress_tokens: [Int] }
        let gen = try JSONDecoder().decode(
            Generation.self,
            from: Data(contentsOf: config.supportURL.appending(path: "generation_config.json"))
        )
        // Match WhisperKit 1.1.0 createLogitsFilters, including its special-token exclusion.
        suppressTokens = Set(gen.suppress_tokens.filter { (0..<tok.specialTokens.specialTokenBegin).contains($0) })

        featureExtractor = mel
        tokenizer = tok
        preparedConfig = config

        let prep = Preparation(
            architecture: AIModel.deviceArchitectureName,
            supportDirectory: config.supportURL.path,
            melLoadSeconds: melSeconds,
            tokenizerLoadSeconds: tokSeconds,
            totalSeconds: ProcessInfo.processInfo.systemUptime - total,
            assetSHA256: assetSHA256, decoderCompute: config.cpuOnly ? "cpuOnly" : "default"
        )
        try event("prepare-after")
        return prep
    }

    func transcribe(_ samples: [Float], file: URL) async throws -> Result? {
        guard let mel = featureExtractor, tokenizer != nil,
              let config = preparedConfig else { throw ProbeError("Prepare first.") }
        guard !samples.isEmpty, samples.count <= 480_000, samples.allSatisfy(\.isFinite) else {
            throw ProbeError("Expected 1–480000 finite 16 kHz mono samples.")
        }
        let total = ProcessInfo.processInfo.systemUptime
        fixture = file.lastPathComponent
        let audioSHA256 = try Self.fingerprint(file)
        try event("fixture-before", fields: ["audioSHA256": audioSHA256, "sampleCount": samples.count])

        if ProcessInfo.processInfo.arguments.contains("--coreai-decode-only") {
            let root = try Self.checkpointURL(file)
            let metadata = try JSONDecoder().decode(EncoderCheckpoint.self,
                from: Data(contentsOf: root.appendingPathExtension("json")))
            guard metadata.file == file.lastPathComponent, metadata.sampleCount == samples.count,
                  metadata.audioSHA256 == audioSHA256,
                  metadata.encoderSHA256 == assetSHA256["encoder"],
                  metadata.supportSHA256 == assetSHA256["support"] else {
                throw ProbeError("Encoder checkpoint audio/model/support identity differs. Encode this fixture again.")
            }
            let data = try Data(contentsOf: root.appendingPathExtension("fp16"))
            guard data.count == 1500 * 1280 * 2,
                  Self.sha256(data) == metadata.tensorSHA256 else {
                throw ProbeError("Encoder checkpoint length or SHA-256 mismatch.")
            }
            try event("checkpoint-verified", fields: ["tensorSHA256": metadata.tensorSHA256])
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
            let data = encoded.values.withUnsafeBytes { Data($0) }
            try data.write(to: root.appendingPathExtension("fp16"), options: .atomic)
            let metadata = EncoderCheckpoint(file: file.lastPathComponent, sampleCount: samples.count,
                audioSHA256: audioSHA256, encoderSHA256: assetSHA256["encoder"]!,
                supportSHA256: assetSHA256["support"]!, tensorSHA256: Self.sha256(data),
                load: encoded.load, seconds: encoded.seconds, melSeconds: melSeconds)
            try JSONEncoder().encode(metadata).write(to: root.appendingPathExtension("json"), options: .atomic)
            try event("checkpoint-written", fields: ["tensorSHA256": metadata.tensorSHA256])
            return nil
        }
        let result = try await decodeTurn(encoded, config: config, melSeconds: melSeconds, totalStart: total)
        VietnameseEnglishRecognizer.logMemory(stage: "decoder-scope-ended", model: "coreai-sequential")
        return result
    }

    private struct EncoderCheckpoint: Codable {
        let file: String
        let sampleCount: Int
        let audioSHA256: String
        let encoderSHA256: String
        let supportSHA256: String
        let tensorSHA256: String
        let load: AssetTiming
        let seconds: Double
        let melSeconds: Double
    }

    private static func checkpointURL(_ file: URL) throws -> URL {
        let directory = URL.documentsDirectory.appending(path: "CoreAI/PhoWhisper/EncoderCheckpoints-v2")
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
                            totalStart: Double) async throws -> Result? {
        guard let tok = tokenizer else { throw ProbeError("Prepare first.") }
        try event("decoder-load-before")
        let decoder = try await Self.loadAsset(config.decoderURL, options: config.cpuOnly ? .cpuOnly : .default)
        try Self.validate(decoder.model, role: "decoder")
        try event("decoder-load-after", fields: [
            "cacheHit": decoder.timing.cacheHit,
            "cacheLookupSeconds": decoder.timing.cacheLookupSeconds,
            "specializationSeconds": decoder.timing.specializationSeconds,
            "functionLoadSeconds": decoder.timing.functionLoadSeconds
        ])
        let desc = try Self.inputDescriptor(decoder.model, name: "encoder_hidden_states")
        var hidden = NDArray(descriptor: desc.resolvingDynamicDimensions([1, 1500, 1280]))
        guard hidden.scalarType == .float16 else { throw ProbeError("Decoder hidden input must remain FP16.") }
        var hiddenView = hidden.mutableView(as: Float16.self)
        hiddenView.copyElements(fromContentsOf: encoded.values)
        guard try Self.copyEncoderOutput(hidden).map(\.bitPattern) == encoded.values.map(\.bitPattern) else {
            throw ProbeError("Encoder/decoder handoff changed FP16 bits.")
        }
        let decFn = decoder.function, decModel = decoder.model
        let cache = try config.statefulMode.map { _ in try DecoderState(model: decModel) }
        defer { cache?.reset() } // Local ownership: no state survives success, error or cancellation.
        if config.statefulMode == "steps" {
            let sequence: [Int32] = [50258, 50278, 50359, 50363, 56, 4690, 286, 1437]
            for replay in 0..<2 {
                cache!.reset()
                try event("state-reset", fields: ["stateID": cache!.id, "replay": replay])
                for end in 1...sequence.count {
                    _ = try await decode(decFn, model: decModel, tokens: Array(sequence.prefix(end)),
                                         hidden: hidden, cache: cache)
                }
            }
            try event("diagnostic-complete", fields: ["transcriptProduced": false, "stateful": true])
            return nil
        }
        if let decoderCase = config.decoderCase {
            // Teacher-forced diagnostic prefix, not a forced language for transcription.
            let one: [Int32] = [50258], four: [Int32] = [50258, 50278, 50359, 50363]
            let prefixes = decoderCase == "one-one" ? [one, one] : (decoderCase == "four" ? [four] : [one, four])
            for prefix in prefixes {
                _ = try await decode(decFn, model: decModel, tokens: prefix, hidden: hidden)
            }
            try event("diagnostic-complete", fields: ["transcriptProduced": false])
            return nil
        }
        let langStart = ProcessInfo.processInfo.systemUptime
        let langLogits = try await decode(
            decFn, model: decModel,
            tokens: [Int32(tok.specialTokens.startOfTranscriptToken)], hidden: hidden, cache: cache)
        let language = try Self.checkedArgmax(
            langLogits, allowed: tok.allLanguageTokens, suppressed: [])
        let langSeconds = ProcessInfo.processInfo.systemUptime - langStart
        Logger().notice("Core AI probe: language token \(language) in \(langSeconds) s")

        let s = tok.specialTokens
        let sampleBegin = 4
        var tokens = [s.startOfTranscriptToken, language, s.transcribeToken, s.noTimestampsToken]
        let decStart = ProcessInfo.processInfo.systemUptime
        if let cache {
            cache.reset() // Language detection must not double-feed SOT or contaminate transcription.
            try event("state-reset", fields: ["stateID": cache.id, "purpose": "transcription"])
            for end in 1..<sampleBegin {
                _ = try await decode(decFn, model: decModel, tokens: tokens.prefix(end).map(Int32.init),
                                     hidden: hidden, cache: cache)
            }
        }
        var generated = 0
        var termination = "tokenLimit"
        // WhisperKit 1.1.0 stops before appending at maxTokenContext - 1.
        while tokens.count < Constants.maxTokenContext - 1 {
            try Task.checkCancellation()
            let logits = try await decode(
                decFn, model: decModel, tokens: tokens.map(Int32.init), hidden: hidden, cache: cache)
            var suppressed = suppressTokens
            if tokens.count == sampleBegin {
                suppressed.insert(s.whitespaceToken)
                suppressed.insert(s.endToken)
            }
            let next = try Self.checkedArgmax(logits, allowed: nil, suppressed: suppressed)
            if next == s.endToken { termination = "endToken"; break }
            tokens.append(next)
            generated += 1
        }
        let decSeconds = ProcessInfo.processInfo.systemUptime - decStart
        let lexical = tokens.dropFirst(sampleBegin).filter { $0 < s.specialTokenBegin }
        let text = tok.decode(tokens: Array(lexical))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Result(
            text: text, detectedLanguageToken: language, generatedTokenCount: generated,
            termination: termination, encoderLoad: encoded.load, decoderLoad: decoder.timing,
            melSeconds: melSeconds, encoderSeconds: encoded.seconds,
            languageSeconds: langSeconds, decoderSeconds: decSeconds,
            totalSeconds: ProcessInfo.processInfo.systemUptime - totalStart)
    }

    private func unload() {
        featureExtractor = nil; tokenizer = nil
        preparedConfig = nil; assetSHA256 = [:]
        suppressTokens = []
    }

    private static func loadAsset(_ url: URL, options: SpecializationOptions = .default) async throws
      -> (model: AIModel, function: InferenceFunction, timing: AssetTiming) {
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

    /// Owned by one decodeTurn invocation, never shared across actor suspension points.
    private final class DecoderState {
        let storage: any MTLBuffer
        let descriptors: [NDArrayDescriptor]
        let offsets: [Int]
        let names: [String]
        var logits: NDArray
        var position = 0
        var id = UUID().uuidString

        init(model: AIModel) throws {
            guard let d = model.functionDescriptor(for: "main"),
                  Set(d.stateNames) == Set((0..<32).flatMap { ["key_\($0)", "value_\($0)"] }),
                  case .ndArray(let output) = d.outputDescriptor(of: "logits"),
                  output.shape == [1, 1, 51865], output.scalarType == .float16 else {
                throw ProbeError("Unexpected stateful output/state ABI.")
            }
            for (name, shape, type) in [
                ("decoder_input_ids", [1, 1], NDArray.ScalarType.int32),
                ("cache_position", [1], .int32), // Core AI conversion narrows Torch int64 indices.
                ("attention_mask", [1, 1, 1, 224], .float16),
                ("encoder_hidden_states", [1, 1500, 1280], .float16)
            ] {
                let input = try CoreAIPhoWhisper.inputDescriptor(model, name: name)
                guard input.shape == shape, input.scalarType == type else {
                    throw ProbeError("Unexpected stateful input ABI: \(name), \(input.shape), \(input.scalarType).")
                }
            }
            names = d.stateNames.sorted()
            logits = NDArray(descriptor: output)
            var descriptors: [NDArrayDescriptor] = [], offsets: [Int] = []
            var byteCount = 0
            for name in names {
                guard case .ndArray(let state) = d.stateDescriptor(of: name),
                      state.shape == [1, 20, 224, 64], state.scalarType == .float16 else {
                    throw ProbeError("Unexpected stateful cache ABI: \(name).")
                }
                offsets.append(byteCount); descriptors.append(state)
                byteCount += (state.minimumByteCount + 4095) / 4096 * 4096
            }
            guard let storage = MTLCreateSystemDefaultDevice()?.makeBuffer(length: byteCount, options: .storageModeShared) else {
                throw ProbeError("Cannot allocate native state storage.")
            }
            self.storage = storage; self.descriptors = descriptors; self.offsets = offsets
            reset()
        }

        func reset() {
            // Only called outside inference; no live mutable view or GPU operation shares this storage.
            storage.contents().initializeMemory(as: UInt8.self, repeating: 0, count: storage.length)
            position = 0; id = UUID().uuidString
        }
    }

    private func decode(
        _ function: InferenceFunction, model: AIModel,
        tokens: [Int32], hidden: NDArray, cache: DecoderState? = nil
    ) async throws -> [Float] {
        try Task.checkCancellation()
        guard !tokens.isEmpty, tokens.allSatisfy({ (0..<51865).contains($0) }) else {
            throw ProbeError("Invalid decoder token.")
        }
        if let cache {
            guard cache.position == tokens.count - 1, (0..<224).contains(cache.position) else {
                throw ProbeError("Non-sequential or out-of-bounds cache position.")
            }
        }
        let inputTokens = cache == nil ? tokens : [tokens.last!]
        let desc = try Self.inputDescriptor(model, name: "decoder_input_ids")
        var ids = NDArray(descriptor: desc.resolvingDynamicDimensions([1, inputTokens.count]))
        var view = ids.mutableView(as: Int32.self)
        view.copyElements(fromContentsOf: inputTokens)
        callIndex += 1
        let identity: [String: Any] = ["tokens": tokens, "prefixLength": tokens.count,
            "stateID": cache?.id ?? "stateless", "position": cache?.position ?? 0,
            "inputTokens": inputTokens]
        try event("decoder-before", fields: identity)
        let start = ProcessInfo.processInfo.systemUptime
        do {
            let logits: NDArray
            if let cache {
                var position = NDArray(descriptor: try Self.inputDescriptor(model, name: "cache_position"))
                var positionView = position.mutableView(as: Int32.self)
                positionView.copyElements(fromContentsOf: [Int32(cache.position)])
                var mask = NDArray(descriptor: try Self.inputDescriptor(model, name: "attention_mask"))
                var maskView = mask.mutableView(as: Float16.self)
                maskView.copyElements(fromContentsOf: (0..<224).map {
                    $0 <= cache.position ? Float16(0) : -Float16.greatestFiniteMagnitude
                })
                try await runCached(function, inputs: ["decoder_input_ids": ids, "encoder_hidden_states": hidden,
                    "cache_position": position, "attention_mask": mask], storage: cache.storage,
                    names: cache.names, descriptors: cache.descriptors, offsets: cache.offsets, output: &cache.logits)
                logits = cache.logits
                cache.position += 1
            } else {
                var outputs = try await function.run(inputs: [
                    "decoder_input_ids": ids, "encoder_hidden_states": hidden
                ])
                guard let output = outputs.remove("logits")?.ndArray else {
                    throw ProbeError("Missing decoder logits.")
                }
                logits = output
            }
            let seconds = ProcessInfo.processInfo.systemUptime - start
            guard logits.shape == [1, inputTokens.count, 51_865] else {
                throw ProbeError("Unexpected decoder logits shape.")
            }
            try Task.checkCancellation()
            let row = try Self.readLogits(logits)
            let top = row.indices.sorted { row[$0] == row[$1] ? $0 < $1 : row[$0] > row[$1] }.prefix(5)
            guard let runDirectory else { throw ProbeError("Missing diagnostic directory.") }
            let name = String(format: "step-%04d.logits.f32", callIndex)
            try row.withUnsafeBytes { try Data($0).write(to: runDirectory.appending(path: name), options: .atomic) }
            try event("decoder-after", fields: identity.merging([
                "seconds": seconds,
                "shape": logits.shape, "scalarType": String(describing: logits.scalarType),
                "allFinite": true, "lastRowFile": name,
                "topIDs": Array(top), "topLogits": top.map { row[$0] },
                "winnerMargin": row[top.first!] - row[top.dropFirst().first!]
            ]) { _, new in new })
            return row
        } catch {
            try event("decoder-error", fields: ["prefixLength": tokens.count,
                "seconds": ProcessInfo.processInfo.systemUptime - start, "error": error.localizedDescription])
            throw error
        }
    }

    private func runCached(_ function: InferenceFunction, inputs: [String: NDArray],
                           storage: borrowing any MTLBuffer, names: [String],
                           descriptors: [NDArrayDescriptor], offsets: [Int], output: inout NDArray) async throws {
        // Disjoint aligned regions in one privately owned native buffer. Views end with this await.
        var states = InferenceFunction.MutableViews()
        for i in names.indices {
            let d = descriptors[i]
            states.insert(NDArray.MutableRawView(metalBuffer: storage, byteOffset: offsets[i],
                scalarType: d.scalarType, shape: d.shape, strides: d.preferredStrides,
                interleaveLayout: d.interleaveLayout), for: names[i])
        }
        var outputs = InferenceFunction.MutableViews()
        outputs.insert(&output, for: "logits")
        _ = try await function.run(inputs: inputs, states: states, outputViews: outputs)
    }

    private static func readLogits(_ a: NDArray) throws -> [Float] {
        let shape = a.shape
        var row = [Float](repeating: 0, count: 51_865)
        func read<T: BinaryFloatingPoint & BitwiseCopyable>(_ type: T.Type) throws {
            try a.view(as: type).withUnsafePointer { p, _, strides in
                for t in 0..<shape[1] { for v in 0..<51_865 {
                    let value = Float(p[t * strides[1] + v * strides[2]])
                    guard value.isFinite else { throw ProbeError("Non-finite raw logit at [\(t),\(v)].") }
                    if t == shape[1] - 1 { row[v] = value }
                }}
            }
        }
        switch a.scalarType {
        case .float16: try read(Float16.self)
        case .float32: try read(Float.self)
        default: throw ProbeError("Unsupported logits type \(a.scalarType).")
        }
        return row
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

    private func event(_ stage: String, fields: [String: Any] = [:]) throws {
        guard let runDirectory else { throw ProbeError("Missing diagnostic directory.") }
        var entry = fields
        entry["stage"] = stage
        entry["runID"] = runDirectory.lastPathComponent
        entry["fixture"] = fixture
        entry["callIndex"] = callIndex
        entry["uptime"] = ProcessInfo.processInfo.systemUptime
        entry["memory"] = VietnameseEnglishRecognizer.logMemory(stage: stage, model: "coreai-diagnostic")
        entry["thermalState"] = ProcessInfo.processInfo.thermalState.rawValue
        let data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) + Data([10])
        let url = runDirectory.appending(path: "events.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize() // The before marker must survive a native SIGABRT.
    }

    struct WhisperKitProof: Codable, Sendable {
        let mode: String
        let timings: [String: Double]
        let assetSHA256: [String: String]
        let encoderLoad: AssetTiming?
        let turns: [ProofTurn]
    }
    struct ProofTurn: Codable, Sendable {
        let text: String
        let languages: [String]
        let tokens: [[Int]]
        let seconds: Double
    }
    private struct EncoderCapture: Sendable {
        let mel: [Float]
        let hidden: [Float16] // Canonical [time, channel], not Core ML's physical layout.
    }

    // Single private kit owner, one window/worker, awaited serially. The stock model,
    // loading implementation and predictions are unchanged; only boundary values are copied.
    private final class CapturingCoreMLEncoder: AudioEncoding, WhisperMLModel {
        let encoder = AudioEncoder()
        let owner: CoreAIPhoWhisper
        var capture: EncoderCapture?
        var model: MLModel? {
            get { encoder.model }
            set { encoder.model = newValue }
        }
        var embedSize: Int? { encoder.embedSize }
        init(owner: CoreAIPhoWhisper) { self.owner = owner }
        func encodeFeatures(_ features: any FeatureExtractorOutputType) async throws -> (any AudioEncoderOutputType)? {
            guard let mel = features as? MLMultiArray else { throw ProbeError("Expected accepted mel array.") }
            let values = try CoreAIPhoWhisper.readAcceptedMel(mel)
            try await owner.event("whisperkit-encoder-before", fields: ["backend": "coreml"])
            guard let hidden = try await encoder.encodeFeatures(mel) else { throw ProbeError("Missing Core ML encoder output.") }
            try Task.checkCancellation()
            capture = EncoderCapture(mel: values, hidden: try CoreAIPhoWhisper.readDecoderEmbeddings(hidden))
            try await owner.event("whisperkit-encoder-after", fields: ["backend": "coreml"])
            return hidden
        }
    }

    private actor HybridEncoder: AudioEncoding {
        nonisolated let embedSize: Int? = 1280
        let function: InferenceFunction
        let input: NDArrayDescriptor
        let owner: CoreAIPhoWhisper
        private var busy = false
        private(set) var capture: EncoderCapture?
        init(function: InferenceFunction, input: NDArrayDescriptor, owner: CoreAIPhoWhisper) {
            self.function = function; self.input = input; self.owner = owner
        }
        nonisolated(nonsending) func encodeFeatures(_ features: any FeatureExtractorOutputType) async throws -> (any AudioEncoderOutputType)? {
            guard let mel = features as? MLMultiArray else { throw ProbeError("Expected accepted mel array.") }
            // Only owned Sendable values cross isolation, never WhisperKit's non-Sendable arrays.
            let values = try CoreAIPhoWhisper.readAcceptedMel(mel)
            return try CoreAIPhoWhisper.decoderEmbeddings(await encode(values))
        }
        private func encode(_ values: [Float]) async throws -> [Float16] {
            guard !busy else { throw ProbeError("Hybrid encoder is already running.") }
            busy = true; defer { busy = false }
            try Task.checkCancellation()
            var array = NDArray(descriptor: input)
            try CoreAIPhoWhisper.fillFloat(&array, values: values)
            try await owner.event("whisperkit-encoder-before", fields: ["backend": "coreai"])
            var outputs = try await function.run(inputs: ["input_features": array])
            guard let output = outputs.remove("encoder_hidden_states")?.ndArray else {
                throw ProbeError("Missing Core AI encoder output.")
            }
            try Task.checkCancellation()
            let hidden = try CoreAIPhoWhisper.copyEncoderOutput(output)
            capture = EncoderCapture(mel: values, hidden: hidden)
            try await owner.event("whisperkit-encoder-after", fields: ["backend": "coreai"])
            return hidden
        }
    }

    private static func whisperKitProofUsesFreshEncoder(_ args: [String], mode: String) throws -> Bool {
        let freshFlags = args.filter { $0.hasPrefix("--coreai-hybrid-fresh-encoder") }
        let invalidationFlags = args.filter { $0.hasPrefix("--coreai-hybrid-invalidate-encoder") }
        let releaseFlags = args.filter { $0.hasPrefix("--coreai-hybrid-release-after-first") }
        let recreateFlags = args.filter { $0.hasPrefix("--coreai-hybrid-recreate-between-turns") }
        guard ["baseline", "hybrid"].contains(mode),
              args.filter({ $0.hasPrefix("--coreai-whisperkit=") }) == ["--coreai-whisperkit=\(mode)"],
              args.filter({ $0.hasPrefix("--coreai-fixture=") }) == ["--coreai-fixture=001.wav"],
              (freshFlags.isEmpty || (mode == "hybrid" && freshFlags == ["--coreai-hybrid-fresh-encoder"])),
              (invalidationFlags.isEmpty || (freshFlags == ["--coreai-hybrid-fresh-encoder"] &&
                  invalidationFlags == ["--coreai-hybrid-invalidate-encoder"])),
              (releaseFlags.isEmpty || (mode == "hybrid" && releaseFlags == ["--coreai-hybrid-release-after-first"] &&
                  freshFlags.isEmpty && invalidationFlags.isEmpty && recreateFlags.isEmpty)),
              (recreateFlags.isEmpty || (mode == "hybrid" && recreateFlags == ["--coreai-hybrid-recreate-between-turns"] &&
                  freshFlags.isEmpty && invalidationFlags.isEmpty && releaseFlags.isEmpty)),
              !args.contains(where: { $0.hasPrefix("--coreai-decoder") || $0.hasPrefix("--coreai-stateful") ||
                  $0 == "--coreai-encode-only" || $0 == "--coreai-decode-only" ||
                  $0.hasPrefix("--coreai-support-dir=") || $0.hasPrefix("--coreai-encoder-path=") }) else {
            throw ProbeError("WhisperKit proof requires baseline or hybrid and fixture 001, without legacy decoder/path flags. Fresh encoder is hybrid-only.")
        }
        return !freshFlags.isEmpty
    }

    // Deliberately only fixture 001 and two serial turns. No Core AI decoder is loaded.
    func whisperKitProof(mode: String, file: URL, runDirectory: URL) async throws -> WhisperKitProof {
        let args = ProcessInfo.processInfo.arguments
        let freshEncoder = try Self.whisperKitProofUsesFreshEncoder(args, mode: mode)
        let invalidateEncoder = args.contains("--coreai-hybrid-invalidate-encoder")
        let releaseAfterFirstTurn = args.contains("--coreai-hybrid-release-after-first")
        let recreateBetweenTurns = args.contains("--coreai-hybrid-recreate-between-turns")
        guard !invalidateEncoder || !encoderInvalidationAttempted else {
            throw ProbeError("Encoder invalidation was already attempted in this process. Stop for review.")
        }
        self.runDirectory = runDirectory; fixture = file.lastPathComponent; callIndex = 0
        let start = ProcessInfo.processInfo.systemUptime
        try event("whisperkit-prepare-before", fields: ["mode": mode,
            "os": ProcessInfo.processInfo.operatingSystemVersionString, "architecture": AIModel.deviceArchitectureName,
            "melCompute": "cpuAndGPU", "decoderCompute": "cpuAndNeuralEngine",
            "encoderCompute": mode == "baseline" ? "cpuAndNeuralEngine" : "CoreAI default",
            "coreMLCacheState": "unobserved; existing caches preserved", "freshEncoder": freshEncoder,
            "invalidateEncoder": invalidateEncoder])
        let support = URL.applicationSupportDirectory.appending(path: "PhoWhisperCS/phowhisper-cs-fp16-v1")
        let encoderURL = URL.applicationSupportDirectory.appending(path:
            "CoreAI/\(freshEncoder ? "PhoWhisperHybridFresh" : "PhoWhisperSplit")/phowhisper-cs-fp16-v1.encoder.\(AIModel.deviceArchitectureName).aimodelc")
        let verificationStart = ProcessInfo.processInfo.systemUptime
        let manifest = try Data(contentsOf: support.appending(path: "manifest.json"))
        guard Self.sha256(manifest) == "7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52" else {
            throw ProbeError("Accepted support manifest changed.")
        }
        struct Manifest: Decodable {
            struct File: Decodable { let bytes: Int; let sha256: String }
            let files: [String: File]
        }
        for (path, expected) in try JSONDecoder().decode(Manifest.self, from: manifest).files {
            let url = support.appending(path: path)
            guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == expected.bytes,
                  try Self.fingerprint(url) == expected.sha256 else { throw ProbeError("Support mismatch: \(path)") }
        }
        var hashes = ["supportManifest": Self.sha256(manifest), "audio": try Self.fingerprint(file)]
        guard hashes["audio"] == "e9789f09cf31930239ff5842a1b502103844481d4669fb7e0de77b69966b597f" else {
            throw ProbeError("Not the frozen fixture 001.")
        }
        if mode == "hybrid" { hashes["encoder"] = try Self.fingerprint(encoderURL) }
        if freshEncoder {
            // Original Mac h18p AOT tree, verified with this same fingerprint helper.
            guard AIModel.deviceArchitectureName == "h18p",
                  hashes["encoder"] == "590fcca5d35ea07d31b361a7809ad239a9c985a91d945fda9887852b9b02ec67" else {
                throw ProbeError("Fresh encoder differs from the original h18p AOT. Do not load it.")
            }
        }
        var timings = ["verification": ProcessInfo.processInfo.systemUptime - verificationStart]
        try event("whisperkit-verification-after", fields: ["assetSHA256": hashes])
        let baseline = CapturingCoreMLEncoder(owner: self)
        var hybrid: HybridEncoder?
        var encoderLoad: AssetTiming?
        if mode == "hybrid" {
            // Do not retain an AIModel while deleting its entry. The SDK rejects deletion of live entries.
            let cache = AIModelCache.default
            var cacheHit = try autoreleasepool { try cache.model(for: encoderURL, options: .default) != nil }
            if invalidateEncoder {
                try Task.checkCancellation()
                guard cacheHit else { throw ProbeError("Expected encoder cache entry is absent; no invalidation performed.") }
                encoderInvalidationAttempted = true
                try event("encoder-invalidation-before", fields: ["encoderPath": encoderURL.path,
                    "options": "default", "cacheLookupHit": cacheHit])
                // Explicit one-entry experiment only. Never deleteEntries(for:) or deleteAll().
                try cache.deleteEntry(for: encoderURL, options: .default)
                cacheHit = try autoreleasepool { try cache.model(for: encoderURL, options: .default) != nil }
                try event("encoder-invalidation-after", fields: ["cacheLookupHit": cacheHit])
            }
            try event("whisperkit-coreai-load-before", fields: ["encoderPath": encoderURL.path,
                "cacheLookupHit": cacheHit, "freshEncoder": freshEncoder])
            guard !freshEncoder || !cacheHit else {
                throw ProbeError("Fresh path already resolves to a cached specialization. Stop rather than retry the existing cache.")
            }
            let loaded = try await Self.loadAsset(encoderURL)
            try Self.validate(loaded.model, role: "encoder")
            let input = try Self.inputDescriptor(loaded.model, name: "input_features")
            guard input.scalarType == .float16, input.shape == [1, 80, 3000] else {
                throw ProbeError("Hybrid encoder requires the accepted fixed FP16 input.")
            }
            hybrid = HybridEncoder(function: loaded.function, input: input, owner: self)
            encoderLoad = loaded.timing
            try event("whisperkit-coreai-load-after", fields: ["cacheHit": loaded.timing.cacheHit,
                "lookup": loaded.timing.cacheLookupSeconds, "specialization": loaded.timing.specializationSeconds,
                "functionLoad": loaded.timing.functionLoadSeconds])
        }
        var activeEncoder: any AudioEncoding = hybrid.map { $0 as any AudioEncoding } ?? baseline
        let kit = try await WhisperKit(WhisperKitConfig(modelFolder: support.path, tokenizerFolder: support,
            computeOptions: ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine,
                                                textDecoderCompute: .cpuAndNeuralEngine),
            audioEncoder: activeEncoder, verbose: false, prewarm: false, load: false, download: false))
        do {
            let tokenizerStart = ProcessInfo.processInfo.systemUptime
            kit.tokenizer = try await PhoWhisperTokenizer.load(from: support)
            kit.textDecoder.isModelMultilingual = true
            struct Generation: Decodable { let suppress_tokens: [Int] }
            let suppression = try JSONDecoder().decode(Generation.self,
                from: Data(contentsOf: support.appending(path: "generation_config.json"))).suppress_tokens
            timings["tokenizer"] = ProcessInfo.processInfo.systemUptime - tokenizerStart
            try Task.checkCancellation()
            try event("whisperkit-prewarm-before")
            let prewarmStart = ProcessInfo.processInfo.systemUptime
            try await kit.prewarmModels()
            timings["prewarm"] = ProcessInfo.processInfo.systemUptime - prewarmStart
            timings["decoderPrewarm"] = kit.currentTimings.decoderSpecializationTime
            timings["encoderPrewarm"] = kit.currentTimings.encoderSpecializationTime
            try event("whisperkit-prewarm-after", fields: ["timings": timings])
            try Task.checkCancellation()
            try event("whisperkit-load-before")
            let loadStart = ProcessInfo.processInfo.systemUptime
            try await kit.loadModels()
            timings["load"] = ProcessInfo.processInfo.systemUptime - loadStart
            timings["decoderLoad"] = kit.currentTimings.decoderLoadTime
            timings["encoderLoad"] = kit.currentTimings.encoderLoadTime
            timings["prepare"] = ProcessInfo.processInfo.systemUptime - start
            guard kit.featureExtractor.melCount == 80, kit.featureExtractor.windowSamples == 480_000,
                  kit.audioEncoder.embedSize == 1280, kit.textDecoder.logitsSize == 51865 else {
                throw ProbeError("WhisperKit model contract changed.")
            }
            try event("whisperkit-load-after", fields: ["timings": timings])
            // Same policy as LocalConversationEngine.WhisperRecognizer, no handwritten decoding.
            var options = DecodingOptions(task: .transcribe, detectLanguage: true,
                skipSpecialTokens: true, windowClipTime: 0, concurrentWorkerCount: 1)
            options.temperatureFallbackCount = 0
            options.withoutTimestamps = true
            options.suppressBlank = true
            options.suppressTokens = suppression
            options.compressionRatioThreshold = nil
            options.logProbThreshold = nil
            options.firstTokenLogProbThreshold = nil
            options.noSpeechThreshold = nil
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: file.path)
            guard samples.count == 90_560, samples.allSatisfy(\.isFinite) else { throw ProbeError("Invalid fixture samples.") }
            var turns: [ProofTurn] = []
            for turn in 1...2 {
                try Task.checkCancellation()
                try event("whisperkit-transcribe-before", fields: ["turn": turn])
                let inferenceStart = ProcessInfo.processInfo.systemUptime
                let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
                let seconds = ProcessInfo.processInfo.systemUptime - inferenceStart
                try Task.checkCancellation()
                let result = ProofTurn(text: results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines),
                    languages: results.map(\.language), tokens: results.flatMap { $0.segments.map(\.tokens) }, seconds: seconds)
                try JSONEncoder().encode(results).write(to: runDirectory.appending(path: "turn-\(turn).json"), options: .atomic)
                let capture: EncoderCapture?
                if let hybrid { capture = await hybrid.capture } else { capture = baseline.capture }
                guard let capture else { throw ProbeError("Encoder capture missing.") }
                try capture.mel.withUnsafeBytes { try Data($0).write(to: runDirectory.appending(path: "turn-\(turn).mel.f32"), options: .atomic) }
                try capture.hidden.withUnsafeBytes { try Data($0).write(to: runDirectory.appending(path: "turn-\(turn).hidden.fp16"), options: .atomic) }
                turns.append(result)
                let proof = WhisperKitProof(mode: mode, timings: timings, assetSHA256: hashes, encoderLoad: encoderLoad, turns: turns)
                try JSONEncoder().encode(proof).write(to: runDirectory.appending(path: "whisperkit-proof.json"), options: .atomic)
                try event("whisperkit-transcribe-after", fields: ["turn": turn, "seconds": seconds,
                    "text": result.text, "languages": result.languages, "tokens": result.tokens])
                // A failed first fixture never automatically advances to another inference.
                guard result.text == "Yesterday I went to the supermarket.", result.languages == ["vi"] else {
                    throw ProbeError("Fixture 001 differs from accepted text/language. Stop for review.")
                }
                if turn == 1 && (releaseAfterFirstTurn || recreateBetweenTurns) {
                    try event("whisperkit-lifetime-release-before")
                    await kit.unloadModels()
                    kit.audioEncoder = baseline
                    activeEncoder = baseline
                    hybrid = nil
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    try event("whisperkit-lifetime-release-after", fields: [
                        "releasedEncoder": true, "releasedWhisperKitModels": true,
                        "recreateForSecondTurn": recreateBetweenTurns])
                    if releaseAfterFirstTurn {
                        try event("whisperkit-lifetime-check-complete")
                        return WhisperKitProof(mode: mode, timings: timings, assetSHA256: hashes,
                            encoderLoad: encoderLoad, turns: turns)
                    }
                    let reloadStart = ProcessInfo.processInfo.systemUptime
                    try event("whisperkit-between-turn-reload-before")
                    let reloaded = try await Self.loadAsset(encoderURL)
                    try Self.validate(reloaded.model, role: "encoder")
                    let replacementInput = try Self.inputDescriptor(reloaded.model, name: "input_features")
                    guard replacementInput.scalarType == .float16, replacementInput.shape == [1, 80, 3000] else {
                        throw ProbeError("Recreated hybrid encoder requires the accepted fixed FP16 input.")
                    }
                    let replacement = HybridEncoder(function: reloaded.function, input: replacementInput, owner: self)
                    hybrid = replacement
                    activeEncoder = replacement
                    kit.audioEncoder = activeEncoder
                    try await kit.loadModels()
                    timings["betweenTurnReload"] = ProcessInfo.processInfo.systemUptime - reloadStart
                    try event("whisperkit-between-turn-reload-after", fields: [
                        "cacheHit": reloaded.timing.cacheHit,
                        "functionLoad": reloaded.timing.functionLoadSeconds,
                        "loadSeconds": timings["betweenTurnReload"]!])
                }
                if turn == 2, result.tokens != turns[0].tokens { throw ProbeError("Repeated turn tokens differ.") }
            }
            await kit.unloadModels()
            try event("whisperkit-proof-complete", fields: ["corpusParityEstablished": false])
            // The local kit/adapter releases the Core AI function on return, including throwing returns.
            return WhisperKitProof(mode: mode, timings: timings, assetSHA256: hashes, encoderLoad: encoderLoad, turns: turns)
        } catch {
            await kit.unloadModels()
            try? event("whisperkit-error", fields: ["error": error.localizedDescription])
            throw error
        }
    }

    private static func decoderEmbeddings(_ values: [Float16]) throws -> MLMultiArray {
        guard values.count == 1500 * 1280, values.allSatisfy(\.isFinite) else {
            throw ProbeError("Expected finite FP16 [1,1500,1280] values.")
        }
        let result = try MLMultiArray(shape: [1, 1280, 1, 1500], dataType: .float16)
        let strides = result.strides.map(\.intValue)
        let p = result.dataPointer.assumingMemoryBound(to: Float16.self)
        for t in 0..<1500 { for c in 0..<1280 {
            p[c * strides[1] + t * strides[3]] = values[t * 1280 + c]
        }}
        return result
    }

    private static func readDecoderEmbeddings(_ a: MLMultiArray) throws -> [Float16] {
        guard a.shape.map(\.intValue) == [1, 1280, 1, 1500], a.dataType == .float16 else {
            throw ProbeError("WhisperKit embeddings must be FP16 [1,1280,1,1500].")
        }
        let strides = a.strides.map(\.intValue)
        let p = a.dataPointer.assumingMemoryBound(to: Float16.self)
        var values = [Float16](repeating: 0, count: 1500 * 1280)
        for t in 0..<1500 { for c in 0..<1280 {
            values[t * 1280 + c] = p[c * strides[1] + t * strides[3]]
        }}
        guard values.allSatisfy(\.isFinite) else { throw ProbeError("Non-finite decoder embeddings.") }
        return values
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // Sorted child-name -> digest JSON recursively binds names and contents, independent of container URL.
    private static func fingerprint(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw ProbeError("Symlinks are not diagnostic assets.") }
        if values.isDirectory == true {
            var children: [String: String] = [:]
            for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                                     options: [.skipsHiddenFiles]) {
                children[child.lastPathComponent] = try fingerprint(child)
            }
            return sha256(try JSONSerialization.data(withJSONObject: children, options: [.sortedKeys, .withoutEscapingSlashes]))
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        // FileHandle's Foundation buffers otherwise accumulate until this multi-GB scan returns.
        while try autoreleasepool(invoking: { () throws -> Bool in
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { return false }
            hash.update(data: data)
            return true
        }) {}
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func checkedArgmax(
        _ row: [Float], allowed: Set<Int>?, suppressed: Set<Int>
    ) throws -> Int {
        guard !row.isEmpty, row.allSatisfy(\.isFinite) else { throw ProbeError("Non-finite or empty raw logits.") }
        let candidates = allowed?.sorted() ?? Array(row.indices)
        var best: Int?
        for token in candidates where row.indices.contains(token) && !suppressed.contains(token) {
            if best == nil || row[token] > row[best!] { best = token }
        }
        guard let best else { throw ProbeError("No valid token survived filtering.") }
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
        let runID: String
        let status: String
        let architecture: String
        let mode: String
        let preparation: CoreAIPhoWhisper.Preparation?
        let fixturesDirectory: String
        let files: [FileResult]
        let whisperKitProof: CoreAIPhoWhisper.WhisperKitProof?
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
    private(set) var whisperKitProof: CoreAIPhoWhisper.WhisperKitProof?
    static var whisperKitMode: String? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--coreai-whisperkit=") }
            .map { String($0.dropFirst("--coreai-whisperkit=".count)) }
    }
    @ObservationIgnored private var runDirectory: URL?
    @ObservationIgnored private let recognizer = CoreAIPhoWhisper()

    func run() async {
        guard !running else { return }
        running = true; defer { running = false }
        error = nil; results = []; preparation = nil; whisperKitProof = nil; status = "Preparing split Core AI PhoWhisper…"
        runDirectory = URL.documentsDirectory.appending(path: "CoreAI/PhoWhisper/Runs/\(UUID().uuidString)")
        do {
            guard let runDirectory else { throw CoreAIPhoWhisper.ProbeError("Missing run directory.") }
            try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
            let directory = try Self.fixturesDirectory()
            try writeReport(directory: directory, error: nil)
            if let mode = Self.whisperKitMode {
                status = "Running WhisperKit \(mode) proof: fixture 001"
                try writeReport(directory: directory, error: nil)
                whisperKitProof = try await recognizer.whisperKitProof(mode: mode,
                    file: directory.appending(path: "001.wav"), runDirectory: runDirectory)
                status = "Fixture 001 proof complete. Full parity and startup targets remain unproven."
                try writeReport(directory: directory, error: nil)
                return
            }
            let config = try CoreAIPhoWhisper.Config.resolve()
            preparation = try await recognizer.prepare(config, runDirectory: runDirectory)
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
                    throw error // First failure stops the corpus; never continue past an invalid fixture.
                }
                try writeReport(directory: directory, error: nil)
            }
            status = results.allSatisfy({ $0.result == nil })
                ? "Diagnostic/checkpoint complete. No transcript produced."
                : "Corpus complete: \(results.filter { $0.result != nil }.count)/\(files.count) transcribed"
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
        guard let runDirectory else { return }
        let report = Report(
            runID: runDirectory.lastPathComponent, status: status,
            architecture: AIModel.deviceArchitectureName,
            mode: Self.whisperKitMode.map { "whisperkit-\($0)" } ??
                ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--coreai-stateful=") }) ??
                ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--coreai-decoder-case=") }) ??
                (ProcessInfo.processInfo.arguments.contains("--coreai-encode-only") ? "encode-only" :
                (ProcessInfo.processInfo.arguments.contains("--coreai-decode-only") ? "decode-only" : "sequential")),
            preparation: preparation,
            fixturesDirectory: directory.path, files: results, whisperKitProof: whisperKitProof, error: error)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let url = runDirectory.appending(path: "report.json")
        try data.write(to: url, options: .atomic)
        // Compatibility pointer only. Historical evidence lives in the unique run directory.
        try data.write(to: URL.documentsDirectory.appending(path: "coreai-asr-probe.json"), options: .atomic)
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
                        Text(String(format: "Verification/frontend/tokenizer %.3f s · models load sequentially per file", p.totalSeconds))
                            .font(.caption.monospacedDigit())
                    }
                    if !probe.reportPath.isEmpty {
                        Text("Report: \(probe.reportPath)").font(.caption).textSelection(.enabled)
                    }
                    if let error = probe.error {
                        Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                    }
                    if let proof = probe.whisperKitProof, let first = proof.turns.first {
                        Text(first.text).textSelection(.enabled)
                        Text(String(format: "Prepare %.3f s · first transcript %.3f s", proof.timings["prepare"] ?? 0, first.seconds))
                            .font(.caption.monospacedDigit())
                    }
                    Button(probe.running ? "Working…" : (CoreAIASRProbe.whisperKitMode == nil ? "Run staged corpus" : "Run fixture 001 proof")) {
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
                            } else {
                                Text("Diagnostic/checkpoint only, not a transcript.").font(.caption)
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
