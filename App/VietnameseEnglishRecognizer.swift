import CoreML
import Darwin
import FluidAudio
import ArgmaxCore
import Foundation
import OSLog

/// Fixed Phase 2 community conversion, not a general ASR provider.
/// The audio owner serializes calls and retains this actor until cancellation ends.
actor VietnameseEnglishRecognizer {
    static let maxSeconds = 15
    private static let maxSamples = 240_000
    private static let revision = "8e7545c334001a4a135aa031095538ff97487089"
    private var models: CtcModels?

    static func download(repair: Bool) async throws -> URL {
        var base = URL.applicationSupportDirectory.appending(path: "ParakeetVietnameseEnglish", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var resources = URLResourceValues(); resources.isExcludedFromBackup = true
        try base.setResourceValues(resources)
        let hub = HubApiWrapper(downloadBase: base)
        let repo = HubApiWrapper.Repo(id: "leakless/parakeet-ctc-0.6b-Vietnamese-coreml")
        let folder = hub.localRepoLocation(repo)
        let required = ["vocab.json", "config.json"] + ["MelSpectrogram", "AudioEncoder"].flatMap { model in
            ["coremldata.bin", "metadata.json", "model.mil", "weights/weight.bin"].map { "\(model).mlmodelc/\($0)" }
        }
        if repair || !required.allSatisfy({ FileManager.default.fileExists(atPath: folder.appending(path: $0).path) }) {
            _ = try await hub.snapshot(from: repo, revision: revision,
                matching: ["MelSpectrogram.mlmodelc/*", "AudioEncoder.mlmodelc/*", "vocab.json", "config.json"])
        }
        return folder
    }

    func prepare(directory: URL) async throws {
        let loaded = try await CtcModels.loadDirect(from: directory)
        try Task.checkCancellation()
        guard loaded.vocabulary.count == 1024,
              (0..<1024).allSatisfy({ loaded.vocabulary[$0] != nil }) else { throw RecognitionError.contract }
        let mel = loaded.melSpectrogram.modelDescription
        let encoder = loaded.encoder.modelDescription
        guard Self.matches(mel.inputDescriptionsByName["audio"], [1, 240000], .float32),
              Self.matches(mel.inputDescriptionsByName["audio_length"], [1], .int32),
              Self.matches(mel.outputDescriptionsByName["melspectrogram_features"], [1, 80, 1501], .float32),
              Self.matches(mel.outputDescriptionsByName["mel_length"], [1], .int32),
              Self.matches(encoder.inputDescriptionsByName["melspectrogram_features"], [1, 80, 1501], .float32),
              Self.matches(encoder.inputDescriptionsByName["mel_length"], [1], .int32),
              Self.matches(encoder.outputDescriptionsByName["ctc_head_raw_output"], [1, 188, 1025], .float32)
        else { throw RecognitionError.contract }
        models = loaded
        Self.logMemory(stage: "loaded")
    }

    private static func matches(_ feature: MLFeatureDescription?, _ shape: [Int], _ type: MLMultiArrayDataType) -> Bool {
        feature?.multiArrayConstraint?.shape.map(\.intValue) == shape && feature?.multiArrayConstraint?.dataType == type
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let models else { throw RecognitionError.notReady }
        try Task.checkCancellation()
        guard samples.count <= Self.maxSamples, samples.allSatisfy(\.isFinite) else { throw RecognitionError.audio }
        guard !samples.isEmpty else { return "" }
        // This export performs pre-emphasis, mel extraction and masked normalization.
        // Supply actual length; do not normalize again or score zero-padding as speech.
        let audio = try MLMultiArray(shape: [1, NSNumber(value: Self.maxSamples)], dataType: .float32)
        let pointer = audio.dataPointer.assumingMemoryBound(to: Float.self)
        for index in 0..<Self.maxSamples { pointer[index] = index < samples.count ? samples[index] : 0 }
        let length = try MLMultiArray(shape: [1], dataType: .int32)
        length[0] = NSNumber(value: samples.count)
        let input = try MLDictionaryFeatureProvider(dictionary: ["audio": audio, "audio_length": length])
        let melOutput = try await models.melSpectrogram.prediction(from: input, options: MLPredictionOptions())
        try Task.checkCancellation()
        guard let mel = melOutput.featureValue(for: "melspectrogram_features")?.multiArrayValue,
              let melLength = melOutput.featureValue(for: "mel_length")?.multiArrayValue,
              melLength.count == 1, (0...1500).contains(melLength[0].intValue)
        else { throw RecognitionError.contract }
        let encoderInput = try MLDictionaryFeatureProvider(dictionary: ["melspectrogram_features": mel, "mel_length": melLength])
        let output = try await models.encoder.prediction(from: encoderInput, options: MLPredictionOptions())
        try Task.checkCancellation()
        guard let logits = output.featureValue(for: "ctc_head_raw_output")?.multiArrayValue,
              logits.dataType == .float32, logits.shape.map(\.intValue) == [1, 188, 1025]
        else { throw RecognitionError.contract }
        // Pinned MIL applies ceil(length / 2) three times, equivalent to ceil(length / 8).
        let validFrames = (melLength[0].intValue + 7) / 8
        let strides = logits.strides.map(\.intValue)
        let values = logits.dataPointer.assumingMemoryBound(to: Float.self)
        var frames: [[Float]] = []
        for frame in 0..<validFrames {
            try Task.checkCancellation()
            let row = (0..<1025).map { values[frame * strides[1] + $0 * strides[2]] }
            guard row.allSatisfy(\.isFinite) else { throw RecognitionError.contract }
            frames.append(row)
        }
        // The library's MLMultiArray overload assumes contiguous rows. Use its
        // array overload instead; raw logits and log-probabilities have equal argmax.
        let text = ctcGreedyDecode(logProbs: frames, vocabulary: models.vocabulary, blankId: 1024)
        Logger(subsystem: "no.william.mural", category: "LocalAudio").notice("asr_decode model=parakeet valid_frames=\(validFrames, privacy: .public) thermal_state=\(ProcessInfo.processInfo.thermalState.rawValue, privacy: .public)")
        Self.logMemory(stage: "finalized")
        return text
    }

    @discardableResult
    nonisolated static func logMemory(stage: String, model: String = "parakeet") -> [String: UInt64] {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return [:] }
        // Kernel process-lifetime peaks, distinct from this phase sample and model-only memory.
        let footprintPeak = UInt64(max(0, info.ledger_phys_footprint_peak))
        Logger(subsystem: "no.william.mural", category: "LocalAudio").notice("asr_memory model=\(model, privacy: .public) stage=\(stage, privacy: .public) footprint_bytes=\(info.phys_footprint, privacy: .public) process_footprint_peak_bytes=\(footprintPeak, privacy: .public) process_rss_peak_bytes=\(info.resident_size_peak, privacy: .public) thermal_state=\(ProcessInfo.processInfo.thermalState.rawValue, privacy: .public)")
        return ["footprintBytes": info.phys_footprint, "processFootprintPeakBytes": footprintPeak, "processRSSPeakBytes": info.resident_size_peak]
    }

    private enum RecognitionError: LocalizedError {
        case contract, notReady, audio
        var errorDescription: String? {
            switch self {
            case .contract: "Parakeet's model, vocabulary, or output does not match the tested format. Stop and report this error; no transcript was accepted."
            case .notReady: "Prepare Parakeet before recording."
            case .audio: "Parakeet accepts at most 15 seconds of finite 16 kHz mono audio. Record a shorter turn."
            }
        }
    }
}
