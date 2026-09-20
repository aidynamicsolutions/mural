import Foundation
import CryptoKit
import FluidAudio
import MuralCore
import OSLog

/// Opt-in AED probe only. The existing audio task retains this actor until native work drains.
actor FireRedEnglishRecognizer {
    static var available: Bool {
        #if MURAL_FIRERED_FILE_PROBE
        true
        #else
        false
        #endif
    }

    nonisolated static var memoryDiagnostic: Bool {
        #if MURAL_FIRERED_FILE_PROBE
        ProcessInfo.processInfo.arguments.contains("--firered-memory-diagnostic")
        #else
        false
        #endif
    }

    nonisolated static func diagnosticMemory(_ stage: String) {
        guard memoryDiagnostic else { return }
        Logger(subsystem: "no.william.mural", category: "LocalAudio").notice("firered_memory_boundary stage=\(stage, privacy: .public) uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public)")
        VietnameseEnglishRecognizer.logMemory(stage: stage, model: "firered-memory-diagnostic")
    }

    #if MURAL_FIRERED_FILE_PROBE
    private var recognizer: OpaquePointer?
    private var vad: VadManager?
    private var vadMode: SpeechPresencePolicy.Mode = .off
    private var busy = false
    private let logger = Logger(subsystem: "no.william.mural", category: "LocalAudio")
    private static let identity = "firered-v2-aed-int8"

    deinit {
        if let recognizer { SherpaOnnxDestroyOfflineRecognizer(recognizer) }
        VietnameseEnglishRecognizer.logMemory(stage: "released", model: Self.identity)
    }

    private struct Pin: Decodable {
        struct Artifact: Decodable { let bytes: Int; let sha256: String }
        let model: String
        let sherpa_version: String
        let ort_version: String
        let artifacts: [String: Artifact]
    }

    @concurrent static func localDirectory() async throws -> URL {
        diagnosticMemory("verification-begin")
        defer { diagnosticMemory("verification-end") }
        guard let pinURL = Bundle.main.url(forResource: "pin", withExtension: "json") else {
            throw Failure("Missing built-in FireRed v2 AED pin.")
        }
        let pin = try JSONDecoder().decode(Pin.self, from: Data(contentsOf: pinURL))
        guard pin.model == "FireRedASR2-AED", pin.sherpa_version == String(cString: SherpaOnnxGetVersionStr()),
              pin.ort_version == MuralFireRedORTVersion(),
              Set(pin.artifacts.keys) == Set(["encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt"]) else {
            throw Failure("FireRed AED model/runtime identity mismatch. No fallback.")
        }
        let root = URL.documentsDirectory.appending(path: "FireRedProbe", directoryHint: .isDirectory)
        let folder = root.appending(path: "model", directoryHint: .isDirectory)
        for url in [root, folder] {
            guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw Failure("FireRed assets must not contain symbolic links.")
            }
        }
        for (name, artifact) in pin.artifacts {
            let url = folder.appending(path: name)
            let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true, attributes.fileSize == artifact.bytes else {
                throw Failure("Missing or wrong-sized pinned FireRed asset.")
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            while try autoreleasepool(invoking: { () throws -> Bool in
                try Task.checkCancellation()
                guard let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty else { return false }
                hash.update(data: bytes)
                return true
            }) {}
            guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == artifact.sha256 else {
                throw Failure("FireRed asset hash mismatch. No repair download or fallback.")
            }
        }
        var excluded = root
        var resources = URLResourceValues(); resources.isExcludedFromBackup = true
        try excluded.setResourceValues(resources)
        return folder
    }

    func prepare(directory: URL) async throws {
        guard !busy, recognizer == nil else { throw Failure("FireRed is busy or already prepared.") }
        busy = true; defer { busy = false }
        try checkReadyForWork()
        vadMode = try SpeechPresencePolicy.Mode(arguments: ProcessInfo.processInfo.arguments)
        if Self.memoryDiagnostic {
            guard vadMode != .off else { throw Failure("Memory diagnostic requires VAD.") }
            // Preserve existing assets even if Core ML loading fails. No repair or download.
            ModelHub.offlineMode = true
        }
        if vadMode != .off {
            Self.diagnosticMemory("vad-prepare-begin")
            defer { Self.diagnosticMemory("vad-prepare-end") }
            do {
                vad = try await VadManager(config: VadConfig(
                    defaultThreshold: SpeechPresencePolicy.threshold, computeUnits: .cpuAndNeuralEngine))
            } catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                if Self.memoryDiagnostic { throw error }
                logger.warning("firered_vad_unavailable phase=prepare action=allow_asr")
            }
        }
        try checkReadyForWork()
        let started = ProcessInfo.processInfo.systemUptime
        logger.notice("firered_native_begin phase=prepare uptime=\(started, privacy: .public) cpu_threads=1")
        defer {
            logger.notice("firered_native_return phase=prepare uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public) cancelled=\(Task.isCancelled, privacy: .public)")
            VietnameseEnglishRecognizer.logMemory(stage: "prepared-or-draining", model: Self.identity)
        }
        Self.diagnosticMemory("native-prepare-begin")
        // Every config string lives through the synchronous constructor; sherpa copies its config.
        recognizer = directory.appending(path: "encoder.int8.onnx").path.withCString { encoder in
            directory.appending(path: "decoder.int8.onnx").path.withCString { decoder in
                directory.appending(path: "tokens.txt").path.withCString { tokens in
                    "cpu".withCString { provider in
                        "greedy_search".withCString { decoding in
                            var config = SherpaOnnxOfflineRecognizerConfig()
                            config.feat_config.sample_rate = 16_000
                            config.feat_config.feature_dim = 80
                            config.model_config.fire_red_asr.encoder = encoder
                            config.model_config.fire_red_asr.decoder = decoder
                            config.model_config.tokens = tokens
                            config.model_config.provider = provider
                            config.model_config.num_threads = 1
                            config.decoding_method = decoding
                            return SherpaOnnxCreateOfflineRecognizer(&config)
                        }
                    }
                }
            }
        }
        guard recognizer != nil else { throw Failure("Native FireRed AED preparation failed.") }
        try checkReadyForWork()
        guard ProcessInfo.processInfo.systemUptime - started <= 60 else {
            throw Failure("FireRed preparation exceeded 60 seconds. Stop qualification; do not retry.")
        }
    }

    private func checkReadyForWork() throws {
        try Task.checkCancellation()
        guard ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else {
            throw Failure("Serious thermal state. Stop FireRed qualification.")
        }
    }
    #endif

    func transcribe(_ samples: [Float]) async throws -> String {
        #if MURAL_FIRERED_FILE_PROBE
        guard !busy, let recognizer else { throw Failure("Prepare FireRed before recording.") }
        guard samples.count <= 480_000, samples.allSatisfy(\.isFinite) else {
            throw Failure("FireRed accepts at most 30 seconds of finite 16 kHz mono audio.")
        }
        try checkReadyForWork()
        guard !samples.isEmpty else { return "" }
        busy = true; defer { busy = false }
        // Reuse the accepted whole-turn speech gate, without changing waveform/script/words.
        if vadMode != .off, let vad {
            Self.diagnosticMemory("vad-turn-begin")
            defer { Self.diagnosticMemory("vad-turn-end") }
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
                logger.notice("firered_vad mode=\(self.vadMode.rawValue, privacy: .public) samples=\(samples.count, privacy: .public) complete=\(evidence.complete, privacy: .public) rejected=\(rejected, privacy: .public) trimming=false")
                if rejected { return "" }
            } catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                if Self.memoryDiagnostic { throw error }
                logger.warning("firered_vad_unavailable phase=turn action=allow_asr")
            }
        }
        try checkReadyForWork()
        let started = ProcessInfo.processInfo.systemUptime
        logger.notice("firered_native_begin phase=decode uptime=\(started, privacy: .public) samples=\(samples.count, privacy: .public)")
        defer {
            logger.notice("firered_native_return phase=decode uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public) seconds=\(ProcessInfo.processInfo.systemUptime - started, privacy: .public) cancelled=\(Task.isCancelled, privacy: .public)")
            VietnameseEnglishRecognizer.logMemory(stage: "finalized-or-draining", model: Self.identity)
        }
        // No suspension while a stream/result exists. Cancellation only takes effect after C returns.
        let text = try samples.withUnsafeBufferPointer { buffer -> String in
            guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else { throw Failure("Native stream creation failed.") }
            defer { SherpaOnnxDestroyOfflineStream(stream) }
            SherpaOnnxAcceptWaveformOffline(stream, 16_000, buffer.baseAddress, Int32(buffer.count))
            SherpaOnnxDecodeOfflineStream(recognizer, stream)
            try checkReadyForWork()
            guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { throw Failure("Native result missing.") }
            defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
            guard let raw = result.pointee.text, let text = String(validatingCString: raw) else {
                throw Failure("Invalid native transcript encoding.")
            }
            return text
        }
        guard ProcessInfo.processInfo.systemUptime - started <= 60 else {
            throw Failure("FireRed decoding exceeded 60 seconds. Stop qualification; do not retry.")
        }
        return text
        #else
        throw Failure("FireRed is not included in this build.")
        #endif
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
