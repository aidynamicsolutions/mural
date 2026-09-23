import CoreML
import CryptoKit
import FluidAudio
import Foundation
import MuralCore

extension Supertonic3Voice {
    var muralName: String {
        switch self {
        case .f1: "Bella"
        case .f2: "Clara"
        case .f3: "Maya"
        case .f4: "Nora"
        case .f5: "Zoe"
        case .m1: "Adam"
        case .m2: "Jack"
        case .m3: "Leo"
        case .m4: "Ethan"
        case .m5: "Theo"
        }
    }
}

enum SupertonicSpeed: String, CaseIterable, Identifiable {
    case verySlow = "0.70", slow = "0.80", relaxed = "0.90", normal = "1.00"
    case balanced = "1.05", brisk = "1.15", fast = "1.25", veryFast = "1.50"
    var id: String { rawValue }
    var value: Float { Float(rawValue)! }
    var valueLabel: String { "\(rawValue.replacingOccurrences(of: #"0$"#, with: "", options: .regularExpression))×" }
    var label: String {
        let name = switch self {
        case .verySlow: "Very slow"
        case .slow: "Slow"
        case .relaxed: "Relaxed"
        case .normal: "Normal"
        case .balanced: "Balanced"
        case .brisk: "Brisk"
        case .fast: "Fast"
        case .veryFast: "Very fast"
        }
        return "\(valueLabel) · \(name)"
    }
}

enum LocalTTSBackend: String, CaseIterable, Identifiable {
    case apple, supertonic, kokoro
    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: "Apple voice"
        case .supertonic: "Mural Voice (Supertonic-3 int4)"
        case .kokoro: "Kokoro-82M (blocked)"
        }
    }
    func voice(supertonic: Supertonic3Voice, speed: SupertonicSpeed) -> String {
        switch self {
        case .apple: OnDeviceSpeechVoiceCatalog.resolvedVoice().map(OnDeviceSpeechVoiceCatalog.description) ?? "Unavailable"
        case .supertonic: "\(supertonic.muralName) (\(supertonic.rawValue)) · 8 steps · speed \(speed.label)"
        case .kokoro: "af_heart - runtime undecided"
        }
    }
    func checkAvailable() throws {
        if self == .kokoro { throw LocalNeuralTTS.Failure(message: "Kokoro CoreML is blocked on iOS 27. No model was loaded or Apple substitution made.") }
        #if targetEnvironment(simulator)
        if self == .supertonic { throw LocalNeuralTTS.Failure(message: "Mural Voice requires the paired physical phone. Simulator checks use Apple or explicit synthetic PCM.") }
        #endif
    }
}

/// One manager, serialized by the audio owner's admission gate. Never clean up during native work.
@MainActor final class LocalNeuralTTS {
    private var manager: Supertonic3Manager?
    private var style: Supertonic3VoiceStyle?
    private var syntheses = 0
    var hasResources: Bool { manager != nil }
    var isReady: Bool { style != nil }
    private(set) var preparation: [String: Any] = [:]

    struct Render {
        let audio: LocalTTSAudio
        let synthMilliseconds: Double
        let first: Bool
    }
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Existence preflight only, using the downloader's own cache layout/inventory.
    /// Normal acquisition and native loading remain authoritative after consent.
    static func needsDownload(voice: Supertonic3Voice) throws -> Bool {
        let repo = try TtsCacheDirectory.ensure().appending(path: "Models/\(Repo.supertonic3.folderName)")
        let required = ModelNames.Supertonic3.requiredFiles(veVariant: "ane-int4").union([voice.fileName])
        return !required.allSatisfy { FileManager.default.fileExists(atPath: repo.appending(path: $0).path) }
    }

    func prepare(voice selectedVoice: Supertonic3Voice,
                 setup: @escaping @MainActor @Sendable (SpeechSetupProgress) -> Void = { _ in },
                 progress: @escaping @MainActor @Sendable (String) -> Void) async throws {
        try Task.checkCancellation()
        if style != nil { return }
        preparation = [:]
        let model = Supertonic3Manager(computeUnits: .cpuAndNeuralEngine, vectorEstimator: .aneBucketed(.int4))
        manager = model // Retain even on failure until the owned worker has drained.
        let begin = ProcessInfo.processInfo.systemUptime
        func reporter(_ stage: SpeechSetupProgress.Stage) -> ProgressHandler {
            { value in
                let update: SpeechSetupProgress
                switch value.phase {
                case .listing: update = .init(.checkingVoice)
                case .downloading: update = .init(stage, fraction: value.fractionCompleted)
                case .compiling: update = .init(.preparingVoice)
                }
                Task { @MainActor in setup(update) }
            }
        }
        setup(.init(.checkingVoice))
        progress("Checking/downloading Mural Voice assets for \(selectedVoice.muralName)…")
        let repo = try await Supertonic3ResourceDownloader.ensureModels(veVariant: "ane-int4", progressHandler: reporter(.downloadingVoice))
        try Task.checkCancellation()
        let voice = try await Supertonic3ResourceDownloader.loadVoiceStyle(selectedVoice, progressHandler: reporter(.downloadingVoiceStyle))
        let acquired = ProcessInfo.processInfo.systemUptime
        try Task.checkCancellation()
        var cache = repo
        var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try cache.setResourceValues(attributes)
        // Refuse a changed config instead of silently relabeling its samples as 44.1 kHz.
        let config = try JSONDecoder().decode(Supertonic3Config.self, from: Data(contentsOf: repo.appending(path: "tts.json")))
        guard config.ae.sampleRate == 44_100 else { throw Failure(message: "Unexpected Mural Voice sample rate. No audio played.") }
        setup(.init(.checkingVoice))
        progress("Recording acquired asset identity…")
        let inventory = try await Self.inventory(repo: repo, voice: selectedVoice)
        try Task.checkCancellation()
        setup(.init(.preparingVoice))
        progress("Loading Mural Voice. First use can take longer…")
        let loadStart = ProcessInfo.processInfo.systemUptime
        // The SDK owns the individual voice models. Time this opaque boundary without
        // pretending its synchronous native loads can be forcibly interrupted.
        try await SpeechPreparationStep.run(model: "supertonic3-ane-int4", component: "voice-models", phase: "load") {
            try await model.initialize()
        }
        try Task.checkCancellation()
        style = voice; syntheses = 0
        preparation = ["acquisition_or_cache_check_ms": (acquired - begin) * 1_000,
                       "prepare_ms": (ProcessInfo.processInfo.systemUptime - loadStart) * 1_000,
                       "asset_inventory_sha256": inventory, "asset_root": repo.path,
                       "variant": "ane-int4", "voice": selectedVoice.rawValue, "steps": 8,
                       "inter_chunk_silence_seconds": 0.05, "requested_compute_units": "cpuAndNeuralEngine",
                       "actual_ane_placement": "not-profiled", "latin_chunk_limit": Supertonic3Constants.maxChunkLengthLatin,
                       "token_window": Supertonic3Constants.textTFixed]
    }

    func synthesize(_ text: String, speed: Float) async throws -> Render {
        let text = try LocalTTSAudio.validatedSupertonicText(text,
            chunkLimit: Supertonic3Constants.maxChunkLengthLatin, tokenLimit: Supertonic3Constants.textTFixed)
        guard let manager, let style else { throw Failure(message: "Mural Voice is not prepared.") }
        let first = syntheses == 0
        syntheses += 1
        let start = ProcessInfo.processInfo.systemUptime
        let rendered = try await manager.synthesize(text: text, language: "en", style: style, totalSteps: 8, speed: speed, silenceDuration: 0.05)
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        let audio = try LocalTTSAudio(samples: rendered.samples, sampleRate: 44_100)
        return Render(audio: audio, synthMilliseconds: elapsed, first: first)
    }

    func unload() async {
        if let manager { await manager.cleanup() }
        manager = nil; style = nil; syntheses = 0
    }

    /// One acquired-asset inventory, outside initialization/synthesis timing and off the UI executor.
    /// Existing caches are preserved; no download/rehash occurs per utterance.
    @concurrent private static func inventory(repo: URL, voice: Supertonic3Voice) async throws -> String {
        // File enumeration resolves /var to /private/var on device; use the same root for relative paths.
        let repo = repo.resolvingSymlinksInPath()
        let destination = URL.documentsDirectory.appending(path: "TTSComparison/supertonic-assets-v3-\(voice.rawValue).json")
        if FileManager.default.fileExists(atPath: destination.path) {
            return SHA256.hash(data: try Data(contentsOf: destination)).map { String(format: "%02x", $0) }.joined()
        }
        var files: [[String: Any]] = []
        let roots = ModelNames.Supertonic3.requiredFiles(veVariant: "ane-int4").union([voice.fileName])
        for path in roots.sorted() {
            let url = repo.appending(path: path)
            let urls: [URL]
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else { throw CocoaError(.fileReadUnknown) }
                urls = enumerator.compactMap { $0 as? URL }.sorted { $0.path < $1.path }
            } else { urls = [url] }
            for file in urls where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                var hash = SHA256(); var bytes = 0
                while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                    try Task.checkCancellation(); hash.update(data: data); bytes += data.count
                }
                let canonicalPath = file.resolvingSymlinksInPath().path
                guard canonicalPath.hasPrefix(repo.path + "/") else { throw CocoaError(.fileReadInvalidFileName) }
                files.append(["path": String(canonicalPath.dropFirst(repo.path.count + 1)), "bytes": bytes,
                              "sha256": hash.finalize().map { String(format: "%02x", $0) }.joined()])
            }
        }
        let data = try JSONSerialization.data(withJSONObject: ["repository": "FluidInference/supertonic-3-coreml",
            "revision": "downloader main; exact acquired bytes recorded below", "variant": "ane-int4", "voice": voice.rawValue, "files": files], options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension LocalTTSAudio {
    static func testSignal(sampleRate: Double) throws -> Self {
        guard sampleRate == 24_000 || sampleRate == 44_100 else { throw LocalTTSError.invalidAudio }
        let count = Int(sampleRate)
        let samples = (0..<count).map { index -> Float in
            let time = Double(index) / sampleRate
            let envelope = min(1, min(time / 0.02, (1 - time) / 0.02))
            return Float(0.035 * envelope * sin(2 * .pi * 440 * time))
        }
        return try Self(samples: samples, sampleRate: sampleRate)
    }
}
