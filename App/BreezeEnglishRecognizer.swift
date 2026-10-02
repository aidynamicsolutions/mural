import CoreML
import CryptoKit
import Foundation
import FluidAudio
import MuralCore
import OSLog
import WhisperKit

/// Explicit Taiwan Mandarin–English Talk/test recognizer, never an automatic fallback.
/// The existing audio owner serializes calls and retains this actor through cancellation.
actor BreezeEnglishRecognizer {
    static var identity: String {
        BreezeTrialSelection.requestsPAL4 ? BreezePAL4TrialPin.identity : "breeze-asr25-pal8-v1"
    }
    static var displayName: String {
        BreezeTrialSelection.requestsPAL4 ? "Breeze PAL4 (trial)" : "Breeze PAL8"
    }

    /// Shared existence-preflight / verified-loader resolver; PAL4 never reads an active pointer.
    static func assetDirectory() throws -> URL {
        let selected = try BreezeTrialSelection.parse(ProcessInfo.processInfo.arguments,
                                                      enabled: BreezeTrialSelection.enabled)
        if selected == .pal4 {
            guard BreezePAL4TrialPin.manifestSHA256.count == 64,
                  BreezePAL4TrialPin.revision.count == 40, BreezePAL4TrialPin.fileCount >= 17,
                  BreezePAL4TrialPin.identity.range(of: "^breeze-asr25-weiren-pal4-[0-9a-f]{12}-[0-9a-f]{12}$",
                                                  options: .regularExpression) != nil else {
                throw Failure("PAL4 trial has no reviewed compiled-in pin. No model loaded.")
            }
            return URL.applicationSupportDirectory.appending(path: "BreezeASR25/\(identity)", directoryHint: .isDirectory)
        }
        return try LocalSpeechProvisioning.installedDirectory(for: .taiwanMandarinEnglish, component: "support") ??
            URL.applicationSupportDirectory.appending(path: "BreezeASR25/\(identity)", directoryHint: .isDirectory)
    }
    private var kit: WhisperKit?
    private var vad: VadManager?
    private var vadMode: SpeechPresencePolicy.Mode = .off
    private var busy = false
    private var inferenceCount = 0
    private var suppressTokens: [Int] = []
    private let logger = Logger(subsystem: "no.william.mural", category: "LocalAudio")

    private struct Manifest: Decodable {
        struct File: Decodable { let bytes: Int; let sha256: String }
        let schema: String
        let model: String
        let revision: String
        let precision: String
        let files: [String: File]
    }

    /// Fixed reviewed artifact pin. Neither launch arguments nor remote metadata can override it.
    /// Managed downloads and retained development assets pass the same full verification.
    @concurrent static func localDirectory() async throws -> URL {
        let started = ProcessInfo.processInfo.systemUptime
        let logger = Logger(subsystem: "no.william.mural", category: "LocalAudio")
        var verified = false
        logger.notice("breeze_asset_verification_begin")
        defer {
            logger.notice("breeze_asset_verification_end success=\(verified, privacy: .public) seconds=\(ProcessInfo.processInfo.systemUptime - started, privacy: .public)")
        }
        let folder = try assetDirectory()
        let trial = BreezeTrialSelection.requestsPAL4
        let expected = trial ? BreezePAL4TrialPin.manifestSHA256 : SpeechPackagePins.breezeManifest
        let revision = trial ? BreezePAL4TrialPin.revision : SpeechPackagePins.breezeRevision
        let precision = trial ? "pal4" : "pal8"
        let schema = trial ? "mural.breeze-coreml.trial.v1" : "mural.breeze-coreml.v1"
        let fileCount = trial ? BreezePAL4TrialPin.fileCount : 27
        #if MURAL_BREEZE_PAL4_TRIAL
        logger.notice("breeze_trial_identity model=\(identity, privacy: .public) manifest=\(expected, privacy: .public) revision=\(revision, privacy: .public)")
        #endif
        if trial {
            var ancestor = folder
            while ancestor.path != URL.applicationSupportDirectory.path {
                guard try ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                    throw Failure("PAL4 trial root must not contain symbolic links.")
                }
                ancestor.deleteLastPathComponent()
            }
            guard try folder.appending(path: "manifest.json").resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw Failure("PAL4 trial manifest must not be a symbolic link.")
            }
        }
        let data = try Data(contentsOf: folder.appending(path: "manifest.json"))
        guard digest(data) == expected else { throw Failure("Breeze manifest pin mismatch. No model loaded.") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.schema == schema, manifest.model == "MediaTek-Research/Breeze-ASR-25",
              manifest.precision == precision, manifest.revision == revision,
              manifest.files.count == fileCount else {
            throw Failure("Wrong Breeze artifact contract.")
        }
        let required = ["config.json", "generation_config.json", "preprocessor_config.json", "tokenizer.json", "tokenizer_config.json"]
            + ["MelSpectrogram", "AudioEncoder", "TextDecoder"].flatMap { name in
                ["coremldata.bin", "metadata.json", "model.mil", "weights/weight.bin"].map { "\(name).mlmodelc/\($0)" }
            }
        guard required.allSatisfy({ manifest.files[$0] != nil }) else { throw Failure("Breeze support inventory is incomplete.") }
        if trial {
            try BreezeTrialSelection.verifyInventory(at: folder,
                allowed: Set(manifest.files.keys).union(["manifest.json", "audit.json"]))
        }
        for (path, entry) in manifest.files {
            try Task.checkCancellation()
            let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !pieces.isEmpty, !path.contains("\\"), pieces.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw Failure("Invalid Breeze inventory path.")
            }
            var url = folder
            for piece in pieces {
                url.appendPathComponent(String(piece))
                guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                    throw Failure("Breeze artifacts must not contain symbolic links.")
                }
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256(), size = 0
            while try autoreleasepool(invoking: { () throws -> Bool in
                try Task.checkCancellation()
                guard let block = try handle.read(upToCount: 1_048_576), !block.isEmpty else { return false }
                size += block.count; hash.update(data: block)
                return true
            }) {}
            guard size == entry.bytes, hash.finalize().map({ String(format: "%02x", $0) }).joined() == entry.sha256 else {
                throw Failure("Breeze artifact hash mismatch. No fallback or repair download is allowed.")
            }
        }
        var excluded = folder
        var resources = URLResourceValues(); resources.isExcludedFromBackup = true
        try excluded.setResourceValues(resources)
        try Task.checkCancellation()
        verified = true
        return folder
    }

    func prepare(directory: URL) async throws {
        guard !busy, kit == nil else { throw Failure("Breeze is busy or already prepared.") }
        busy = true; defer { busy = false }
        #if MURAL_BREEZE_PAL4_TRIAL
        let trialStarted = ProcessInfo.processInfo.systemUptime
        var trialPrepared = false
        defer {
            logger.notice("breeze_trial_prepare model=\(Self.identity, privacy: .public) success=\(trialPrepared, privacy: .public) seconds=\(ProcessInfo.processInfo.systemUptime - trialStarted, privacy: .public)")
        }
        #endif
        struct Model: Decodable {
            let model_type: String; let num_mel_bins: Int; let d_model: Int
            let encoder_layers: Int; let decoder_layers: Int; let vocab_size: Int
        }
        struct Generation: Decodable { let suppress_tokens: [Int] }
        let model = try JSONDecoder().decode(Model.self, from: Data(contentsOf: directory.appending(path: "config.json")))
        guard model.model_type == "whisper", model.num_mel_bins == 80, model.d_model == 1280,
              model.encoder_layers == 32, model.decoder_layers == 32, model.vocab_size == 51865 else {
            throw Failure("Breeze requires its own Whisper-large-v2 conversion, not v3 or PhoWhisper assets.")
        }
        suppressTokens = try JSONDecoder().decode(Generation.self,
            from: Data(contentsOf: directory.appending(path: "generation_config.json"))).suppress_tokens
        guard !suppressTokens.isEmpty, suppressTokens.allSatisfy({ (0..<51865).contains($0) }) else { throw Failure("Invalid Breeze suppression tokens.") }
        // Reuse the large-v2 control-token wrapper, but load Breeze's OWN lexical BPE.
        // No word timestamps are requested; no Vietnamese vocabulary is reused.
        let lexical = try await AutoTokenizerWrapper.from(modelFolder: directory)
        guard lexical.convertTokenToId("<|zh|>") == 50260,
              lexical.convertTokenToId("<|en|>") == 50259,
              lexical.convertTokenToId("<|transcribe|>") == 50359,
              lexical.convertTokenToId("<|notimestamps|>") == 50363,
              ["<|nospeech|>", "<|nocaptions|>"].contains(where: { lexical.convertTokenToId($0) == 50362 }) else {
            throw Failure("Breeze tokenizer control IDs do not match the v2 decoder.")
        }
        try Task.checkCancellation()
        let loaded = try await WhisperKit(WhisperKitConfig(modelFolder: directory.path,
            tokenizerFolder: directory,
            computeOptions: ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine,
                                                textDecoderCompute: .cpuAndNeuralEngine),
            featureExtractor: CancellableWhisperModel(FeatureExtractor()),
            audioEncoder: CancellableWhisperModel(AudioEncoder()),
            textDecoder: CancellableWhisperModel(TextDecoder()),
            verbose: false, prewarm: false, load: false, download: false))
        loaded.tokenizer = PhoWhisperTokenizer(base: lexical)
        loaded.textDecoder.isModelMultilingual = true
        do {
            // Same existing VAD implementation/policy, no new detector or cropped audio.
            await SpeechSetupReporting.emit(.stage(.checkingDetection))
            try await SpeechSetupReporting.checkAdmission()
            vadMode = try SpeechPresencePolicy.Mode(arguments: ProcessInfo.processInfo.arguments)
            var detector: VadManager?
            if vadMode != .off {
                do {
                    await SpeechSetupReporting.emit(.stage(.preparingDetection))
                    try await SpeechSetupReporting.checkAdmission()
                    detector = try await VadManager(config: VadConfig(
                        defaultThreshold: SpeechPresencePolicy.threshold, computeUnits: .cpuAndNeuralEngine))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try Task.checkCancellation()
                    logger.warning("breeze_vad_unavailable phase=prepare action=allow_asr")
                }
            }
            try Task.checkCancellation()
            let receipt = try CoreMLPreparationReceipt(verifiedDirectory: directory, scope: .eager,
                computeUnits: ["mel": loaded.modelCompute.melCompute.rawValue,
                               "encoder": loaded.modelCompute.audioEncoderCompute.rawValue,
                               "decoder": loaded.modelCompute.textDecoderCompute.rawValue])
            _ = try await receipt.prepare(prewarm: {
                VietnameseEnglishRecognizer.logMemory(stage: "prewarm-begin", model: Self.identity)
                defer { VietnameseEnglishRecognizer.logMemory(stage: "prewarm-end", model: Self.identity) }
                try await loaded.prewarmModels()
            }, loadAndValidate: {
                VietnameseEnglishRecognizer.logMemory(stage: "load-begin", model: Self.identity)
                defer { VietnameseEnglishRecognizer.logMemory(stage: "load-end", model: Self.identity) }
                try await loaded.loadModels()
                await SpeechSetupReporting.emit(.stage(.validatingSpeech))
                try await SpeechSetupReporting.checkAdmission()
                guard loaded.textDecoder.logitsSize == 51865, loaded.audioEncoder.embedSize == 1280,
                      loaded.featureExtractor.melCount == 80, loaded.featureExtractor.windowSamples == 480_000 else {
                    throw Failure("Breeze compiled frontend/encoder/decoder shapes do not match.")
                }
            })
            try Task.checkCancellation()
            vad = detector; kit = loaded
            inferenceCount = 0
            #if MURAL_BREEZE_PAL4_TRIAL
            trialPrepared = true
            #endif
            VietnameseEnglishRecognizer.logMemory(stage: "loaded", model: Self.identity)
        } catch {
            await loaded.unloadModels()
            loaded.tokenizer = nil
            throw error
        }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard !busy, let kit else { throw Failure("Prepare Breeze before recording.") }
        guard samples.count <= 480_000, samples.allSatisfy(\.isFinite) else {
            throw Failure("Breeze accepts at most 30 seconds of finite 16 kHz mono audio.")
        }
        try Task.checkCancellation()
        guard !samples.isEmpty else { return "" }
        busy = true; defer { busy = false }
        #if MURAL_BREEZE_PAL4_TRIAL
        let trialStarted = ProcessInfo.processInfo.systemUptime
        var trialOutcome = "failed-or-cancelled"
        defer {
            logger.notice("breeze_trial_transcribe model=\(Self.identity, privacy: .public) outcome=\(trialOutcome, privacy: .public) samples=\(samples.count, privacy: .public) seconds=\(ProcessInfo.processInfo.systemUptime - trialStarted, privacy: .public) scope=asr-including-vad-not-ui-send")
            VietnameseEnglishRecognizer.logMemory(stage: "trial-transcribe-return", model: Self.identity)
        }
        #endif
        if vadMode != .off, let vad {
            do {
                var state = VadStreamState.initial()
                var evidence = SpeechPresencePolicy.Evidence(sampleCount: samples.count)
                for offset in stride(from: 0, to: samples.count, by: SpeechPresencePolicy.chunkSize) {
                    try Task.checkCancellation()
                    let chunk = Array(samples[offset..<min(offset + SpeechPresencePolicy.chunkSize, samples.count)])
                    let result = try await vad.processStreamingChunk(chunk, state: state)
                    try Task.checkCancellation()
                    state = result.state
                    evidence.append(probability: result.probability, sampleCount: chunk.count)
                }
                let rejected = evidence.rejects(in: vadMode)
                logger.notice("breeze_vad mode=\(self.vadMode.rawValue, privacy: .public) samples=\(samples.count, privacy: .public) complete=\(evidence.complete, privacy: .public) score=\(evidence.speechScore, privacy: .public) rejected=\(rejected, privacy: .public) trimming=false")
                if rejected {
                    #if MURAL_BREEZE_PAL4_TRIAL
                    trialOutcome = "vad-rejected"
                    #endif
                    return ""
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                // A detector failure is not evidence of silence; match the existing owner policy.
                logger.warning("breeze_vad_unavailable phase=turn action=allow_asr")
            }
        }
        var options = DecodingOptions(task: .transcribe, sampleLength: 220, detectLanguage: true,
            skipSpecialTokens: true, windowClipTime: 0, concurrentWorkerCount: 1)
        options.temperatureFallbackCount = 0
        options.withoutTimestamps = true
        options.suppressBlank = true
        options.suppressTokens = suppressTokens
        // Don't copy PhoWhisper's threshold overrides, force English, translate,
        // prompt with the reference, or normalize characters in the recognizer.
        let started = ProcessInfo.processInfo.systemUptime
        inferenceCount += 1
        logger.notice("breeze_inference_begin turn=\(self.inferenceCount, privacy: .public) first_since_prepare=\(self.inferenceCount == 1, privacy: .public)")
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        try Task.checkCancellation()
        logger.notice("breeze_decode scope=whisperkit-transcribe-not-ui-send seconds=\(ProcessInfo.processInfo.systemUptime - started, privacy: .public) windows=\(results.count, privacy: .public)")
        VietnameseEnglishRecognizer.logMemory(stage: "finalized", model: Self.identity)
        #if MURAL_BREEZE_PAL4_TRIAL
        trialOutcome = "completed"
        #endif
        return results.map(\.text).joined(separator: " ")
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
