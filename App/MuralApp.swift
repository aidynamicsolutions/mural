#if (DEBUG || MURAL_COREAI_W8) && canImport(CoreAI)
import CoreAI
import ArgmaxCore
#endif
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
        #if MURAL_FIRERED_FILE_PROBE
        // The file probe must not open/migrate learning data or create the normal audio owner.
        if FireRedFileProbe.requested { return }
        #endif
        let args = ProcessInfo.processInfo.arguments
        #if (DEBUG || MURAL_COREAI_W8) && canImport(CoreAI)
        let coreAIProbeRequested = CoreAIASRProbe.requested
        #else
        let coreAIProbeRequested = false
        #endif
        let inMemory = args.contains("--preview") || AudioVerification.requested || coreAIProbeRequested
        do { _store = State(initialValue: try LearningStore(inMemory: inMemory)) }
        catch { _startupError = State(initialValue: "Mural couldn’t open its learning record. Your existing data has not been replaced.") }
    }

    @ViewBuilder private var mainContent: some View {
        if let store {
            RootView(store: store).preferredColorScheme(.light)
        } else {
            ContentUnavailableView(
                "Let’s try again",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text(startupError ?? "The learning record is unavailable.")
            ).preferredColorScheme(.light)
        }
    }

    var body: some Scene {
        WindowGroup {
            #if MURAL_FIRERED_FILE_PROBE
            if FireRedFileProbe.requested {
                FireRedFileProbe()
            } else {
                mainContent
            }
            #elseif (DEBUG || MURAL_COREAI_W8) && canImport(CoreAI)
            if CoreAIASRProbe.requested {
                CoreAIASRProbeView().preferredColorScheme(.light)
            } else {
                mainContent
            }
            #else
            mainContent
            #endif
        }
    }
}

#if (DEBUG || MURAL_COREAI_W8) && canImport(CoreAI)
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

    // Product-gate ownership is deliberately kept on this actor. The historical
    // probe above remains unchanged; this state is only used by the bounded gate.
    private var productState: ProductState = .idle
    private var productKit: WhisperKit?
    private var productEncoder: (any AudioEncoding)?
    private var productModel: AIModel?
    private var productFunction: InferenceFunction?
    private var productInput: NDArrayDescriptor?
    private var productV3Identity: W8RuntimeIdentitySpec?
    private var productV3ChallengeInput: NDArrayDescriptor?
    private var productSuppressionTokens: [Int] = []
    private var productCancellationController: ProductCancellationController?
    private var productRunDirectory: URL?
    private var productSessionID = ""
    private var productGeneration = 0
    private var productTurnNumber = 0
    private var productMelHashes: [String] = []
    private var productHiddenHashes: [String] = []
    private var productBeforeEncoderMemory: ProductMemory?
    private var productAfterEncoderMemory: ProductMemory?
    private var productAfterTranscriptMemory: ProductMemory?
    private var productEncoderStarted: Double?
    private var productEncoderElapsed = 0.0
    private var productDecoderElapsed = 0.0
    private var productWarningCount: (@Sendable () async -> Int)?
    private var productCompanionStart: (@MainActor @Sendable () -> Void)?
    private var productUnderlyingInferenceReturned = false
    private var productActiveInferenceCount = 0
    private var productEncoderBusy = false
    private var productQuiescenceWaiters: [CheckedContinuation<Void, Never>] = []
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
        try PhoWhisperStagedEncoder.copyEncoderOutput(hidden)
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

    private static func loadAsset(_ url: URL, options: SpecializationOptions = .default,
                                  requireCached: Bool = false, functionName: String = "main") async throws
      -> (model: AIModel, function: InferenceFunction, timing: AssetTiming) {
        let logger = Logger(subsystem: "no.william.mural", category: "CoreAIProductGate")
        var stage = "cache-access"
        do {
            let cache = AIModelCache.default
            let cacheStart = ProcessInfo.processInfo.systemUptime
            stage = "cache-lookup"
            let cached = try cache.model(for: url, options: options)
            let lookup = ProcessInfo.processInfo.systemUptime - cacheStart
            logger.notice("coreai_cache_lookup asset=\(url.lastPathComponent, privacy: .public) hit=\(cached != nil, privacy: .public) required=\(requireCached, privacy: .public)")
            guard !requireCached || cached != nil else {
                throw ProbeError("Required cached specialization is absent; no specialization or inference attempted.")
            }
            let model: AIModel
            let specialization: Double
            if let cached { model = cached; specialization = 0 }
            else {
                let start = ProcessInfo.processInfo.systemUptime
                stage = "specialization"
                model = try await AIModel.specialize(
                    contentsOf: url, options: options, cachePolicy: .persistent)
                specialization = ProcessInfo.processInfo.systemUptime - start
            }
            let start = ProcessInfo.processInfo.systemUptime
            stage = "function-load"
            logger.notice("coreai_function_load_begin asset=\(url.lastPathComponent, privacy: .public) function=\(functionName, privacy: .public)")
            guard let function = try model.loadFunction(named: functionName) else {
                throw ProbeError("Missing \(functionName) function in \(url.lastPathComponent).")
            }
            logger.notice("coreai_function_load_complete asset=\(url.lastPathComponent, privacy: .public) function=\(functionName, privacy: .public)")
            return (
                model, function,
                AssetTiming(
                    path: url.path, cacheHit: cached != nil, cacheLookupSeconds: lookup,
                    specializationSeconds: specialization,
                    functionLoadSeconds: ProcessInfo.processInfo.systemUptime - start)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let error = error as NSError
            logger.error("coreai_load_failed stage=\(stage, privacy: .public) domain=\(error.domain, privacy: .public) code=\(error.code, privacy: .public)")
            throw ProbeError("Core AI \(stage) failed for \(url.lastPathComponent): \(error.domain)(\(error.code)) \(error.userInfo)")
        }
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
        try PhoWhisperStagedEncoder.readAcceptedMel(a)
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

    private static func fillFloat16(_ a: inout NDArray, values: [Float16]) throws {
        guard a.scalarType == .float16, values.count == a.shape.reduce(1, *) else {
            throw ProbeError("FP16 input size/type mismatch.")
        }
        var view = a.mutableView(as: Float16.self)
        view.copyElements(fromContentsOf: values)
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
            audioEncoder: activeEncoder, textDecoder: ProductDecoder(owner: self), verbose: false, prewarm: false, load: false, download: false))
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
        try PhoWhisperStagedEncoder.decoderEmbeddings(values)
    }

    private static func readDecoderEmbeddings(_ a: MLMultiArray) throws -> [Float16] {
        try PhoWhisperStagedEncoder.readDecoderEmbeddings(a)
    }

    private static func sha256(_ data: Data) -> String {
        PhoWhisperStagedEncoder.sha256(data)
    }

    // Sorted child-name -> digest JSON recursively binds names and contents, independent of container URL.
    private static func fingerprint(_ url: URL) throws -> String {
        try PhoWhisperStagedEncoder.fingerprint(url)
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
        let productGate: CoreAIPhoWhisper.ProductReport?
        let memoryWarnings: Int
        let error: String?
    }

    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains("--coreai-asr-probe") ||
            CoreAIPhoWhisper.productGateRequested || W8TinyProbe.requested
    }
    static var autoRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--coreai-asr-auto") ||
            CoreAIPhoWhisper.productGateRequested || W8TinyProbe.requested
    }

    private(set) var running = false
    private(set) var status = "Ready"
    private(set) var preparation: CoreAIPhoWhisper.Preparation?
    private(set) var results: [FileResult] = []
    private(set) var error: String?
    private(set) var reportPath = ""
    private(set) var whisperKitProof: CoreAIPhoWhisper.WhisperKitProof?
    private(set) var productGate: CoreAIPhoWhisper.ProductReport?
    private(set) var memoryWarnings = 0
    @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol?
    static var whisperKitMode: String? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--coreai-whisperkit=") }
            .map { String($0.dropFirst("--coreai-whisperkit=".count)) }
    }
    @ObservationIgnored private var runDirectory: URL?
    @ObservationIgnored private var vadReplayTask: Task<Void, Error>?
    @ObservationIgnored private let recognizer = CoreAIPhoWhisper()

    init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("UIApplicationDidReceiveMemoryWarningNotification"),
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.memoryWarnings += 1
                    self?.vadReplayTask?.cancel()
                    Logger(subsystem: "no.william.mural", category: "CoreAIProductGate")
                        .fault("ios_memory_warning count=\(self?.memoryWarnings ?? 0, privacy: .public)")
                }
            }
    }

    deinit {
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
    }

    func run() async {
        guard !running, memoryWarnings == 0 else { return }
        running = true; defer { running = false }
        error = nil; results = []; preparation = nil; whisperKitProof = nil; productGate = nil; status = "Preparing split Core AI PhoWhisper…"
        runDirectory = URL.documentsDirectory.appending(path: "CoreAI/PhoWhisper/Runs/\(UUID().uuidString)")
        do {
            guard let runDirectory else { throw CoreAIPhoWhisper.ProbeError("Missing run directory.") }
            try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
            if W8TinyProbe.requested {
                status = "Running tiny cache isolation (no speech)"
                try writeReport(directory: runDirectory, error: nil)
                try await W8TinyProbe.shared.run(directory: runDirectory,
                    warningCount: { @MainActor [weak self] in self?.memoryWarnings ?? 1 })
                status = ProcessInfo.processInfo.arguments.contains("--w8-tiny-source")
                    ? "Tiny source diagnostic complete (not an AOT isolation pass)"
                    : "Tiny cache isolation complete"
                try writeReport(directory: runDirectory, error: nil)
                return
            }
            let directory = try Self.fixturesDirectory()
            try writeReport(directory: directory, error: nil)
            if ProcessInfo.processInfo.arguments.contains("--asr-vad-replay") {
                status = "Comparing saved recordings with VAD trimming"
                let task = Task {
                    try await LocalConversationEngine.replayVADRecordings(directory: directory,
                        reportURL: runDirectory.appending(path: "vad-replay.json"))
                }
                vadReplayTask = task
                let observer = NotificationCenter.default.addObserver(
                    forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in task.cancel() }
                defer {
                    NotificationCenter.default.removeObserver(observer)
                    vadReplayTask = nil
                }
                try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                guard memoryWarnings == 0 else { throw CoreAIPhoWhisper.ProbeError("VAD replay stopped after a memory warning.") }
                status = "VAD replay complete: 22 saved recordings"
                try writeReport(directory: directory, error: nil)
                return
            }
            if CoreAIPhoWhisper.productGateRequested {
                let config = try CoreAIPhoWhisper.ProductConfig.resolve()
                status = "Running Core AI hybrid product gate: \(config.mode)"
                try writeReport(directory: directory, error: nil)
                var companions: Task<Void, Error>?
                defer { companions?.cancel() }
                let coexistence = ProcessInfo.processInfo.arguments.contains("--coreai-product-coexistence")
                let startCompanions: (@MainActor @Sendable () -> Void)?
                if coexistence {
                    startCompanions = { @MainActor in
                        companions = Task { @MainActor in
                            let audio = LocalConversationEngine()
                            let tutor = LocalTutorModel()
                            defer { audio.stop() }
                            Logger().notice("coexistence_begin")
                            async let speech: Void = audio.speak("Yesterday I went to the supermarket. I bought some apples and a loaf of bread. Today I am practising how to describe my shopping trip in English.")
                            async let reply = tutor.reply(to: "Yesterday I went to the supermarket. Help me describe what I bought in one short sentence.")
                            _ = try await (speech, reply)
                            Logger().notice("coexistence_complete")
                        }
                    }
                } else { startCompanions = nil }
                productGate = try await recognizer.productGate(config, fixturesDirectory: directory,
                    runDirectory: runDirectory, warningCount: { @MainActor [weak self] in self?.memoryWarnings ?? 0 },
                    companionStart: startCompanions)
                try await companions?.value
                status = "Product gate complete: \(productGate?.status ?? "unknown")"
                try writeReport(directory: directory, error: nil)
                return
            }
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
            if let directory = runDirectory {
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
            fixturesDirectory: directory.path, files: results, whisperKitProof: whisperKitProof,
            productGate: productGate, memoryWarnings: memoryWarnings, error: error)
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

extension CoreAIPhoWhisper {
    fileprivate enum ProductState: String, Codable, Sendable {
        case idle, preparing, ready, transcribing, tearingDown, readyForRecreate
    }

    fileprivate static let productGateRequested = ProcessInfo.processInfo.arguments.contains(
        "--coreai-hybrid-product-gate")
    fileprivate static let productSupportManifestSHA256 =
        "7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52"
    fileprivate static let productEncoderFingerprintByArchitecture = [
        "h18p": "b13ccaf3fa91098a21bc81786843e138ad2e6cde4a9fdcccece6d531b0f9d034"
    ]
    fileprivate static let productFrozenAudioSHA256: [String: String] = [
        "001.wav": "e9789f09cf31930239ff5842a1b502103844481d4669fb7e0de77b69966b597f",
        "002.wav": "a4105a2051580587e2712c0b8aa49c8c82d8012b4128771b65683829cd3f9766",
        "003.wav": "49183e01bc787544a7e6b1776d8590b27e83634b71dd6831864e8c480a73d482",
        "004.wav": "760a6aaa4cd40db22d7ea317ed606e05a1a993fc4677fd34eed75a3ff261405a",
        "005.wav": "ee6acf2a2f96151d709c78b680fc3a0007764dc4ef4817c49964975d10aced4c",
        "006.wav": "b38f61202c920a2e21f503f1e303e5c1c3db31a817d89be4a2ae77cef854e3a5",
        "007.wav": "93a8ddcb9373e56cd67a071f3ba0998b07b130718ab5229d6307f7bf9f904cc0",
        "008.wav": "e7468cd7ade96870d94934102a95ea24e5c70b2acaf964950d08586e8b1101bf",
        "009.wav": "fd2bf28ffd05745d9fa7b1675b0a15e9a0c816057b4c42f40a583532243b8505",
        "010.wav": "1a98829d4262a53211e621079ef1ae069a9008a782970c4028d843695a0797a9",
        "011.wav": "9b7ee366d6665c83955cc4c01afe9aaa41b6cecd26256b9ca5310d65016398c5",
        "012.wav": "b199c59f745f1c79aa91814b6dde59d03a9c925a68de412ee159c5e52ae84b18",
        "013.wav": "6100478ca5bc19192710fa08baa1929bb78eeae48094a4bdc741c4372131ec72",
        "014.wav": "5fe4b1a6cbcde095b8cedb33dbc5ea3dc7a157795ab2a72645cb5320ea516fac",
        "015.wav": "51fc170162f63f5fab38c35011bcf787aabb36d7e2dd556cad7be5843fba39b4",
        "016.wav": "65ac106a3ffdd9d92cd8b368d8414b6732519bf0dd659a9f3cdd64c5be22d214",
        "017.wav": "c599899c7a6b873135198363b1fad6096d457e23a352b41893fd100819e876fd",
        "018.wav": "8ca9cb899430724dc90f1c9c61e5fe677470e6b1241c0c42073652da72d2a344",
        "019.wav": "bc3a324e35577ac6ec16831edc02c2fe3c02ab13d17f684dfe6d7348beea6279",
        "020.wav": "37c6d0dcfc414e3971fcf149698793af8488ed48c1970801252e517b05740415",
        "021.wav": "92488954545250138b7591f8f26efdd996b6977f168cf6aaa0810c815214e732",
        "022.wav": "b2966792f9b9feffb54bb5921b08c0fe1a86665b6b576927d50de80d9eb645bf"
    ]

    fileprivate struct ProductConfig: Sendable {
        let mode: String
        let corpus: Bool
        let turns: Int
        let lifecycle: String
        let sequence: [String]
        let cancelAt: String?
        let candidate: PhoWhisperStagedEncoder.CompressionCandidate?
        let selection: PhoWhisperStagedEncoder.Selection

        static func resolve() throws -> Self {
            let args = ProcessInfo.processInfo.arguments
            let productFlags = args.filter { $0.hasPrefix("--coreai-product-") }
            let allowedExact = Set(["--coreai-product-corpus", "--coreai-product-coexistence"])
            for flag in productFlags where !allowedExact.contains(flag) &&
                !["--coreai-product-mode=", "--coreai-product-turns=", "--coreai-product-lifecycle=",
                  "--coreai-product-sequence=", "--coreai-product-cancel-at="].contains(where: { flag.hasPrefix($0) }) {
                throw ProbeError("Unknown product-gate flag: \(flag)")
            }
            let prohibited = args.contains { arg in
                arg.hasPrefix("--coreai-decoder") || arg.hasPrefix("--coreai-stateful") ||
                arg == "--coreai-encode-only" || arg == "--coreai-decode-only" ||
                arg.hasPrefix("--coreai-hybrid-invalidate-encoder") ||
                arg.hasPrefix("--coreai-hybrid-fresh-encoder") ||
                arg.hasPrefix("--coreai-hybrid-release-after-first") ||
                arg.hasPrefix("--coreai-hybrid-recreate-between-turns") ||
                arg.hasPrefix("--coreai-support-dir=") || arg.hasPrefix("--coreai-encoder-path=") ||
                arg == "--coreai-download" || arg == "--coreai-repair" ||
                arg.hasPrefix("--coreai-fixture=")
            }
            guard !prohibited else {
                throw ProbeError("Product-gate mode rejects decoder, diagnostic, cache, download, and legacy fixture flags.")
            }

            func values(_ prefix: String) -> [String] {
                args.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
            }
            func one(_ prefix: String) throws -> String? {
                let result = values(prefix)
                guard result.count <= 1 else { throw ProbeError("Duplicate product-gate flag: \(prefix)") }
                return result.first
            }
            let mode = try one("--coreai-product-mode=") ?? "hybrid"
            guard ["baseline", "hybrid", "encoder-only", "encoder-gpu-only", "decoder-only", "encoder-rebuild-only", "staged", "staged-gpu", "staged-gpu-encode"].contains(mode) else {
                throw ProbeError("Unknown product-gate mode.")
            }
            let selection = try PhoWhisperStagedEncoder.resolveSelection()
            let compressed = selection.legacy
            if compressed != nil && !["staged-gpu", "staged-gpu-encode"].contains(mode) {
                throw ProbeError("Compression candidates require the sequential GPU-preferred owner.")
            }
            if let v3 = selection.v3 {
                if v3.supportIdentity == "phowhisper-cs-pal6-g16-v1" {
                    guard ["staged-gpu", "staged-gpu-encode"].contains(mode) else {
                        throw ProbeError("PAL6 decoder trial requires sequential GPU encoding.")
                    }
                }
                guard v3.format != "pal6" || ["staged-gpu", "staged-gpu-encode"].contains(mode) else {
                    throw ProbeError("PAL6 qualification requires the sequential GPU-preferred owner.")
                }
                guard ["hybrid", "staged-gpu", "staged-gpu-encode", "encoder-only", "encoder-gpu-only"].contains(mode) else {
                    throw ProbeError("The v3 selection requires an encoder-owning product mode.")
                }
                guard v3.identity.kind == "encoder", v3.identity.transport == "packed" else {
                    throw ProbeError("The product gate accepts only the audited packed v3 encoder.")
                }
            }
            if args.contains("--coreai-product-coexistence"), !mode.hasPrefix("staged") {
                throw ProbeError("Coexistence qualification requires staged mode.")
            }
            let corpusCount = args.filter { $0 == "--coreai-product-corpus" }.count
            guard corpusCount <= 1 else { throw ProbeError("Duplicate --coreai-product-corpus.") }
            let corpus = corpusCount == 1
            if mode == "staged-gpu-encode", corpus {
                throw ProbeError("Encoder-only qualification uses explicit saved inputs, not the scored corpus.")
            }
            if mode == "staged-gpu-encode", args.contains("--coreai-product-coexistence") {
                throw ProbeError("Encoder-only qualification cannot run a decoder companion.")
            }
            let rawTurns = try one("--coreai-product-turns=") ?? "1"
            guard let turns = Int(rawTurns), (1...20).contains(turns) else {
                throw ProbeError("Product-gate turns must be an integer from 1 through 20.")
            }
            let lifecycle = try one("--coreai-product-lifecycle=") ?? "recreate"
            guard lifecycle == "recreate" else {
                throw ProbeError("Product-gate only permits the explicit recreate lifecycle.")
            }
            let rawSequence = try one("--coreai-product-sequence=")
            let sequence = rawSequence.map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) } ?? []
            guard sequence.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("\\") }) else {
                throw ProbeError("Product-gate sequence entries must be local filenames.")
            }
            guard !(corpus && !sequence.isEmpty) else {
                throw ProbeError("Corpus and explicit product sequence cannot be combined.")
            }
            let cancelAt = try one("--coreai-product-cancel-at=")
            if let cancelAt {
                guard ["prepare", "encoder", "decoder"].contains(cancelAt) else {
                    throw ProbeError("Unknown cancellation boundary.")
                }
                guard !corpus && turns == 1 && (sequence.isEmpty || sequence == ["001.wav"]) else {
                    throw ProbeError("Cancellation runs must use one explicit local turn.")
                }
            }
            guard !corpus || turns == 1 else {
                throw ProbeError("Corpus runs visit all 22 fixtures once; do not combine with a turn count.")
            }
            if mode.hasPrefix("staged") {
                guard turns <= 10 else {
                    throw ProbeError("Staged qualification permits up to ten turns.")
                }
                if mode != "staged-gpu-encode" {
                    guard sequence.isEmpty || sequence.allSatisfy({ $0 == "001.wav" }) else {
                        throw ProbeError("Staged decoder qualification uses the frozen corpus or fixture-001 turns.")
                    }
                }
            }
            if mode.hasSuffix("-only") {
                guard !corpus, turns == 1, sequence.isEmpty, cancelAt == nil else {
                    throw ProbeError("Loading-only decomposition rejects inference and cancellation options.")
                }
            }
            guard CoreAIPhoWhisper.productEncoderFingerprintByArchitecture[AIModel.deviceArchitectureName] != nil || mode == "baseline" else {
                throw ProbeError("No bound production encoder fingerprint for architecture \(AIModel.deviceArchitectureName).")
            }
            return Self(mode: mode, corpus: corpus, turns: turns, lifecycle: lifecycle,
                        sequence: sequence, cancelAt: cancelAt, candidate: compressed, selection: selection)
        }

        func withoutCancellation() -> Self {
            Self(mode: mode, corpus: false, turns: 1, lifecycle: "recreate",
                 sequence: sequence.isEmpty ? ["001.wav"] : [sequence[0]], cancelAt: nil,
                 candidate: candidate, selection: selection)
        }
    }

    fileprivate struct ProductMemory: Codable, Sendable {
        let footprintBytes: UInt64
        let processRSSPeakBytes: UInt64
    }
    fileprivate struct ProductPreparation: Codable, Sendable {
        let index: Int
        let state: String
        let totalSeconds: Double
        let assetVerificationSeconds: Double
        let coreAICacheHit: Bool?
        let coreAICacheLookupSeconds: Double?
        let coreAISpecializationSeconds: Double?
        let coreAIFunctionLoadSeconds: Double?
        let tokenizerSeconds: Double
        let whisperKitPrewarmSeconds: Double
        let whisperKitLoadSeconds: Double
        let readySeconds: Double
        let memoryBefore: ProductMemory
        let memoryAfter: ProductMemory
        let thermalBefore: Int
        let thermalAfter: Int
    }
    fileprivate struct ProductTurnTiming: Codable, Sendable {
        let totalSeconds: Double
        let melSeconds: Double
        let encoderSeconds: Double
        let decoderSeconds: Double
        let decodingInitSeconds: Double
        let decodingLoopSeconds: Double
        let decodingPredictionsSeconds: Double
        let decodingNonPredictionSeconds: Double
        let pipelineSeconds: Double
    }
    fileprivate struct ProductTurn: Codable, Sendable {
        let turn: Int
        let file: String
        let sampleCount: Int
        let audioSHA256: String
        let rawTranscript: String?
        let normalizedTranscript: String?
        let detectedLanguages: [String]
        let generatedTokens: [[Int]]
        let segmentTokens: [[Int]]
        let melSHA256: [String]
        let encoderHiddenSHA256: [String]
        let timings: ProductTurnTiming?
        let memoryBeforeEncoder: ProductMemory?
        let memoryAfterEncoder: ProductMemory?
        let memoryAfterTranscript: ProductMemory?
        let thermalBefore: Int
        let thermalAfter: Int
        let termination: String
        let error: String?
    }
    fileprivate struct ProductCancellation: Codable, Sendable {
        let requested: Bool
        let point: String?
        let requestedUptime: Double?
        let underlyingExecutionReturned: Bool
        var teardownCompleted: Bool
        var recoverySucceeded: Bool
        var recoveryTurnCount: Int
    }
    fileprivate struct ProductReport: Codable, Sendable {
        let date: Date
        let runID: String
        let mode: String
        let lifecycle: String
        let requestedTurns: Int
        let corpusRequested: Bool
        let expectedCorpusCount: Int
        let architecture: String
        let supportManifestSHA256: String
        let encoderArtifactSHA256: String?
        let expectedEncoderArtifactSHA256: String?
        let modelPrecision: String
        let melBoundary: String
        let tokenizer: String
        let decodingOptions: [String: String]
        var terminal = false
        var status: String
        var stateAtEnd: String
        var preparations: [ProductPreparation]
        var turns: [ProductTurn]
        var cancellation: ProductCancellation?
        var errors: [String]
    }

    fileprivate actor ProductCancellationController {
        let target: String?
        private var operation: Task<ProductReport, Never>?
        private(set) var requestedPoint: String?
        private(set) var requestedUptime: Double?
        private var armed = false

        init(target: String?) { self.target = target }

        func install(_ operation: Task<ProductReport, Never>) {
            self.operation = operation
            if requestedPoint != nil { operation.cancel() }
        }

        func reached(_ point: String) {
            guard target == point, !armed else { return }
            armed = true
            Task {
                // Inject while the operation is active; event timestamps must confirm overlap.
                try? await Task.sleep(for: .milliseconds(10))
                request(point)
            }
        }

        private func request(_ point: String) {
            requestedPoint = point
            requestedUptime = ProcessInfo.processInfo.systemUptime
            operation?.cancel()
            Logger(subsystem: "no.william.mural", category: "CoreAIProductGate")
                .notice("swift_task_cancellation_requested point=\(point, privacy: .public) uptime=\(self.requestedUptime ?? 0, privacy: .public)")
        }

        func snapshot() -> (point: String?, uptime: Double?) {
            (requestedPoint, requestedUptime)
        }
    }

    private final class ProductReplayEncoder: AudioEncoding {
        let embedSize: Int? = 1280
        let hidden: [Float16]
        let melHash: String
        weak var owner: CoreAIPhoWhisper?
        init(hidden: [Float16], melHash: String, owner: CoreAIPhoWhisper) {
            self.hidden = hidden; self.melHash = melHash; self.owner = owner
        }
        func encodeFeatures(_ features: any FeatureExtractorOutputType) async throws -> (any AudioEncoderOutputType)? {
            guard let array = features as? MLMultiArray, let owner else { throw ProbeError("Missing replay mel/owner") }
            let values = try CoreAIPhoWhisper.readAcceptedMel(array)
            guard CoreAIPhoWhisper.productFloatHash(values) == melHash else { throw ProbeError("Staged mel differs from accepted WhisperKit frontend") }
            await owner.productReplayConsumed(melHash: melHash, hidden: hidden)
            return try CoreAIPhoWhisper.decoderEmbeddings(hidden)
        }
    }

    // Delegates every decoding operation to the existing accepted decoder.
    private final class ProductDecoder: TextDecoding, WhisperMLModel {
        let decoder = TextDecoder()
        weak var owner: CoreAIPhoWhisper?
        init(owner: CoreAIPhoWhisper) { self.owner = owner }
        var model: MLModel? { get { decoder.model } set { decoder.model = newValue } }
        var tokenizer: (any WhisperTokenizer)? { get { decoder.tokenizer } set { decoder.tokenizer = newValue } }
        var isModelMultilingual: Bool { get { decoder.isModelMultilingual } set { decoder.isModelMultilingual = newValue } }
        var logitsFilters: [any LogitsFiltering]? { get { decoder.logitsFilters } set { decoder.logitsFilters = newValue } }
        var supportsWordTimestamps: Bool { decoder.supportsWordTimestamps }
        var logitsSize: Int? { decoder.logitsSize }
        var kvCacheEmbedDim: Int? { decoder.kvCacheEmbedDim }
        var kvCacheMaxSequenceLength: Int? { decoder.kvCacheMaxSequenceLength }
        var windowSize: Int? { decoder.windowSize }
        var embedSize: Int? { decoder.embedSize }
        func predictLogits(_ inputs: any TextDecoderInputType) async throws -> (any TextDecoderOutputType)? {
            try await decoder.predictLogits(inputs)
        }
        func prepareDecoderInputs(withPrompt prompt: [Int]) throws -> any DecodingInputsType {
            try decoder.prepareDecoderInputs(withPrompt: prompt)
        }
        func prefillDecoderInputs(_ inputs: any DecodingInputsType, withOptions options: DecodingOptions?) async throws -> any DecodingInputsType {
            try await decoder.prefillDecoderInputs(inputs, withOptions: options)
        }
        func detectLanguage(from output: any AudioEncoderOutputType, using inputs: any DecodingInputsType,
                            sampler: any TokenSampling, options: DecodingOptions, temperature: FloatType) async throws -> DecodingResult {
            let start = ProcessInfo.processInfo.systemUptime
            try await owner?.productDecoderBegin(phase: "language")
            do {
                let result = try await decoder.detectLanguage(from: output, using: inputs, sampler: sampler, options: options, temperature: temperature)
                await owner?.productDecoderEnd(start: start, phase: "language")
                return result
            } catch {
                await owner?.productDecoderEnd(start: start, phase: "language", error: error.localizedDescription)
                throw error
            }
        }
        func decodeText(from output: any AudioEncoderOutputType, using inputs: any DecodingInputsType,
                        sampler: any TokenSampling, options: DecodingOptions, callback: TranscriptionCallback?) async throws -> DecodingResult {
            let start = ProcessInfo.processInfo.systemUptime
            try await owner?.productDecoderBegin(phase: "text")
            do {
                let result = try await decoder.decodeText(from: output, using: inputs, sampler: sampler, options: options, callback: callback)
                await owner?.productDecoderEnd(start: start, phase: "text")
                return result
            } catch {
                await owner?.productDecoderEnd(start: start, phase: "text", error: error.localizedDescription)
                throw error
            }
        }
    }

    private func productRequireNoWarnings() async throws {
        guard await productWarningCount?() == 0 else { throw ProbeError("Memory warning observed; stop qualification, no further turn/recovery permitted.") }
    }

    private func productDecoderBegin(phase: String) async throws {
        try await productRequireNoWarnings()
        try productEvent("decoder-run-begin", fields: ["phase": phase])
        await productCancellationController?.reached("decoder")
    }
    private func productDecoderEnd(start: Double, phase: String, error: String? = nil) {
        let seconds = ProcessInfo.processInfo.systemUptime - start
        productDecoderElapsed += seconds
        try? productEvent("decoder-run-end", fields: ["phase": phase, "seconds": seconds, "error": error ?? "none"])
    }
    private func productReplayConsumed(melHash: String, hidden: [Float16]) {
        productMelHashes.append(melHash)
        productHiddenHashes.append(Self.productFloat16Hash(hidden))
        try? productEvent("owned-encoder-output-consumed")
    }

    private func productStageEncoder(_ samples: [Float], support: URL,
                                     selection: PhoWhisperStagedEncoder.Selection,
                                     gpuPreferred: Bool = false) async throws -> ProductReplayEncoder {
        guard samples.count <= 480_000, !samples.isEmpty, samples.allSatisfy(\.isFinite), productKit == nil else {
            throw ProbeError("Staged encoder requires a short finite fixture with no decoder resident")
        }
        // Cancellation belongs to the outer operation. Always await the underlying scope's return.
        let worker = Task { try await self.productOwnedEncoderScope(samples, support: support, selection: selection, gpuPreferred: gpuPreferred) }
        defer {
            // Also sample the throwing path, after the worker has unwound its local resources.
            try? productEvent("encoder-scope-returned", fields: ["runtimeRetirementVerified": false])
        }
        let replay = try await worker.value
        // All Core AI references and model-backed arrays were local to the awaited scope.
        try productEvent("encoder-function-released", fields: ["runtimeRetirementVerified": false])
        try productEvent("encoder-post-release-footprint")
        try Task.checkCancellation()
        try await productRequireNoWarnings()
        return ProductReplayEncoder(hidden: replay.hidden, melHash: replay.melHash, owner: self)
    }

    private func productOwnedEncoderScope(_ samples: [Float], support: URL,
                                         selection: PhoWhisperStagedEncoder.Selection,
                                         gpuPreferred: Bool) async throws -> PhoWhisperStagedEncoder.Encoded {
        let mel = FeatureExtractor()
        try await mel.loadModel(at: support.appending(path: "MelSpectrogram.mlmodelc"), computeUnits: .cpuAndGPU)
        defer { mel.unloadModel() }
        guard let padded = AudioProcessor.padOrTrimAudio(fromArray: samples, startAt: 0, toLength: 480_000, saveSegment: false),
              let features = try await mel.logMelSpectrogram(fromAudio: padded) as? MLMultiArray else {
            throw ProbeError("Staged frontend produced no mel")
        }
        let values = try Self.readAcceptedMel(features)
        // Start companion preparation early enough to measure actual generation overlap.
        if let start = productCompanionStart {
            productCompanionStart = nil
            await start()
        }
        try productEvent("encoder-load-begin", fields: ["gpuPreferred": gpuPreferred,
            "selection": selection.v3?.format ?? selection.legacy?.rawValue ?? "original"])
        let options: SpecializationOptions = gpuPreferred ? SpecializationOptions(preferredComputeUnitKind: .gpu) : .default
        // This explicit encoder-only gate may create the new candidate specialization.
        // It also restores the original GPU specialization after the user's app uninstall.
        // Talk and decoder/corpus runs still require the existing verified cache entry.
        let encodeOnly = ProcessInfo.processInfo.arguments.contains("--coreai-product-mode=staged-gpu-encode")
        let functionName = selection.v3?.identity.entrypoint ?? "main"
        let loaded = try await Self.loadAsset(selection.encoderURL, options: options,
            requireCached: gpuPreferred && !encodeOnly, functionName: functionName)
        let descriptor: NDArrayDescriptor
        let challengeDescriptor: NDArrayDescriptor?
        let outputName: String
        if let v3 = selection.v3 {
            try v3.identity.requireModel(loaded.model)
            guard let functionDescriptor = loaded.model.functionDescriptor(for: v3.identity.entrypoint),
                  case .ndArray(let input) = functionDescriptor.inputDescriptor(of: "input_features"),
                  case .ndArray(let challenge) = functionDescriptor.inputDescriptor(of: v3.identity.challengeInput),
                  case .ndArray(let output) = functionDescriptor.outputDescriptor(of: v3.identity.packedOutput),
                  input.scalarType == .float16, input.shape == v3.identity.inputShape,
                  challenge.scalarType == .float16, challenge.shape == v3.identity.challengeShape,
                  output.scalarType == .float16, output.shape == v3.identity.packetShape else {
                throw ProbeError("Staged v3 encoder ABI changed")
            }
            descriptor = input; challengeDescriptor = challenge; outputName = v3.identity.packedOutput
        } else {
            try Self.validate(loaded.model, role: "encoder")
            let input = try Self.inputDescriptor(loaded.model, name: "input_features")
            guard input.scalarType == .float16, input.shape == [1, 80, 3000] else { throw ProbeError("Staged encoder input contract changed") }
            descriptor = input; challengeDescriptor = nil; outputName = "encoder_hidden_states"
        }
        try productEvent("encoder-load-complete", fields: ["cacheHit": loaded.timing.cacheHit,
            "cacheLookupSeconds": loaded.timing.cacheLookupSeconds,
            "specializationSeconds": loaded.timing.specializationSeconds,
            "functionLoadSeconds": loaded.timing.functionLoadSeconds,
            "function": functionName])
        try await productRequireNoWarnings()
        var input = NDArray(descriptor: descriptor)
        try Self.fillFloat(&input, values: values)
        var challenge: [Float16]?
        var challengeArray: NDArray?
        if let v3 = selection.v3, let challengeDescriptor {
            let values = try v3.identity.challenge(seed: productTurnNumber & 31)
            var array = NDArray(descriptor: challengeDescriptor)
            try Self.fillFloat16(&array, values: values)
            challenge = values; challengeArray = array
        } else {
            challenge = nil; challengeArray = nil
        }
        try productEvent("encoder-run-begin", fields: ["challengeSeed": selection.v3 == nil ? -1 : productTurnNumber & 31])
        await productCancellationController?.reached("encoder")
        var inputs: [String: NDArray] = ["input_features": input]
        if let challengeArray, let v3 = selection.v3 { inputs[v3.identity.challengeInput] = challengeArray }
        let nativeStarted = ProcessInfo.processInfo.systemUptime
        var outputs = try await loaded.function.run(inputs: inputs)
        let nativeSeconds = ProcessInfo.processInfo.systemUptime - nativeStarted
        let validationStarted = ProcessInfo.processInfo.systemUptime
        let owned: [Float16]
        if let v3 = selection.v3 {
            guard let packet = outputs.remove(outputName)?.ndArray else { throw ProbeError("Staged v3 encoder has no packed output") }
            let packed = try W8RuntimeIdentitySpec.readFP16(packet, shape: v3.identity.packetShape)
            owned = try v3.identity.unpack(packed, challenge: challenge ?? [])
            try productEvent("encoder-response-verified", fields: ["format": v3.format,
                "challengeSeed": productTurnNumber & 31, "packetElements": packed.count,
                "nativeSeconds": nativeSeconds,
                "validationCopySeconds": ProcessInfo.processInfo.systemUptime - validationStarted])
        } else {
            guard let hidden = outputs.remove(outputName)?.ndArray else { throw ProbeError("Staged encoder has no output") }
            owned = try Self.copyEncoderOutput(hidden)
        }
        productUnderlyingInferenceReturned = true
        if ProcessInfo.processInfo.arguments.contains("--coreai-product-mode=staged-gpu-encode"), let directory = productRunDirectory {
            let suffix = String(format: "%02d", productTurnNumber)
            try owned.withUnsafeBytes { try Data($0).write(to: directory.appending(path: "encoder-\(suffix).fp16"), options: .withoutOverwriting) }
            try values.withUnsafeBytes { try Data($0).write(to: directory.appending(path: "mel-\(suffix).f32"), options: .withoutOverwriting) }
        }
        try productEvent("encoder-run-end", fields: ["hiddenElements": owned.count])
        try productEvent("encoder-function-release-begin")
        return PhoWhisperStagedEncoder.Encoded(hidden: owned, melHash: Self.productFloatHash(values))
    }

    private final class ProductCoreMLEncoder: AudioEncoding, WhisperMLModel {
        let encoder = AudioEncoder()
        weak var owner: CoreAIPhoWhisper?
        var model: MLModel? {
            get { encoder.model }
            set { encoder.model = newValue }
        }
        var embedSize: Int? { encoder.embedSize }
        init(owner: CoreAIPhoWhisper) { self.owner = owner }

        func encodeFeatures(_ features: any FeatureExtractorOutputType) async throws -> (any AudioEncoderOutputType)? {
            guard let mel = features as? MLMultiArray, let owner else {
                throw ProbeError("Expected accepted mel array and live product owner.")
            }
            let values = try CoreAIPhoWhisper.readAcceptedMel(mel)
            try await owner.productEncoderBegin(values)
            do {
                guard let hiddenArray = try await encoder.encodeFeatures(mel) else {
                    await owner.productEncoderFailure("Core ML encoder returned no output.")
                    throw ProbeError("Core ML encoder returned no output.")
                }
                let hidden = try CoreAIPhoWhisper.readDecoderEmbeddings(hiddenArray)
                await owner.productEncoderFinish(hidden)
                return hiddenArray
            } catch {
                await owner.productEncoderFailure(error.localizedDescription)
                throw error
            }
        }
    }

    private final class ProductHybridEncoder: AudioEncoding {
        nonisolated let embedSize: Int? = 1280
        weak var owner: CoreAIPhoWhisper?
        init(owner: CoreAIPhoWhisper) { self.owner = owner }

        nonisolated(nonsending) func encodeFeatures(_ features: any FeatureExtractorOutputType) async throws -> (any AudioEncoderOutputType)? {
            guard let mel = features as? MLMultiArray, let owner else {
                throw ProbeError("Expected accepted mel array and live product owner.")
            }
            let values = try CoreAIPhoWhisper.readAcceptedMel(mel)
            let hidden = try await owner.productRunHybridEncoder(values)
            return try CoreAIPhoWhisper.decoderEmbeddings(hidden)
        }
    }

    fileprivate func productGate(_ config: ProductConfig, fixturesDirectory: URL,
                                 runDirectory: URL, warningCount: @escaping @Sendable () async -> Int,
                                 companionStart: (@MainActor @Sendable () -> Void)? = nil) async throws -> ProductReport {
        productWarningCount = warningCount
        productCompanionStart = companionStart
        defer { productWarningCount = nil; productCompanionStart = nil }
        let controller = ProductCancellationController(target: config.cancelAt)
        let operation: Task<ProductReport, Never> = Task { [self] in
            await self.productExecute(config, fixturesDirectory: fixturesDirectory,
                                      runDirectory: runDirectory, controller: controller,
                                      label: "primary")
        }
        await controller.install(operation)
        var report = await operation.value
        let cancellation = await controller.snapshot()
        guard cancellation.point != nil else {
            report.terminal = true
            productWriteReport(report)
            return report
        }
        guard report.status == "cancelled" else {
            if report.status == "complete" { report.status = "cancellation-request-too-late" }
            report.cancellation = ProductCancellation(requested: true, point: cancellation.point,
                requestedUptime: cancellation.uptime, underlyingExecutionReturned: productUnderlyingInferenceReturned,
                teardownCompleted: report.stateAtEnd == ProductState.idle.rawValue,
                recoverySucceeded: false, recoveryTurnCount: 0)
            report.terminal = true
            productWriteReport(report)
            return report
        }

        let recovery = await productExecute(config.withoutCancellation(), fixturesDirectory: fixturesDirectory,
                                            runDirectory: runDirectory, controller: nil, label: "recovery")
        report.preparations.append(contentsOf: recovery.preparations)
        report.turns.append(contentsOf: recovery.turns)
        report.errors.append(contentsOf: recovery.errors)
        let recovered = recovery.status == "complete" && !recovery.turns.isEmpty &&
            recovery.turns.allSatisfy { Self.productRecoveryMatches($0) }
        report.status = recovered ? "cancelled-recovered" : "cancelled-recovery-failed"
        report.cancellation = ProductCancellation(requested: true, point: cancellation.point,
            requestedUptime: cancellation.uptime, underlyingExecutionReturned: report.cancellation?.underlyingExecutionReturned ?? false,
            teardownCompleted: recovery.stateAtEnd == ProductState.idle.rawValue,
            recoverySucceeded: recovered, recoveryTurnCount: recovery.turns.count)
        report.terminal = true
        report.stateAtEnd = recovery.stateAtEnd
        productWriteReport(report)
        return report
    }

    private func productExecute(_ config: ProductConfig, fixturesDirectory: URL,
                                runDirectory: URL, controller: ProductCancellationController?,
                                label: String) async -> ProductReport {
        await Task.yield()
        if productState != .idle { await productTeardown(next: .idle) }
        productRunDirectory = runDirectory
        productSessionID = "\(label)-\(UUID().uuidString)"
        productGeneration += 1
        productTurnNumber = 0
        productMelHashes = []; productHiddenHashes = []
        productBeforeEncoderMemory = nil; productAfterEncoderMemory = nil
        productAfterTranscriptMemory = nil; productEncoderStarted = nil
        productEncoderElapsed = 0; productDecoderElapsed = 0
        productUnderlyingInferenceReturned = false
        productV3Identity = nil
        productV3ChallengeInput = nil
        productCancellationController = controller
        let selection = config.selection
        let compressed = config.candidate
        let support = selection.supportURL
        let architecture = AIModel.deviceArchitectureName
        let gpuEncoder = config.mode == "encoder-gpu-only" || config.mode.hasPrefix("staged-gpu") || selection.v3 != nil
        let expectedEncoderHash = selection.v3?.artifactFingerprint ?? compressed?.fingerprint ?? (gpuEncoder
            ? (architecture == "h18p" ? "f783c9b539d90a589e1449e514599e240ce6036b3bab6c298858e49bba112829" : nil)
            : Self.productEncoderFingerprintByArchitecture[architecture])
        var report = ProductReport(
            date: Date(), runID: runDirectory.lastPathComponent, mode: config.mode,
            lifecycle: config.lifecycle, requestedTurns: config.turns, corpusRequested: config.corpus,
            expectedCorpusCount: 22, architecture: architecture,
            supportManifestSHA256: "unverified", encoderArtifactSHA256: nil,
            expectedEncoderArtifactSHA256: expectedEncoderHash,
            modelPrecision: selection.v3.map { "v3 packed \($0.format) encoder, FP16 activations/handoff, decoder=\($0.supportIdentity)" }
                ?? compressed.map { "\($0.rawValue) weights, FP16 activations/handoff" } ?? "FP16",
            melBoundary: "WhisperKit accepted mel tensor is read without frontend replacement; Core AI boundary is FP16 [1,80,3000]",
            tokenizer: "PhoWhisperTokenizer", decodingOptions: [
                "task": "transcribe", "detectLanguage": "true", "skipSpecialTokens": "true",
                "windowClipTime": "0", "concurrentWorkerCount": "1", "temperatureFallbackCount": "0",
                "withoutTimestamps": "true", "suppressBlank": "true", "compressionRatioThreshold": "nil",
                "logProbThreshold": "nil", "firstTokenLogProbThreshold": "nil", "noSpeechThreshold": "nil"
            ], status: "running", stateAtEnd: ProductState.idle.rawValue,
            preparations: [], turns: [], cancellation: nil, errors: [])
        do {
            let verificationStart = ProcessInfo.processInfo.systemUptime
            let manifestHash = try productVerifySupport(support, expected: selection.supportManifest)
            var encoderURL: URL?
            var encoderHash: String?
            if config.mode == "hybrid" || config.mode.hasPrefix("staged") || config.mode.hasPrefix("encoder-") {
                guard let expectedEncoderHash else {
                    throw ProbeError("No bound production encoder fingerprint for architecture \(architecture).")
                }
                let folder = gpuEncoder ? "PhoWhisperGPU" : "PhoWhisperSplit"
                let url = selection.v3?.encoderURL ?? compressed?.url ?? URL.applicationSupportDirectory.appending(path:
                    "CoreAI/\(folder)/phowhisper-cs-fp16-v1.encoder.\(architecture).aimodelc")
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw ProbeError("Missing bound Core AI encoder artifact: \(url.path)")
                }
                let hash = try Self.fingerprint(url)
                guard hash == expectedEncoderHash else {
                    throw ProbeError("Core AI encoder fingerprint is not the bound production artifact: \(hash)")
                }
                encoderURL = url; encoderHash = hash
            }
            report = ProductReport(date: report.date, runID: report.runID, mode: report.mode,
                lifecycle: report.lifecycle, requestedTurns: report.requestedTurns,
                corpusRequested: report.corpusRequested, expectedCorpusCount: report.expectedCorpusCount,
                architecture: report.architecture, supportManifestSHA256: manifestHash,
                encoderArtifactSHA256: encoderHash, expectedEncoderArtifactSHA256: expectedEncoderHash,
                modelPrecision: report.modelPrecision, melBoundary: report.melBoundary,
                tokenizer: report.tokenizer, decodingOptions: report.decodingOptions,
                status: report.status, stateAtEnd: report.stateAtEnd, preparations: report.preparations,
                turns: report.turns, cancellation: report.cancellation, errors: report.errors)
            let assetVerificationSeconds = ProcessInfo.processInfo.systemUptime - verificationStart
            let suppression = try productSuppressionTokens(support)
            if config.mode.hasSuffix("-only") {
                try await productLoadOnly(config, support: support, encoderURL: encoderURL,
                                          suppression: suppression)
                report.status = "complete"
                report.stateAtEnd = productState.rawValue
                return report
            }
            let jobs = try productJobs(config, directory: fixturesDirectory)
            guard !jobs.isEmpty else { throw ProbeError("No product-gate fixtures.") }
            try? productEvent("asset-verification-complete", fields: [
                "seconds": assetVerificationSeconds, "supportManifestSHA256": manifestHash,
                "encoderArtifactSHA256": encoderHash ?? "not-applicable", "mode": config.mode])
            for (index, file) in jobs.enumerated() {
                productTurnNumber = index + 1
                if index > 0 { try? productEvent("recreate-begin", fields: ["turn": index + 1]) }
                try await productRequireNoWarnings()
                let samples = try await Task.detached {
                    try AudioProcessor.loadAudioAsFloatArray(fromPath: file.path)
                }.value
                let stagedASRStarted = ProcessInfo.processInfo.systemUptime
                let replay: ProductReplayEncoder?
                if config.mode.hasPrefix("staged") {
                    guard try Self.fingerprint(file) == Self.productFrozenAudioSHA256[file.lastPathComponent] else {
                        throw ProbeError("Staged qualification requires the frozen fixture and encoder.")
                    }
                    replay = try await productStageEncoder(samples, support: support, selection: selection, gpuPreferred: gpuEncoder)
                } else { replay = nil }
                if config.mode == "staged-gpu-encode" {
                    try productEvent("encoder-only-complete", fields: ["candidate": selection.v3?.format ?? compressed?.rawValue ?? "original", "decoderLoaded": false])
                    continue
                }
                let preparation = try await productPrepare(config, support: support,
                    encoderURL: encoderURL, replay: replay, suppression: suppression,
                    assetVerificationSeconds: index == 0 ? assetVerificationSeconds : 0,
                    controller: controller, index: index + 1)
                report.preparations.append(preparation)
                try? productEvent("recreate-end", fields: ["turn": index + 1,
                    "readySeconds": preparation.readySeconds])
                productWriteReport(report)
                try await productRequireNoWarnings()
                let audioHash = try Self.fingerprint(file)
                let turn = try await productTranscribe(samples, file: file,
                    audioSHA256: audioHash, controller: controller)
                report.turns.append(turn)
                if config.mode == "staged-gpu" {
                    try productEvent("staged-asr-full-complete", fields: [
                        "file": file.lastPathComponent,
                        "seconds": ProcessInfo.processInfo.systemUptime - stagedASRStarted,
                        "scope": "after-audio-read-through-encoder-prepare-decoder-not-UI-send"])
                }
                let requireRecovery: Bool
                if try DecoderTrialPolicy.combined(ProcessInfo.processInfo.arguments) {
                    requireRecovery = !config.corpus // Joint native 001 gate; corpus differences remain reviewable.
                } else {
                    requireRecovery = selection.v3?.format != "pal6" && selection.supportIdentity != "phowhisper-cs-pal6-g16-v1"
                }
                if compressed == nil, requireRecovery, config.mode.hasPrefix("staged"), file.lastPathComponent == "001.wav", !Self.productRecoveryMatches(turn) {
                    throw ProbeError("Staged fixture-001 parity failed.")
                }
                productWriteReport(report)
                try await productRequireNoWarnings()
                if index + 1 < jobs.count { await productTeardown(next: .readyForRecreate) }
            }
            await productTeardown(next: .idle)
            try await productRequireNoWarnings()
            report.status = "complete"
        } catch {
            let cancellation = await controller?.snapshot()
            let point = cancellation?.point
            report.errors.append(error.localizedDescription)
            report.status = error is CancellationError && point != nil ? "cancelled" : "failed"
            if let point {
                report.cancellation = ProductCancellation(requested: true, point: point,
                    requestedUptime: cancellation?.uptime,
                    underlyingExecutionReturned: productUnderlyingInferenceReturned,
                    teardownCompleted: false, recoverySucceeded: false, recoveryTurnCount: 0)
            }
            await productTeardown(next: .idle)
            if var value = report.cancellation { value.teardownCompleted = productState == .idle; report.cancellation = value }
        }
        report.stateAtEnd = productState.rawValue
        productCancellationController = nil
        productWriteReport(report)
        return report
    }

    private static func productRecoveryMatches(_ turn: ProductTurn) -> Bool {
        turn.error == nil && turn.file == "001.wav" &&
        turn.audioSHA256 == productFrozenAudioSHA256["001.wav"] &&
        turn.rawTranscript == "Yesterday I went to the supermarket." &&
        turn.normalizedTranscript == "yesterday i went to the supermarket" &&
        turn.detectedLanguages == ["vi"] &&
        turn.generatedTokens == [[50258,50278,50359,50363,56,4690,286,1437,220,1353,220,3322,25180,13,50257]]
    }

    private func productLoadOnly(_ config: ProductConfig, support: URL, encoderURL: URL?,
                                 suppression: [Int]) async throws {
        try productEvent("loading-only-begin", fields: ["mode": config.mode, "inferencePermitted": false])
        try await productLoadComponent(config, support: support, encoderURL: encoderURL, suppression: suppression)
        try productEvent("component-loaded", fields: ["mode": config.mode])
        await productTeardown(next: .idle)
        // Observation only: no sleep is used to grant permission to load another model.
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            try productEvent("post-release-observation", fields: [
                "elapsedSeconds": ProcessInfo.processInfo.systemUptime - start,
                "runtimeRetirementVerified": false])
        }
        try productEvent("loading-only-end", fields: ["mode": config.mode])
    }

    private func productLoadComponent(_ config: ProductConfig, support: URL, encoderURL: URL?,
                                      suppression: [Int]) async throws {
        if config.mode.hasPrefix("encoder-") {
            guard let encoderURL else { throw ProbeError("Missing verified encoder") }
            productState = .preparing
            if config.mode == "encoder-rebuild-only" {
                // Explicit one-off repair mode, never an automatic retry on load failure.
                try productEvent("approved-encoder-cache-delete-begin")
                try AIModelCache.default.deleteEntry(for: encoderURL, options: .default)
                try productEvent("approved-encoder-cache-delete-end")
            }
            let options: SpecializationOptions = config.mode == "encoder-gpu-only"
                ? SpecializationOptions(preferredComputeUnitKind: .gpu) : .default
            let functionName = config.selection.v3?.identity.entrypoint ?? "main"
            try productEvent("encoder-load-options", fields: ["gpuPreferred": config.mode == "encoder-gpu-only",
                "function": functionName])
            let loaded = try await Self.loadAsset(encoderURL, options: options,
                requireCached: config.mode == "encoder-only", functionName: functionName)
            if let v3 = config.selection.v3 {
                try v3.identity.requireModel(loaded.model)
                guard let descriptor = loaded.model.functionDescriptor(for: v3.identity.entrypoint),
                      case .ndArray(let input) = descriptor.inputDescriptor(of: "input_features"),
                      case .ndArray(let challenge) = descriptor.inputDescriptor(of: v3.identity.challengeInput),
                      case .ndArray(let output) = descriptor.outputDescriptor(of: v3.identity.packedOutput),
                      input.shape == v3.identity.inputShape, challenge.shape == v3.identity.challengeShape,
                      output.shape == v3.identity.packetShape else {
                    throw ProbeError("v3 encoder-only ABI changed")
                }
                productV3Identity = v3.identity; productV3ChallengeInput = challenge
            } else {
                try Self.validate(loaded.model, role: "encoder")
            }
            productModel = loaded.model
            productFunction = loaded.function
            try productEvent("encoder-load-complete", fields: ["cacheHit": loaded.timing.cacheHit,
                "functionLoadSeconds": loaded.timing.functionLoadSeconds, "function": functionName])
        } else {
            _ = try await productPrepare(config, support: support, encoderURL: nil,
                suppression: suppression, assetVerificationSeconds: 0, controller: nil, index: 1)
        }
    }

    private func productPrepare(_ config: ProductConfig, support: URL, encoderURL: URL?,
                                replay: ProductReplayEncoder? = nil, suppression: [Int], assetVerificationSeconds: Double,
                                controller: ProductCancellationController?, index: Int) async throws -> ProductPreparation {
        guard productState == .idle || productState == .readyForRecreate,
              productKit == nil, productFunction == nil else {
            throw ProbeError("Product owner is not idle before prepare: \(productState.rawValue)")
        }
        productState = .preparing
        productGeneration += 1
        productSuppressionTokens = suppression
        let start = ProcessInfo.processInfo.systemUptime
        let before = productMemorySnapshot(stage: "before-prepare")
        let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
        try? productEvent("prepare-begin", fields: ["mode": config.mode, "turn": index,
            "lifecycle": config.lifecycle])
        var assetTiming: AssetTiming?
        if config.mode == "hybrid" || config.mode.hasPrefix("encoder-") {
            guard let encoderURL else { throw ProbeError("Missing product encoder URL.") }
            try? productEvent("encoder-load-begin", fields: ["path": encoderURL.path,
                "selection": config.selection.v3?.format ?? config.selection.legacy?.rawValue ?? "original"])
            let functionName = config.selection.v3?.identity.entrypoint ?? "main"
            let loaded = try await Self.loadAsset(encoderURL, functionName: functionName)
            let input: NDArrayDescriptor
            if let v3 = config.selection.v3 {
                try v3.identity.requireModel(loaded.model)
                guard let descriptor = loaded.model.functionDescriptor(for: v3.identity.entrypoint),
                      case .ndArray(let inputDescriptor) = descriptor.inputDescriptor(of: "input_features"),
                      case .ndArray(let challenge) = descriptor.inputDescriptor(of: v3.identity.challengeInput),
                      case .ndArray(let output) = descriptor.outputDescriptor(of: v3.identity.packedOutput),
                      inputDescriptor.scalarType == .float16, inputDescriptor.shape == v3.identity.inputShape,
                      challenge.scalarType == .float16, challenge.shape == v3.identity.challengeShape,
                      output.scalarType == .float16, output.shape == v3.identity.packetShape else {
                    throw ProbeError("Product v3 encoder ABI changed; no packed output was accepted.")
                }
                input = inputDescriptor
                productV3Identity = v3.identity
                productV3ChallengeInput = challenge
            } else {
                try Self.validate(loaded.model, role: "encoder")
                let legacyInput = try Self.inputDescriptor(loaded.model, name: "input_features")
                guard legacyInput.scalarType == .float16, legacyInput.shape == [1, 80, 3000] else {
                    throw ProbeError("Product encoder input must remain FP16 [1,80,3000].")
                }
                guard let descriptor = loaded.model.functionDescriptor(for: "main"),
                      case .ndArray(let output) = descriptor.outputDescriptor(of: "encoder_hidden_states"),
                      output.scalarType == .float16, output.shape == [1, 1500, 1280] else {
                    throw ProbeError("Product encoder output must remain FP16 [1,1500,1280].")
                }
                input = legacyInput
                productV3Identity = nil
                productV3ChallengeInput = nil
            }
            productModel = loaded.model; productFunction = loaded.function; productInput = input
            assetTiming = loaded.timing
            try? productEvent("encoder-load-complete", fields: [
                "cacheHit": loaded.timing.cacheHit, "cacheLookupSeconds": loaded.timing.cacheLookupSeconds,
                "specializationSeconds": loaded.timing.specializationSeconds,
                "functionLoadSeconds": loaded.timing.functionLoadSeconds, "function": functionName])
        }
        let activeEncoder: any AudioEncoding
        if let replay { activeEncoder = replay }
        else if config.mode != "baseline" { activeEncoder = ProductHybridEncoder(owner: self) }
        else { activeEncoder = ProductCoreMLEncoder(owner: self) }
        productEncoder = activeEncoder
        let kit = try await WhisperKit(WhisperKitConfig(modelFolder: support.path,
            tokenizerFolder: support,
            computeOptions: ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine,
                                                textDecoderCompute: .cpuAndNeuralEngine),
            audioEncoder: activeEncoder, textDecoder: ProductDecoder(owner: self), verbose: false, prewarm: false, load: false, download: false))
        productKit = kit
        let tokenizerStart = ProcessInfo.processInfo.systemUptime
        kit.tokenizer = try await PhoWhisperTokenizer.load(from: support)
        kit.textDecoder.isModelMultilingual = true
        let tokenizerSeconds = ProcessInfo.processInfo.systemUptime - tokenizerStart
        try? productEvent("whisperkit-load-complete", fields: ["phase": "configuration-and-tokenizer",
            "tokenizerSeconds": tokenizerSeconds])
        await controller?.reached("prepare")
        try Task.checkCancellation()
        try? productEvent("decoder-load/prewarm-begin")
        let prewarmStart = ProcessInfo.processInfo.systemUptime
        let reusePrewarm = try DecoderTrialPolicy.once(ProcessInfo.processInfo.arguments) && index > 1
        if !reusePrewarm {
            let prewarmTask = Task { try await kit.prewarmModels() }
            try await prewarmTask.value
        }
        try productEvent("decoder-prewarm-policy", fields: ["reused": reusePrewarm,
            "scope": "same-support-prior-successful-turn-real-load-still-required"])
        let prewarmSeconds = ProcessInfo.processInfo.systemUptime - prewarmStart
        try? productEvent("whisperkit-prewarm-complete", fields: ["seconds": prewarmSeconds,
            "decoderSpecializationSeconds": kit.currentTimings.decoderSpecializationTime,
            "encoderSpecializationSeconds": kit.currentTimings.encoderSpecializationTime])
        try Task.checkCancellation()
        let loadStart = ProcessInfo.processInfo.systemUptime
        let loadTask = Task { try await kit.loadModels() }
        try await loadTask.value
        let loadSeconds = ProcessInfo.processInfo.systemUptime - loadStart
        guard kit.featureExtractor.melCount == 80, kit.featureExtractor.windowSamples == 480_000,
              kit.audioEncoder.embedSize == 1280, kit.textDecoder.logitsSize == 51865 else {
            throw ProbeError("WhisperKit PhoWhisper mel/decoder contract changed.")
        }
        let after = productMemorySnapshot(stage: "after-prepare")
        let thermalAfter = ProcessInfo.processInfo.thermalState.rawValue
        productState = .ready
        let preparation = ProductPreparation(index: index, state: productState.rawValue,
            totalSeconds: ProcessInfo.processInfo.systemUptime - start,
            assetVerificationSeconds: assetVerificationSeconds,
            coreAICacheHit: assetTiming?.cacheHit,
            coreAICacheLookupSeconds: assetTiming?.cacheLookupSeconds,
            coreAISpecializationSeconds: assetTiming?.specializationSeconds,
            coreAIFunctionLoadSeconds: assetTiming?.functionLoadSeconds,
            tokenizerSeconds: tokenizerSeconds, whisperKitPrewarmSeconds: prewarmSeconds,
            whisperKitLoadSeconds: loadSeconds,
            readySeconds: ProcessInfo.processInfo.systemUptime - start,
            memoryBefore: before, memoryAfter: after,
            thermalBefore: thermalBefore, thermalAfter: thermalAfter)
        try? productEvent("whisperkit-load-complete", fields: ["phase": "models", "loadSeconds": loadSeconds,
            "readySeconds": preparation.readySeconds])
        return preparation
    }

    private func productTranscribe(_ samples: [Float], file: URL, audioSHA256: String,
                                   controller: ProductCancellationController?) async throws -> ProductTurn {
        guard productState == .ready, let kit = productKit else {
            throw ProbeError("Product owner is not ready to transcribe.")
        }
        guard samples.count <= 480_000, samples.allSatisfy(\.isFinite), !samples.isEmpty else {
            throw ProbeError("Product audio must be finite 16 kHz mono and at most 30 seconds.")
        }
        productState = .transcribing
        productMelHashes = []; productHiddenHashes = []
        productBeforeEncoderMemory = nil; productAfterEncoderMemory = nil
        productAfterTranscriptMemory = nil; productEncoderStarted = nil
        productEncoderElapsed = 0; productDecoderElapsed = 0
        productUnderlyingInferenceReturned = false
        let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
        let started = ProcessInfo.processInfo.systemUptime
        try? productEvent("transcribe-begin", fields: ["file": file.lastPathComponent,
            "sampleCount": samples.count])
        let options = productDecodingOptions()
        productActiveInferenceCount += 1
        defer { productFinishInference() }
        let transcriptionTask = Task {
            try await kit.transcribe(audioArray: samples, decodeOptions: options)
        }
        do {
            try? productEvent("transcription-await-begin")
            let results = try await transcriptionTask.value
            productUnderlyingInferenceReturned = true
            try Task.checkCancellation()
            let decoderSeconds = productDecoderElapsed
            let raw = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let languages = results.map(\.language)
            let tokens = results.flatMap { $0.segments.map(\.tokens) }
            let timing = ProductTurnTiming(totalSeconds: ProcessInfo.processInfo.systemUptime - started,
                melSeconds: results.reduce(0) { $0 + $1.timings.logmels },
                encoderSeconds: productEncoderElapsed, decoderSeconds: decoderSeconds,
                decodingInitSeconds: results.reduce(0) { $0 + $1.timings.decodingInit },
                decodingLoopSeconds: results.reduce(0) { $0 + $1.timings.decodingLoop },
                decodingPredictionsSeconds: results.reduce(0) { $0 + $1.timings.decodingPredictions },
                decodingNonPredictionSeconds: results.reduce(0) { $0 + $1.timings.decodingNonPrediction },
                pipelineSeconds: results.reduce(0) { $0 + $1.timings.fullPipeline })
            productAfterTranscriptMemory = productMemorySnapshot(stage: "after-transcript")
            try? productEvent("transcription-await-end", fields: ["seconds": decoderSeconds,
                "windows": results.count, "underlyingExecutionReturned": true])
            productState = .ready
            let termination = tokens.last?.last == 50257 ? "endToken" : "returned"
            let turn = ProductTurn(turn: productTurnNumber, file: file.lastPathComponent,
                sampleCount: samples.count, audioSHA256: audioSHA256, rawTranscript: raw,
                normalizedTranscript: Self.productNormalize(raw), detectedLanguages: languages,
                generatedTokens: tokens, segmentTokens: tokens, melSHA256: productMelHashes,
                encoderHiddenSHA256: productHiddenHashes, timings: timing,
                memoryBeforeEncoder: productBeforeEncoderMemory, memoryAfterEncoder: productAfterEncoderMemory,
                memoryAfterTranscript: productAfterTranscriptMemory, thermalBefore: thermalBefore,
                thermalAfter: ProcessInfo.processInfo.thermalState.rawValue, termination: termination, error: nil)
            try? productEvent("transcribe-end", fields: ["seconds": timing.totalSeconds,
                "underlyingExecutionReturned": true])
            return turn
        } catch {
            productUnderlyingInferenceReturned = true
            try? productEvent("transcription-await-end", fields: ["error": error.localizedDescription,
                "underlyingExecutionReturned": true])
            productState = .ready
            throw error
        }
    }

    private func productRunHybridEncoder(_ values: [Float]) async throws -> [Float16] {
        try await productEncoderBegin(values)
        do {
            guard let function = productFunction, let input = productInput else {
                await productEncoderFailure("Core AI encoder was released before run.")
                throw ProbeError("Core AI encoder is unavailable.")
            }
            var array = NDArray(descriptor: input)
            try Self.fillFloat(&array, values: values)
            let hidden: [Float16]
            if let identity = productV3Identity, let challengeDescriptor = productV3ChallengeInput {
                let challenge = try identity.challenge(seed: productTurnNumber & 31)
                var challengeArray = NDArray(descriptor: challengeDescriptor)
                try Self.fillFloat16(&challengeArray, values: challenge)
                var outputs = try await function.run(inputs: ["input_features": array,
                                                                identity.challengeInput: challengeArray])
                guard let packet = outputs.remove(identity.packedOutput)?.ndArray else {
                    throw ProbeError("Missing packed v3 encoder output.")
                }
                let packed = try W8RuntimeIdentitySpec.readFP16(packet, shape: identity.packetShape)
                hidden = try identity.unpack(packed, challenge: challenge)
                try productEvent("encoder-response-verified", fields: ["format": identity.format,
                    "challengeSeed": productTurnNumber & 31, "packetElements": packed.count])
            } else {
                var outputs = try await function.run(inputs: ["input_features": array])
                guard let output = outputs.remove("encoder_hidden_states")?.ndArray else {
                    throw ProbeError("Missing Core AI encoder output.")
                }
                hidden = try Self.copyEncoderOutput(output)
            }
            productUnderlyingInferenceReturned = true
            await productEncoderFinish(hidden)
            return hidden
        } catch {
            productUnderlyingInferenceReturned = true
            await productEncoderFailure(error.localizedDescription)
            throw error
        }
    }

    private func productEncoderBegin(_ values: [Float]) async throws {
        guard productState == .transcribing, !productEncoderBusy else {
            throw ProbeError("Overlapping product encoder execution.")
        }
        productEncoderBusy = true
        productActiveInferenceCount += 1
        if productMelHashes.isEmpty { productBeforeEncoderMemory = productMemorySnapshot(stage: "before-encoder") }
        productMelHashes.append(Self.productFloatHash(values))
        productEncoderStarted = ProcessInfo.processInfo.systemUptime
        try? productEvent("encoder-run-begin", fields: ["underlyingExecutionReturned": false])
        await productCancellationController?.reached("encoder")
    }

    private func productEncoderFinish(_ hidden: [Float16]) async {
        guard productEncoderBusy else { return }
        productHiddenHashes.append(Self.productFloat16Hash(hidden))
        productAfterEncoderMemory = productMemorySnapshot(stage: "after-encoder")
        if let started = productEncoderStarted { productEncoderElapsed += ProcessInfo.processInfo.systemUptime - started }
        productUnderlyingInferenceReturned = true
        try? productEvent("encoder-run-end", fields: ["underlyingExecutionReturned": true])
        productEncoderBusy = false
        productFinishInference()
    }

    private func productEncoderFailure(_ message: String) async {
        guard productEncoderBusy else { return }
        productUnderlyingInferenceReturned = true
        try? productEvent("encoder-run-end", fields: ["error": message,
            "underlyingExecutionReturned": true])
        productEncoderBusy = false
        productFinishInference()
    }

    private func productFinishInference() {
        precondition(productActiveInferenceCount > 0, "Unbalanced product inference completion")
        productActiveInferenceCount -= 1
        guard productActiveInferenceCount == 0, !productEncoderBusy else { return }
        let waiters = productQuiescenceWaiters
        productQuiescenceWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func productWaitForQuiescence() async {
        guard productActiveInferenceCount > 0 || productEncoderBusy else { return }
        await withCheckedContinuation { continuation in
            productQuiescenceWaiters.append(continuation)
        }
    }

    private func productTeardown(next: ProductState) async {
        guard productKit != nil || productFunction != nil || productEncoder != nil || productState != .idle else {
            productState = next
            return
        }
        productState = .tearingDown
        try? productEvent("teardown-begin", fields: ["activeInferenceCount": productActiveInferenceCount])
        await productWaitForQuiescence()
        if let kit = productKit {
            await kit.unloadModels()
            kit.tokenizer = nil
        }
        try? productEvent("whisperkit-unloaded")
        productKit = nil
        productEncoder = nil
        productFunction = nil
        productModel = nil
        productInput = nil
        productV3Identity = nil
        productV3ChallengeInput = nil
        productEncoderBusy = false
        try? productEvent("references-released", fields: ["runtimeRetirementVerified": false])
        productState = next
        try? productEvent("teardown-end", fields: ["state": next.rawValue,
            "activeInferenceCount": productActiveInferenceCount])
    }

    private func productMemorySnapshot(stage: String) -> ProductMemory {
        let memory = VietnameseEnglishRecognizer.logMemory(stage: stage, model: "coreai-product-gate")
        return ProductMemory(footprintBytes: memory["footprintBytes"] ?? 0,
            processRSSPeakBytes: memory["processRSSPeakBytes"] ?? 0)
    }

    private func productEvent(_ stage: String, fields: [String: Any] = [:]) throws {
        guard let directory = productRunDirectory else { throw ProbeError("Missing product run directory.") }
        var entry = fields
        entry["stage"] = stage; entry["runID"] = directory.lastPathComponent
        entry["sessionID"] = productSessionID; entry["generation"] = productGeneration
        entry["turn"] = productTurnNumber; entry["state"] = productState.rawValue
        entry["uptime"] = ProcessInfo.processInfo.systemUptime
        entry["memory"] = VietnameseEnglishRecognizer.logMemory(stage: stage, model: "coreai-product-gate")
        entry["thermalState"] = ProcessInfo.processInfo.thermalState.rawValue
        let data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) + Data([10])
        let url = directory.appending(path: "events.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.synchronize()
    }

    private func productVerifySupport(_ support: URL, expected: String = CoreAIPhoWhisper.productSupportManifestSHA256) throws -> String {
        let manifestURL = support.appending(path: "manifest.json")
        let manifest = try Data(contentsOf: manifestURL)
        let hash = Self.sha256(manifest)
        guard hash == expected else { throw ProbeError("Accepted support manifest changed.") }
        struct Manifest: Decodable {
            struct File: Decodable { let bytes: Int; let sha256: String }
            let files: [String: File]
        }
        for (path, expected) in try JSONDecoder().decode(Manifest.self, from: manifest).files {
            let url = support.appending(path: path)
            guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == expected.bytes,
                  try Self.fingerprint(url) == expected.sha256 else {
                throw ProbeError("Support mismatch: \(path)")
            }
        }
        return hash
    }

    private func productSuppressionTokens(_ support: URL) throws -> [Int] {
        struct Generation: Decodable { let suppress_tokens: [Int] }
        return try JSONDecoder().decode(Generation.self,
            from: Data(contentsOf: support.appending(path: "generation_config.json"))).suppress_tokens
    }

    private func productJobs(_ config: ProductConfig, directory: URL) throws -> [URL] {
        let extensions = Set(["wav", "m4a", "caf", "mp3"])
        if config.corpus {
            let expectedNames = (1...22).map { String(format: "%03d.wav", $0) }
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                .filter { extensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            guard files.map(\.lastPathComponent) == expectedNames else {
                throw ProbeError("Frozen product corpus must contain exactly 001.wav through 022.wav.")
            }
            for file in files {
                guard let expected = Self.productFrozenAudioSHA256[file.lastPathComponent],
                      try Self.fingerprint(file) == expected else {
                    throw ProbeError("Frozen corpus audio changed: \(file.lastPathComponent)")
                }
            }
            return files
        }
        let names = config.sequence.isEmpty ? ["001.wav"] : config.sequence
        let files = try names.map { name -> URL in
            let file = directory.appending(path: name)
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw ProbeError("Missing product fixture: \(file.path)")
            }
            return file
        }
        return (0..<config.turns).map { files[$0 % files.count] }
    }

    private func productDecodingOptions() -> DecodingOptions {
        var options = DecodingOptions(task: .transcribe, detectLanguage: true,
            skipSpecialTokens: true, windowClipTime: 0, concurrentWorkerCount: 1)
        options.temperatureFallbackCount = 0; options.withoutTimestamps = true
        options.suppressBlank = true; options.suppressTokens = productSuppressionTokens
        options.compressionRatioThreshold = nil; options.logProbThreshold = nil
        options.firstTokenLogProbThreshold = nil; options.noSpeechThreshold = nil
        return options
    }

    private func productWriteReport(_ report: ProductReport) {
        guard let directory = productRunDirectory else { return }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(report).write(to: directory.appending(path: "product-report.json"), options: .atomic)
        let transcripts = report.turns.map { $0 }
        try? encoder.encode(transcripts).write(to: directory.appending(path: "transcripts.json"), options: .atomic)
    }

    private static func productFloatHash(_ values: [Float]) -> String {
        values.withUnsafeBufferPointer { sha256(Data(buffer: $0)) }
    }
    private static func productFloat16Hash(_ values: [Float16]) -> String {
        values.withUnsafeBufferPointer { sha256(Data(buffer: $0)) }
    }
    private static func productNormalize(_ text: String) -> String {
        // Match the frozen corpus benchmark: NFC, lowercase, punctuation and whitespace only.
        let value = text.precomposedStringWithCanonicalMapping.lowercased()
        let output = value.unicodeScalars.map {
            CharacterSet.punctuationCharacters.contains($0) ? " " : String($0)
        }.joined()
        return output.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

#endif
