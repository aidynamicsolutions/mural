import AVFoundation
import CryptoKit
import CoreML
import Foundation
import MuralCore
import Observation
import OSLog
import FluidAudio
import WhisperKit
#if canImport(CoreAI)
import CoreAI
import ArgmaxCore
#endif

enum LocalSpeechVoice {
    static let preferenceKey = "localTTSVoiceIdentifier"
    static let language = "en-US"

    struct Option: Identifiable, Hashable {
        let id: String
        let name: String
        let language: String
        let qualityLabel: String
        let qualityRank: Int

        var label: String { "\(name) · \(qualityLabel)" }
        var isPremium: Bool { qualityRank == 3 }
    }

    static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter(isEligible)
            .sorted { lhs, rhs in
                let leftRank = qualityRank(lhs.quality)
                let rightRank = qualityRank(rhs.quality)
                if leftRank != rightRank { return leftRank > rightRank }
                let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return lhs.identifier < rhs.identifier
            }
    }

    static func availableOptions() -> [Option] {
        availableVoices().map { voice in
            Option(id: voice.identifier, name: voice.name, language: voice.language,
                   qualityLabel: qualityLabel(voice.quality), qualityRank: qualityRank(voice.quality))
        }
    }

    static func resolvedVoice() -> AVSpeechSynthesisVoice? {
        if let identifier = UserDefaults.standard.string(forKey: preferenceKey),
           !identifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: identifier),
           isEligible(voice) {
            return voice
        }
        return availableVoices().first ?? AVSpeechSynthesisVoice(language: language)
    }

    static func description(for voice: AVSpeechSynthesisVoice) -> String {
        "\(voice.name) (\(voice.language)) · \(qualityLabel(voice.quality))"
    }

    private static func isEligible(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.language == language &&
        !voice.voiceTraits.contains(.isNoveltyVoice) &&
        !voice.voiceTraits.contains(.isPersonalVoice)
    }

    private static func qualityRank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        if quality == .premium { return 3 }
        if quality == .enhanced { return 2 }
        return 1
    }

    private static func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        if quality == .premium { return "Premium" }
        if quality == .enhanced { return "Enhanced" }
        return "Standard"
    }
}

/// Intercepts only WhisperKit's public model-loading seam. Inference, tensor shapes,
/// tokenizer state, unload and compute choices remain owned by the original components.
/// A subclass cannot override the base class's protocol-extension load witness.
final class CancellableWhisperModel<Model: WhisperMLModel>: WhisperMLModel {
    private var base: Model
    init(_ base: Model) { self.base = base }
    var model: MLModel? { get { base.model } set { base.model = newValue } }
    func loadModel(at path: URL, computeUnits: MLComputeUnits, prewarmMode: Bool = false) async throws {
        try await SpeechPreparationStep.run(model: path.deletingLastPathComponent().lastPathComponent,
            component: path.deletingPathExtension().lastPathComponent, phase: prewarmMode ? "prewarm" : "load") {
            try await base.loadModel(at: path, computeUnits: computeUnits, prewarmMode: prewarmMode)
        }
    }
    func unloadModel() { base.unloadModel() }
}

extension CancellableWhisperModel: FeatureExtracting where Model: FeatureExtracting {
    var melCount: Int? { base.melCount }
    var windowSamples: Int? { base.windowSamples }
    func logMelSpectrogram(fromAudio input: any AudioProcessorOutputType) async throws -> (any FeatureExtractorOutputType)? {
        try await base.logMelSpectrogram(fromAudio: input)
    }
}

extension CancellableWhisperModel: AudioEncoding where Model: AudioEncoding {
    var embedSize: Int? { base.embedSize }
    func encodeFeatures(_ features: any FeatureExtractorOutputType) async throws -> (any AudioEncoderOutputType)? {
        try await base.encodeFeatures(features)
    }
}

extension CancellableWhisperModel: TextDecoding where Model: TextDecoding {
    var tokenizer: WhisperTokenizer? { get { base.tokenizer } set { base.tokenizer = newValue } }
    var isModelMultilingual: Bool { get { base.isModelMultilingual } set { base.isModelMultilingual = newValue } }
    var logitsFilters: [any LogitsFiltering]? { get { base.logitsFilters } set { base.logitsFilters = newValue } }
    var supportsWordTimestamps: Bool { base.supportsWordTimestamps }
    var logitsSize: Int? { base.logitsSize }
    var kvCacheEmbedDim: Int? { base.kvCacheEmbedDim }
    var kvCacheMaxSequenceLength: Int? { base.kvCacheMaxSequenceLength }
    var windowSize: Int? { base.windowSize }
    var embedSize: Int? { base.embedSize }
    func predictLogits(_ inputs: any TextDecoderInputType) async throws -> (any TextDecoderOutputType)? {
        try await base.predictLogits(inputs)
    }
    func prepareDecoderInputs(withPrompt prompt: [Int]) throws -> any DecodingInputsType {
        try base.prepareDecoderInputs(withPrompt: prompt)
    }
    func prefillDecoderInputs(_ inputs: any DecodingInputsType, withOptions options: DecodingOptions?) async throws -> any DecodingInputsType {
        try await base.prefillDecoderInputs(inputs, withOptions: options)
    }
    func decodeText(from encoder: any AudioEncoderOutputType, using inputs: any DecodingInputsType,
                    sampler: any TokenSampling, options: DecodingOptions, callback: TranscriptionCallback?) async throws -> DecodingResult {
        try await base.decodeText(from: encoder, using: inputs, sampler: sampler, options: options, callback: callback)
    }
    func detectLanguage(from encoder: any AudioEncoderOutputType, using inputs: any DecodingInputsType,
                        sampler: any TokenSampling, options: DecodingOptions, temperature: FloatType) async throws -> DecodingResult {
        try await base.detectLanguage(from: encoder, using: inputs, sampler: sampler, options: options, temperature: temperature)
    }
    static func updateKVCache(keyTensor: MLMultiArray, keySlice: MLMultiArray, valueTensor: MLMultiArray,
                              valueSlice: MLMultiArray, insertAtIndex index: Int) {
        Model.updateKVCache(keyTensor: keyTensor, keySlice: keySlice, valueTensor: valueTensor, valueSlice: valueSlice, insertAtIndex: index)
    }
}

/// Half-duplex local audio owner. The Phase 2 probe exposes ASR without tutor inference.
@MainActor @Observable final class LocalConversationEngine: NSObject, AVSpeechSynthesizerDelegate {
    enum SafetyStopReason: Equatable { case memoryPressure, thermal }
    @ObservationIgnored var onPlayback: ((Double, Double?, Bool) -> Void)?
    private(set) var playbackStartSeconds: Double?
    private(set) var playbackDurationSeconds: Double?
    private(set) var voiceDescription = "English system voice"
    private(set) var preparationProgress = SpeechSetupProgress(.checking)
    var conversationVoiceNeedsDownload: Bool {
        get throws {
            guard conversationTTSBackend == .supertonic else { return false }
            return try LocalNeuralTTS.needsDownload(voice: supertonicVoice)
        }
    }
    var speechDetectionNeedsDownload: Bool {
        get throws {
            guard try SpeechPresencePolicy.Mode(arguments: ProcessInfo.processInfo.arguments) != .off else { return false }
            // Same default root and model inventory as FluidAudio's VadManager.
            let root = URL.applicationSupportDirectory.appending(path: "FluidAudio/Models/\(Repo.vad.folderName)")
            return !ModelNames.VAD.requiredModels.allSatisfy {
                FileManager.default.fileExists(atPath: root.appending(path: "\($0)/coremldata.bin").path)
            }
        }
    }
    enum ASRState: String {
        case idle = "Prepare speech models", downloading = "Downloading or checking cached assets…"
        case warming = "Preparing speech…", ready = "Ready to record"
        case recording = "Recording", transcribing = "Finalizing speech…", ended = "Stopped", failed = "Speech unavailable"
    }
    enum ASRModel: String, CaseIterable {
        case phoWhisper = "PhoWhisper CS", parakeet = "Parakeet VI–EN", whisper = "Whisper", nemotron = "Nemotron"
        case breeze = "Breeze TW–EN (test)"
        #if MURAL_VAD_PROBE
        case vadOnly = "Silero VAD only (no ASR)"
        #endif
        #if MURAL_FIRERED_FILE_PROBE
        case fireRed = "FireRed v2 CN-EN (probe)"
        #endif

        var supportsRepairDownload: Bool {
            switch self {
            case .phoWhisper, .breeze: false
            #if MURAL_VAD_PROBE
            case .vadOnly: false
            #endif
            #if MURAL_FIRERED_FILE_PROBE
            case .fireRed: false
            #endif
            default: true
            }
        }
    }
    private(set) var asrModel: ASRModel = .phoWhisper
    private var whisper: WhisperRecognizer?
    private var parakeet: VietnameseEnglishRecognizer?
    private var breeze: BreezeEnglishRecognizer?
    private var fireRed: FireRedEnglishRecognizer?
    var recordingLimitSeconds: Int { asrModel == .parakeet ? VietnameseEnglishRecognizer.maxSeconds : 30 }
    private(set) var preparationDetail = ""
    private(set) var asrState: ASRState = .idle
    private(set) var asrText = ""
    private(set) var rawASRText = ""
    private(set) var lastRecordingHadNoSpeech = false
    private(set) var asrError: String?
    private(set) var asrNotice: String?
    private(set) var capturedSeconds = 0.0
    private(set) var finalizeSeconds: Double?
    private(set) var preparationSeconds: Double?
    private(set) var inputDescription = "Microphone off"
    private var asr: StreamingNemotronMultilingualAsrManager?
    private var asrTask: Task<Void, Never>?
    private var stagedDecoderWarmup: Task<Void, Error>?
    private var stagedDecoderWarmupActive = false
    private var limitTask: Task<Void, Never>?
    private var tapInstalled = false
    private var audioEngine: AVAudioEngine?
    private var capture: AsyncThrowingStream<AVReadOnlyAudioPCMBuffer, Error>.Continuation?
    private var generation = UUID()
    private var trialFirstAudioGeneration: UUID?
    private var submittedAt: Double?
    var lastSubmissionTime: Double? { submittedAt }
    private(set) var sendToPlaybackSeconds: Double?
    private var variantDirectory: URL?
    private var ownsAudio = false
    private var audioRelease: Task<Void, Never>?
    var asrBusy: Bool { asrTask != nil }
    var modelWorkDraining: Bool { stagedDecoderWarmupActive && (asrState == .ended || asrState == .failed) }
    private var speechAdmission = LocalSpeechAdmission()
    private var speechTask: Task<Void, Error>?
    private var speechStopRequestedAt: Double?
    private(set) var speechDrainMilliseconds: Double?
    private(set) var speechStopMilliseconds: Double?
    var speechBusy: Bool {
        if ttsCleanup != nil { return true }
        return speechAdmission.isBusy
    }
    var speechDraining: Bool {
        if ttsCleanup != nil { return true }
        return speechAdmission.isDraining
    }
    private let pcmPlayback = LocalPCMPlayback()
    private let neuralTTS = LocalNeuralTTS()
    private var ttsCleanup: Task<Void, Never>?
    private var ttsConversationMonitor: Task<Void, Never>?
    private(set) var thermalStopped = false
    #if DEBUG && targetEnvironment(simulator)
    var testThermalState: ProcessInfo.ThermalState?
    @ObservationIgnored var testTTSSafetySampler: (@MainActor @Sendable () async -> [String: UInt64])?
    var testTTSConversationMonitorTask: Task<Void, Never>? { ttsConversationMonitor }
    #endif
    var ttsThermalState: ProcessInfo.ThermalState {
        #if DEBUG && targetEnvironment(simulator)
        if let testThermalState { return testThermalState }
        #endif
        return ProcessInfo.processInfo.thermalState
    }

    func resumeAfterCooling() throws {
        guard ttsThermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else { throw LocalTTSError.phoneTooWarm }
        thermalStopped = false
        asrError = nil
    }

    func stopForTTSSafety(footprint: UInt64, thermal: ProcessInfo.ThermalState) {
        let memoryStop = footprint >= 3_000_000_000
        guard memoryStop || thermal.rawValue >= ProcessInfo.ThermalState.serious.rawValue else { return }
        let reason: SafetyStopReason
        if memoryStop { reason = .memoryPressure }
        else { thermalStopped = true; reason = .thermal }
        stop()
        logger.fault("tts_safety_stop max_sampled_footprint_bytes=\(footprint, privacy: .public) thermal_state=\(thermal.rawValue, privacy: .public)")
        onSafetyStop?(reason)
    }
    private static let conversationTTSPreferenceKey = "localConversationTTSBackend"
    private(set) var conversationTTSBackend = LocalTTSBackend(
        rawValue: UserDefaults.standard.string(forKey: LocalConversationEngine.conversationTTSPreferenceKey) ?? ""
    ) ?? .supertonic
    private(set) var supertonicVoice = Supertonic3Voice(rawValue: UserDefaults.standard.string(forKey: "supertonicVoice") ?? "") ?? .m5
    private(set) var supertonicSpeed = SupertonicSpeed(rawValue: UserDefaults.standard.string(forKey: "supertonicSpeed") ?? "") ?? .normal
    var ttsVoiceDescription: String { ttsBackend.voice(supertonic: supertonicVoice, speed: supertonicSpeed) }

    func selectSupertonicVoice(_ voice: Supertonic3Voice) throws {
        guard canSelectTTS else { throw LocalTTSError.busy }
        guard voice != supertonicVoice else { return }
        unloadTTSAfterDrain()
        supertonicVoice = voice
        UserDefaults.standard.set(voice.rawValue, forKey: "supertonicVoice")
    }

    func selectSupertonicSpeed(_ speed: SupertonicSpeed) throws {
        guard canSelectTTS else { throw LocalTTSError.busy }
        supertonicSpeed = speed
        UserDefaults.standard.set(speed.rawValue, forKey: "supertonicSpeed")
    }

    var onSafetyStop: (@MainActor (SafetyStopReason) -> Void)?
    struct TTSSynthesisMetrics {
        let milliseconds: Double
        let audioMilliseconds: Double
        let first: Bool
        let clipping: Bool
    }
    private(set) var lastSynthesis: TTSSynthesisMetrics?
    var ttsPreparation: [String: Any] { neuralTTS.preparation }
    private(set) var ttsBackend: LocalTTSBackend = .apple
    var canSelectTTS: Bool { !speechBusy && !asrBusy && !stagedDecoderWarmupActive && canPrepare }

    func selectTTS(_ backend: LocalTTSBackend) throws {
        guard canSelectTTS else { throw LocalTTSError.busy }
        if backend != ttsBackend { unloadTTSAfterDrain() }
        ttsBackend = backend
    }

    func selectConversationTTS(_ backend: LocalTTSBackend) throws {
        guard backend != .kokoro else { throw LocalTTSError.busy }
        try selectTTS(backend)
        conversationTTSBackend = backend
        UserDefaults.standard.set(backend.rawValue, forKey: Self.conversationTTSPreferenceKey)
    }

    func prepareTTS(progress: @escaping @MainActor @Sendable (String) -> Void = { _ in }) async throws {
        guard canSelectTTS else { throw LocalTTSError.busy }
        let started = ProcessInfo.processInfo.systemUptime
        try await performSpeech { id in
            try self.ttsBackend.checkAvailable()
            if self.ttsBackend == .supertonic {
                try await self.neuralTTS.prepare(voice: self.supertonicVoice, setup: { [self] update in
                    guard speechAdmission.accepts(id) else { return }
                    preparationProgress = update
                }) { [self] message in
                    guard speechAdmission.accepts(id) else { return }
                    progress(message)
                }
            }
        }
        logger.notice("tts_prepared backend=\(self.ttsBackend.rawValue, privacy: .public) total_ms=\((ProcessInfo.processInfo.systemUptime - started) * 1_000, privacy: .public) policy=neural-before-asr-preparation")
    }

    private func speakNeural(_ text: String) async throws {
        try await performSpeech { id in
            try self.ttsBackend.checkAvailable()
            // A typed reply or Help may arrive before greeting prewarm has drained.
            if let warmup = self.stagedDecoderWarmup { try await warmup.value }
            try Task.checkCancellation()
            guard self.speechAdmission.accepts(id) else { throw CancellationError() }
            let speed = self.supertonicSpeed
            let rendered = try await self.neuralTTS.synthesize(text, speed: speed.value)
            self.lastSynthesis = TTSSynthesisMetrics(milliseconds: rendered.synthMilliseconds,
                audioMilliseconds: rendered.audio.duration * 1_000, first: rendered.first, clipping: rendered.audio.hasClipping)
            try Task.checkCancellation()
            guard self.speechAdmission.accepts(id) else { throw CancellationError() }
            self.voiceDescription = "Mural Voice · \(self.supertonicVoice.muralName) · \(speed.label)"
            self.logger.notice("tts_synthesized backend=supertonic3-ane-int4 voice=\(self.supertonicVoice.rawValue, privacy: .public) steps=8 speed=\(speed.value, privacy: .public) first=\(rendered.first, privacy: .public) synth_ms=\(rendered.synthMilliseconds, privacy: .public) audio_ms=\(rendered.audio.duration * 1_000, privacy: .public) clipping=\(rendered.audio.hasClipping, privacy: .public) prewarm=after-playback")
            try await self.playPCM(rendered.audio, id: id)
            #if canImport(CoreAI)
            self.startStagedDecoderPrewarmIfNeeded(schedule: "after-neural-playback")
            #endif
        }
    }

    func waitForTTSCleanup() async { await ttsCleanup?.value }

    func finishTTSComparison() async {
        stopSpeech()
        await ttsCleanup?.value
        ttsBackend = conversationTTSBackend
    }

    private func unloadTTSAfterDrain() {
        guard ttsCleanup == nil, neuralTTS.hasResources else { return }
        let worker = speechTask
        ttsCleanup = Task { [self] in
            // Upstream native predictions are not cooperative. Never overlap cleanup with them.
            _ = await worker?.result
            await neuralTTS.unload()
            VietnameseEnglishRecognizer.logMemory(stage: "tts-cleanup-returned", model: "supertonic3-ane-int4")
            ttsCleanup = nil
        }
    }

    private func playPCM(_ audio: LocalTTSAudio, id: UUID) async throws {
        try await activateAudio(category: .playback)
        defer { releaseAudio() }
        try Task.checkCancellation()
        guard speechAdmission.accepts(id) else { throw CancellationError() }
        try await pcmPlayback.play(audio) { [self] time in
            guard speechAdmission.accepts(id) else { return }
            beginPlayback(at: time)
        }
        guard speechAdmission.accepts(id) else { throw CancellationError() }
        finishPlayback(completed: true)
        logger.notice("tts_finished backend=pcm uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public)")
    }

    #if DEBUG && targetEnvironment(simulator)
    func startTTSConversationMonitorForTesting() { startTTSConversationMonitor() }
    #endif

    private func startTTSConversationMonitor(model: String = "supertonic3-ane-int4") {
        guard ttsConversationMonitor == nil else { return }
        ttsConversationMonitor = Task { [weak self] in
            var maximum: UInt64 = 0
            while !Task.isCancelled, let self {
                // task_info and unified logging are synchronous. Keep them off MainActor so
                // the conversation-wide Breeze safety monitor cannot hitch scrolling or animation.
                let sample: [String: UInt64]
                #if DEBUG && targetEnvironment(simulator)
                if let testTTSSafetySampler {
                    sample = await testTTSSafetySampler()
                } else {
                    sample = await Task.detached(priority: .utility) {
                        VietnameseEnglishRecognizer.logMemory(stage: "tts-talk-sampled-1s", model: model)
                    }.value
                }
                #else
                sample = await Task.detached(priority: .utility) {
                    VietnameseEnglishRecognizer.logMemory(stage: "tts-talk-sampled-1s", model: model)
                }.value
                #endif
                guard !Task.isCancelled else { return }
                maximum = max(maximum, sample["footprintBytes"] ?? 0)
                self.stopForTTSSafety(footprint: maximum, thermal: self.ttsThermalState)
                if Task.isCancelled { return }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    func playTestSignal(sampleRate: Double) async throws {
        try await performSpeech { id in
            try await self.playPCM(LocalTTSAudio.testSignal(sampleRate: sampleRate), id: id)
        }
    }
    var canRecord: Bool {
        if ttsBackend == .supertonic, !neuralTTS.isReady { return false }
        return fireRedDiagnosticAllowsRecord && (asr != nil || whisper != nil || parakeet != nil || breeze != nil || fireRed != nil) && asrTask == nil && !speechBusy
    }
    var canPrepare: Bool { asrTask == nil && fireRedDiagnosticAllowsPrepare && !speechBusy && asr == nil && whisper == nil && parakeet == nil && breeze == nil && fireRed == nil }
    private var fireRedDiagnosticAllowsPrepare: Bool {
        #if MURAL_FIRERED_FILE_PROBE
        if FireRedEnglishRecognizer.memoryDiagnostic { return asrModel == .fireRed && !fireRedDiagnosticStarted }
        #endif
        return true
    }
    private var fireRedDiagnosticAllowsRecord: Bool {
        #if MURAL_FIRERED_FILE_PROBE
        if FireRedEnglishRecognizer.memoryDiagnostic { return asrModel == .fireRed && fireRedDiagnosticTurns < 2 }
        #endif
        return true
    }
    #if MURAL_FIRERED_FILE_PROBE
    private var fireRedDiagnosticStarted = false
    private var fireRedDiagnosticTurns = 0
    private var fireRedDiagnosticTask: Task<Void, Never>?

    /// One approved residency observation, not a production memory policy.
    private func startFireRedMemoryDiagnostic() {
        guard FireRedEnglishRecognizer.memoryDiagnostic else { return }
        fireRedDiagnosticStarted = true
        FireRedEnglishRecognizer.diagnosticMemory("owner-baseline")
        let deadline = ProcessInfo.processInfo.systemUptime + 420
        fireRedDiagnosticTask = Task { [weak self] in
            defer { self?.fireRedDiagnosticTask = nil }
            while let self {
                let thermal = ProcessInfo.processInfo.thermalState
                let expired = ProcessInfo.processInfo.systemUptime >= deadline
                let finished = self.asrState == .ended || self.asrState == .failed
                if finished || expired || thermal.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                    let task = self.asrTask
                    let previousError = self.asrError
                    self.stop() // Cancellation drains native work through the existing owner.
                    if let previousError { self.asrError = previousError; self.asrState = .failed }
                    self.asrNotice = "Memory diagnostic stopped. Do not prepare again; report the result."
                    self.logger.notice("firered_diagnostic_stop expired=\(expired, privacy: .public) thermal_state=\(thermal.rawValue, privacy: .public)")
                    await task?.value
                    await self.audioRelease?.value
                    FireRedEnglishRecognizer.diagnosticMemory("owner-drained")
                    // These samples run after the actor and remaining Swift properties release.
                    for delay in [2, 8, 20] {
                        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                        FireRedEnglishRecognizer.diagnosticMemory("post-drain")
                    }
                    return
                }
                FireRedEnglishRecognizer.diagnosticMemory("residency-checkpoint")
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
    #endif
    @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol?
    private let synthesizer = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?
    private var completion: CheckedContinuation<Void, Error>?
    private var requestedAt = 0.0
    private var playbackStartedAt: Double?
    private let logger = Logger(subsystem: "no.william.mural", category: "LocalAudio")

    nonisolated static var retainsVADFixtures: Bool {
        #if MURAL_VAD_PROBE
        ProcessInfo.processInfo.arguments.contains { $0 == "--asr-vad-fixtures" || $0.hasPrefix("--asr-vad-fixtures=") }
        #else
        false
        #endif
    }

    nonisolated static var conversationASRBackend: String {
        #if canImport(CoreAI)
        if PhoWhisperStagedEncoder.enabled { return "Core AI GPU-preferred encoder + Core ML decoder (staged)" }
        #endif
        return "WhisperKit / Core ML (eager)"
    }

    override init() {
        super.init()
        logger.notice("local_talk_asr_backend backend=\(Self.conversationASRBackend, privacy: .public)")
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("UIApplicationDidReceiveMemoryWarningNotification"),
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let previousState = self.asrState.rawValue
                    self.stop()
                    VietnameseEnglishRecognizer.logMemory(stage: "memory-warning", model: self.asrModel.rawValue)
                    self.logger.warning("asr_memory_warning stopped=true uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public) previous_state=\(previousState, privacy: .public) decoder_prewarm_active=\(self.stagedDecoderWarmupActive, privacy: .public)")
                    self.onSafetyStop?(.memoryPressure)
                }
            }
    }

    isolated deinit {
        ttsConversationMonitor?.cancel()
        #if MURAL_FIRERED_FILE_PROBE
        fireRedDiagnosticTask?.cancel()
        #endif
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
    }

    /// Reserve before audio activation (the first await). Stop never reopens admission early.
    func performSpeech(_ operation: @escaping @MainActor (UUID) async throws -> Void) async throws {
        try Task.checkCancellation()
        guard asrTask == nil else { throw SpeechError.busy }
        guard !speechBusy else { throw LocalTTSError.busy }
        guard !thermalStopped else { throw LocalTTSError.phoneTooWarm }
        lastSynthesis = nil
        let id = try speechAdmission.begin()
        speechStopRequestedAt = nil; speechDrainMilliseconds = nil; speechStopMilliseconds = nil
        playbackStartSeconds = nil; playbackDurationSeconds = nil; playbackStartedAt = nil
        requestedAt = ProcessInfo.processInfo.systemUptime
        let task = Task { @MainActor in
            try Task.checkCancellation()
            guard self.speechAdmission.accepts(id) else { throw CancellationError() }
            try await operation(id)
            try Task.checkCancellation()
        }
        speechTask = task
        defer {
            if let stopped = speechStopRequestedAt {
                speechDrainMilliseconds = (ProcessInfo.processInfo.systemUptime - stopped) * 1_000
            }
            speechAdmission.finish(id)
            speechTask = nil
        }
        try await withTaskCancellationHandler {
            do { try await task.value }
            catch { stopSpeech(); throw error }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.speechAdmission.requestID == id else { return }
                self?.stopSpeech()
            }
        }
    }

    func speak(_ text: String) async throws {
        _ = try LocalTTSAudio.validatedText(text)
        if ttsBackend != .apple {
            do {
                try await speakNeural(text)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let failure = error as NSError
                logger.error("tts_fallback backend=supertonic reason=synthesis domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public)")
                await ttsCleanup?.value
                ttsBackend = .apple
            }
        }
        try await performSpeech { id in
            guard let voice = LocalSpeechVoice.resolvedVoice() else { throw SpeechError.noVoice }
            try await self.activateAudio(category: .playback)
            defer { self.releaseAudio() }
            try Task.checkCancellation()
            guard self.speechAdmission.accepts(id) else { throw CancellationError() }
            let current = AVSpeechUtterance(string: text)
            current.voice = voice
            self.voiceDescription = LocalSpeechVoice.description(for: voice)
            self.utterance = current
            try await withCheckedThrowingContinuation { continuation in
                self.completion = continuation
                #if canImport(CoreAI)
                self.startStagedDecoderPrewarmIfNeeded()
                #endif
                self.synthesizer.speak(current)
            }
        }
    }

    /// Playback cancellation is separate from ASR/session teardown.
    func stopSpeech() {
        let stoppingPlayback = playbackStartedAt != nil
        let stopTime = ProcessInfo.processInfo.systemUptime
        if speechAdmission.isBusy, speechStopRequestedAt == nil { speechStopRequestedAt = stopTime }
        speechAdmission.cancel()
        speechTask?.cancel()
        finishPlayback(completed: false)
        utterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        pcmPlayback.stop()
        unloadTTSAfterDrain()
        if stoppingPlayback { speechStopMilliseconds = (ProcessInfo.processInfo.systemUptime - stopTime) * 1_000 }
        let pending = completion; completion = nil
        pending?.resume(throwing: CancellationError())
        releaseAudio()
    }

    private func finishPlayback(completed: Bool, at time: Double = ProcessInfo.processInfo.systemUptime) {
        guard let start = playbackStartedAt else { return }
        playbackStartedAt = nil
        playbackDurationSeconds = time - start
        onPlayback?(start, time, completed)
    }

    func stop() {
        ttsConversationMonitor?.cancel(); ttsConversationMonitor = nil
        generation = UUID()
        limitTask?.cancel(); limitTask = nil
        stopCapture()
        capture?.finish(throwing: CancellationError()); capture = nil
        asrTask?.cancel()
        stagedDecoderWarmup?.cancel()
        #if MURAL_FIRERED_FILE_PROBE
        if asrModel == .fireRed {
            logger.notice("firered_stop_requested uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public) draining=\(self.asrTask != nil, privacy: .public)")
        }
        #endif
        logger.notice("asr_owner_release_requested model=\(self.asrModel.rawValue, privacy: .public) draining=\(self.asrTask != nil || self.stagedDecoderWarmupActive, privacy: .public) assets_retained=true")
        asr = nil; whisper = nil; parakeet = nil; breeze = nil; fireRed = nil
        asrState = .ended
        asrNotice = "Stopped. Downloaded models are kept for the next conversation."
        stopSpeech()
    }

    private func beginPlayback(at time: Double) {
        playbackStartedAt = time
        onPlayback?(time, nil, false)
        playbackStartSeconds = time - requestedAt
        sendToPlaybackSeconds = submittedAt.map { time - $0 }
        if let gap = sendToPlaybackSeconds {
            logger.notice("local_audio_started send_to_audio_seconds=\(gap, privacy: .public)")
            if trialFirstAudioGeneration != generation {
                trialFirstAudioGeneration = generation
                logger.notice("asr_trial_audio id=\(self.generation.uuidString, privacy: .public) uptime=\(time, privacy: .public) send_to_audio_seconds=\(gap, privacy: .public)")
            }
        }
        logger.notice("tts_started startup_seconds=\(time - self.requestedAt, privacy: .public) uptime=\(time, privacy: .public)")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let time = ProcessInfo.processInfo.systemUptime
        Task { @MainActor [weak self] in
            guard let self, self.utterance === utterance else { return }
            self.beginPlayback(at: time)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let time = ProcessInfo.processInfo.systemUptime
        Task { @MainActor [weak self] in
            guard let self, self.utterance === utterance else { return }
            self.finishPlayback(completed: true, at: time)
            self.logger.notice("tts_finished uptime=\(time, privacy: .public)")
            self.utterance = nil
            let pending = self.completion; self.completion = nil
            pending?.resume()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.utterance === utterance else { return }
            self.stopSpeech()
        }
    }

    #if canImport(CoreAI)
    private func startStagedDecoderPrewarmIfNeeded() {
        startStagedDecoderPrewarmIfNeeded(schedule: "with-greeting")
    }

    private func startStagedDecoderPrewarmIfNeeded(schedule: String) {
        guard PhoWhisperStagedEncoder.enabled, stagedDecoderWarmup == nil, let whisper else { return }
        logger.notice("asr_staged_decoder_schedule schedule=\(schedule, privacy: .public)")
        stagedDecoderWarmupActive = true
        stagedDecoderWarmup = Task { [weak self] in
            // Remain active until native loading returns, even after Stop requests cancellation.
            defer { self?.stagedDecoderWarmupActive = false }
            try await whisper.prewarmStagedDecoder()
        }
    }
    #endif

    private func activateAudio(category: AVAudioSession.Category) async throws {
        await audioRelease?.value
        try Task.checkCancellation()
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(category, mode: .default, options: category == .playAndRecord ? [.defaultToSpeaker] : [])
        guard try await audio.activate() else { throw CaptureError.audioSession }
        ownsAudio = true
        if Task.isCancelled { releaseAudio(); throw CancellationError() }
    }

    private func releaseAudio() {
        guard ownsAudio else { return }
        ownsAudio = false
        audioRelease = Task { _ = try? await AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation) }
    }

    var selectedConversationASRBackend: String {
        asrModel == .breeze ? "Breeze PAL8 · WhisperKit / Core ML" : Self.conversationASRBackend
    }

    func hasConversationAssets(for pair: LocalSpeechPair) throws -> Bool {
        let manager = FileManager.default
        if pair == .taiwanMandarinEnglish {
            guard try LocalSpeechProvisioning.hardware() == "iPhone18,3",
                  ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 else { throw SpeechPackageError.incompatible }
            let folder = try LocalSpeechProvisioning.installedDirectory(for: pair, component: "support") ??
                URL.applicationSupportDirectory.appending(path: "BreezeASR25/\(BreezeEnglishRecognizer.identity)")
            return manager.fileExists(atPath: folder.appending(path: "manifest.json").path)
        }
        if let folder = try LocalSpeechProvisioning.installedDirectory(for: pair, component: "support") {
            return manager.fileExists(atPath: folder.appending(path: "manifest.json").path)
        }
        #if canImport(CoreAI)
        if PhoWhisperStagedEncoder.enabled {
            // Only an existence preflight. Full verification and specialization still precede Ready.
            return manager.fileExists(atPath: URL.applicationSupportDirectory.appending(path:
                "PhoWhisperCS/phowhisper-cs-pal8-g16-v1/manifest.json").path) &&
                manager.fileExists(atPath: URL.documentsDirectory.appending(path:
                    "CoreAI/W8FullV3/packed/encoder-fp8/manifest.json").path)
        }
        #endif
        return manager.fileExists(atPath: URL.applicationSupportDirectory.appending(path:
            "PhoWhisperCS/phowhisper-cs-fp16-v1/manifest.json").path)
    }

    /// Await the existing single ASR owner, including its defer cleanup, before TTS.
    func prepareConversation(model: ASRModel = .phoWhisper) async throws {
        try Task.checkCancellation()
        guard model == .phoWhisper || model == .breeze else { throw SpeechError.busy }
        rawASRText = ""
        preparationProgress = .init(.checking)
        if let warmup = stagedDecoderWarmup {
            warmup.cancel()
            _ = await warmup.result
            stagedDecoderWarmup = nil
            try Task.checkCancellation()
        }
        await ttsCleanup?.value
        try Task.checkCancellation()
        guard canPrepare else { throw SpeechError.busy }
        selectASR(model)
        guard asrModel == model else { throw SpeechError.busy }
        logger.notice("local_talk_model_selected pair=\(model == .breeze ? "zh-TW-en" : "vi-en", privacy: .public) model=\(self.asrModel.rawValue, privacy: .public) backend=\(self.selectedConversationASRBackend, privacy: .public)")
        if model == .breeze {
            stopForTTSSafety(footprint: 0, thermal: ttsThermalState)
            try Task.checkCancellation()
            guard !thermalStopped else { throw LocalTTSError.phoneTooWarm }
            // The same 3 GB/thermal guard also applies when Breeze uses the Apple voice.
            startTTSConversationMonitor(model: BreezeEnglishRecognizer.identity)
        }
        submittedAt = nil; sendToPlaybackSeconds = nil
        await ttsCleanup?.value
        try Task.checkCancellation()
        ttsBackend = conversationTTSBackend
        if ttsBackend == .supertonic {
            stopForTTSSafety(footprint: 0, thermal: ttsThermalState)
            guard !thermalStopped else { throw LocalTTSError.phoneTooWarm }
            startTTSConversationMonitor()
            do {
                try await prepareTTS()
                try Task.checkCancellation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation() // A cancelled SDK error is not permission to start a fallback.
                let failure = error as NSError
                logger.error("tts_fallback backend=supertonic reason=preparation domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public)")
                if model != .breeze { ttsConversationMonitor?.cancel(); ttsConversationMonitor = nil }
                await ttsCleanup?.value
                ttsBackend = .apple
            }
        }
        try Task.checkCancellation()
        prepareASR()
        await asrTask?.value
        try Task.checkCancellation()
        guard canRecord, asrState == .ready else {
            throw CaptureError.operation(asrError ?? "Speech preparation did not finish. Start again.")
        }
    }

    func recordConversationTurn() async throws -> String {
        try Task.checkCancellation()
        guard canRecord else { throw SpeechError.busy }
        record()
        await asrTask?.value
        try Task.checkCancellation()
        guard asrState == .ready else {
            throw CaptureError.operation(asrError ?? "Recording did not finish. Try Record again.")
        }
        return asrText
    }

    func clearSubmissionTiming() {
        submittedAt = nil; sendToPlaybackSeconds = nil
    }

    func selectASR(_ model: ASRModel) {
        guard !asrBusy, !speechBusy, !modelWorkDraining, model != asrModel else { return }
        stop() // Release weights, never delete either model's cached assets.
        asrModel = model; asrState = .idle
        asrText = ""; asrError = nil; asrNotice = nil
        preparationDetail = ""
        preparationSeconds = nil; finalizeSeconds = nil; capturedSeconds = 0
        inputDescription = "Microphone off"
    }

    func prepareASR(repairDownload: Bool = false) {
        guard canPrepare else { return }
        #if MURAL_FIRERED_FILE_PROBE
        startFireRedMemoryDiagnostic()
        #endif
        lastRecordingHadNoSpeech = false
        let previousWarmup = stagedDecoderWarmup
        previousWarmup?.cancel()
        let token = UUID(); generation = token
        let selected = asrModel
        asrError = nil; asrNotice = nil; preparationSeconds = nil; preparationDetail = ""; asrState = .downloading
        preparationProgress = .init(.checkingSpeech)
        let repairDirectory = repairDownload ? variantDirectory : nil
        asrTask = Task { [weak self] in
            guard let self else { return }
            defer { self.asrTask = nil }
            do {
                if let previousWarmup {
                    _ = await previousWarmup.result
                    self.stagedDecoderWarmup = nil
                }
                try Task.checkCancellation()
                let started = ProcessInfo.processInfo.systemUptime
                #if MURAL_VAD_PROBE
                if selected == .vadOnly {
                    let fixtureDirectory = try Self.vadFixtureDirectory()
                    self.asrState = .warming
                    let recognizer = WhisperRecognizer(phoWhisper: true)
                    try await recognizer.prepareVADOnly()
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    self.whisper = recognizer
                    self.preparationSeconds = ProcessInfo.processInfo.systemUptime - started
                    self.preparationDetail = fixtureDirectory == nil
                        ? "Silero only. No ASR weights, tutor, TTS or audio retention."
                        : "Silero only. ASR, tutor and TTS off. Explicit private fixture retention: up to 8 submitted recordings."
                    self.asrState = .ready
                    return
                }
                #endif
                let directory: URL
                switch selected {
                #if MURAL_VAD_PROBE
                case .vadOnly: throw SpeechError.busy // Handled above; never resolve ASR assets.
                #endif
                #if MURAL_FIRERED_FILE_PROBE
                case .fireRed:
                    directory = try await FireRedEnglishRecognizer.localDirectory()
                #endif
                case .breeze:
                    directory = try await BreezeEnglishRecognizer.localDirectory()
                case .phoWhisper:
                    VietnameseEnglishRecognizer.logMemory(stage: "asset-verification-begin", model: "phowhisper-support-pending-verification")
                    directory = try await WhisperRecognizer.localPhoWhisperDirectory()
                    VietnameseEnglishRecognizer.logMemory(stage: "asset-verification-end", model: directory.lastPathComponent)
                case .parakeet:
                    directory = try await VietnameseEnglishRecognizer.download(repair: repairDownload)
                case .whisper:
                    directory = try await WhisperRecognizer.download(repair: repairDownload)
                case .nemotron:
                    if let repairDirectory {
                        // Reconcile only this variant; preserve cached weights and learning data.
                        try await ModelHub.download(.nemotronMultilingual, subdirectory: "multilingual/1120ms",
                            to: repairDirectory.deletingLastPathComponent().deletingLastPathComponent(),
                            shouldSkip: { $0.contains(".mlpackage") })
                    }
                    directory = try await StreamingNemotronMultilingualAsrManager.downloadVariant(languageCode: "auto", chunkMs: 1120)
                }
                try Task.checkCancellation()
                guard self.generation == token else { return }
                let assetsSeconds = ProcessInfo.processInfo.systemUptime - started
                self.preparationDetail = String(format: selected == .phoWhisper ? "Local asset verification: %.2f s" : "Asset/model preparation: %.2f s", assetsSeconds)
                self.logger.notice("asr_assets_ready model=\(selected.rawValue, privacy: .public) seconds=\(assetsSeconds, privacy: .public)")
                self.asrState = .warming
                self.preparationProgress = .init(.preparingSpeech)
                let loadingStarted = ProcessInfo.processInfo.systemUptime
                switch selected {
                #if MURAL_VAD_PROBE
                case .vadOnly: throw SpeechError.busy
                #endif
                #if MURAL_FIRERED_FILE_PROBE
                case .fireRed:
                    let recognizer = FireRedEnglishRecognizer()
                    try await recognizer.prepare(directory: directory)
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    self.fireRed = recognizer
                    self.preparationDetail += " · FireRedASR2-AED INT8 · CPU, one thread · no fallback."
                #endif
                case .breeze:
                    let recognizer = BreezeEnglishRecognizer()
                    try await recognizer.prepare(directory: directory)
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    self.breeze = recognizer
                    self.preparationDetail += " · Local PAL8 Breeze probe; no hosted fallback."
                case .parakeet:
                    let recognizer = VietnameseEnglishRecognizer()
                    try await recognizer.prepare(directory: directory)
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    self.parakeet = recognizer
                case .whisper, .phoWhisper:
                    let recognizer = WhisperRecognizer(phoWhisper: selected == .phoWhisper)
                    let timing = try await recognizer.prepare(directory: directory) { [weak self] message in
                        guard let self, self.generation == token else { return }
                        self.preparationDetail = message
                    }
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    self.whisper = recognizer
                    #if canImport(CoreAI)
                    if selected == .phoWhisper, PhoWhisperStagedEncoder.enabled {
                        self.preparationDetail += " · Core AI FP8 encoder / Core ML PAL8 decoder; verified before Ready; decoder released after each turn."
                    } else {
                        self.preparationDetail += String(format: " · Prewarm: %.2f s · Load/tokenizer: %.2f s", timing.prewarm, timing.load)
                    }
                    #else
                    self.preparationDetail += String(format: " · Prewarm: %.2f s · Load/tokenizer: %.2f s", timing.prewarm, timing.load)
                    #endif
                case .nemotron:
                    self.variantDirectory = directory
                    let manager = StreamingNemotronMultilingualAsrManager()
                    try await manager.loadModels(from: directory)
                    await manager.setLanguage("auto")
                    let config = await manager.config
                    let prompt = await manager.promptId()
                    let forcedPrefix = await manager.forcedPrefixEnabled()
                    self.logger.notice("asr_configuration chunk_ms=\(config.chunkMs, privacy: .public) vocabulary=\(config.vocabSize, privacy: .public) sample_rate=\(config.sampleRate, privacy: .public) prompt=\(prompt, privacy: .public) forced_prefix=\(forcedPrefix, privacy: .public)")
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    self.asr = manager
                }
                let loadSeconds = ProcessInfo.processInfo.systemUptime - loadingStarted
                if selected != .whisper && selected != .phoWhisper { self.preparationDetail += String(format: " · Load: %.2f s", loadSeconds) }
                self.asrState = .ready
                self.preparationSeconds = ProcessInfo.processInfo.systemUptime - started
                self.logger.notice("asr_ready model=\(selected.rawValue, privacy: .public) preparation_seconds=\(self.preparationSeconds!, privacy: .public) load_seconds=\(loadSeconds, privacy: .public)")
            } catch {
                guard self.generation == token, !Task.isCancelled else { return }
                self.asrError = selected == .phoWhisper
                    ? "PhoWhisper speech preparation failed. Try Prepare & start again or check available iPhone storage. No backend was changed. (\(error.localizedDescription))"
                    : "Speech models could not be prepared. Connect to Wi-Fi and try Prepare again. If cached assets are incomplete, use Repair download. (\(error.localizedDescription))"
                if selected == .breeze { self.asrError = "Breeze speech preparation failed. Try Prepare & start again or check available iPhone storage. No cloud fallback was used. (\(error.localizedDescription))" }
                #if MURAL_FIRERED_FILE_PROBE
                if selected == .fireRed { self.asrError = "FireRed v2 AED preparation failed. Stop and report this error; no download or fallback. (\(error.localizedDescription))" }
                #endif
                self.asrState = .failed
                self.logger.error("asr_preparation_failed model=\(selected.rawValue, privacy: .public)")
            }
        }
    }

    func record() {
        guard canRecord else { return }
        #if MURAL_FIRERED_FILE_PROBE
        if FireRedEnglishRecognizer.memoryDiagnostic { fireRedDiagnosticTurns += 1 }
        #endif
        let manager = asr, whisper = whisper, parakeet = parakeet, breeze = breeze, fireRed = fireRed
        let decoderWarmup = stagedDecoderWarmup
        let limit = recordingLimitSeconds
        let model = asrModel.rawValue
        let token = UUID(); generation = token
        rawASRText = ""
        asrText = ""; asrError = nil; asrNotice = nil; finalizeSeconds = nil; submittedAt = nil; capturedSeconds = 0
        lastRecordingHadNoSpeech = false
        sendToPlaybackSeconds = nil
        asrState = .warming
        asrTask = Task { [weak self] in
            guard let self else { return }
            defer { self.asrTask = nil }
            do {
                guard await AVAudioApplication.requestRecordPermission() else { throw CaptureError.microphone }
                try Task.checkCancellation()
                try await self.activateAudio(category: .playAndRecord)
                try Task.checkCancellation()
                guard self.generation == token else { return }
                // Reset and all following process/finish/reset calls have one ordered owner.
                await manager?.reset()
                try Task.checkCancellation()
                let engine = AVAudioEngine()
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
                      format.sampleRate > 0, format.sampleRate <= 96_000, (1...2).contains(format.channelCount) else { throw CaptureError.format }
                let (stream, continuation) = AsyncThrowingStream<AVReadOnlyAudioPCMBuffer, Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
                self.capture = continuation; self.audioEngine = engine
                try input.installAudioTap(onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate * 0.1), format: format) { buffer, _ in
                    // iOS 27 gives us owned, read-only Sendable PCM. No conversion or inference
                    // on this callback. Overflow fails loudly instead of silently losing words.
                    if case .dropped = continuation.yield(buffer) {
                        continuation.finish(throwing: CaptureError.overloaded)
                    }
                }
                self.tapInstalled = true
                engine.prepare(); try engine.start()
                self.inputDescription = "\(Int(format.sampleRate)) Hz · \(format.channelCount) channel(s) → 16000 Hz mono"
                self.asrState = .recording
                self.logger.notice("capture_started model=\(model, privacy: .public) input_hz=\(format.sampleRate, privacy: .public)")
                self.logger.notice("asr_trial_capture id=\(token.uuidString, privacy: .public) uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public)")
                self.limitTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(limit)) } catch { return }
                    guard let self, self.generation == token, self.asrState == .recording else { return }
                    self.asrNotice = "\(limit)-second limit reached. Your turn was sent automatically."
                    self.finishRecording()
                }
                let result = try await Self.transcribe(stream, manager: manager, whisper: whisper,
                    decoderWarmup: decoderWarmup, parakeet: parakeet, breeze: breeze, fireRed: fireRed, limitSeconds: limit, turnID: token,
                    sampleRate: format.sampleRate, channelCount: format.channelCount) { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.asrNotice = "\(limit)-second limit reached. Your turn was sent automatically."
                    self.finishRecording()
                }
                await manager?.reset()
                try Task.checkCancellation()
                guard self.generation == token else { return }
                self.stopCapture(); self.capture = nil
                self.releaseAudio()
                self.rawASRText = result.text
                self.asrText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.lastRecordingHadNoSpeech = self.asrText.isEmpty
                self.capturedSeconds = result.seconds
                self.finalizeSeconds = self.submittedAt.map { ProcessInfo.processInfo.systemUptime - $0 } ?? result.finalizeSeconds
                self.logger.notice("asr_trial_final id=\(token.uuidString, privacy: .public) uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public) send_to_final_seconds=\(self.finalizeSeconds!, privacy: .public) captured_seconds=\(self.capturedSeconds, privacy: .public)")
                if let notice = result.notice { self.asrNotice = notice }
                else if self.asrText.isEmpty { self.asrNotice = "No speech recognized. Try another recording." }
                self.asrState = .ready
                self.logger.notice("asr_final model=\(model, privacy: .public) captured_seconds=\(result.seconds, privacy: .public) finish_seconds=\(result.finalizeSeconds, privacy: .public) send_to_final_seconds=\(self.finalizeSeconds!, privacy: .public) characters=\(self.asrText.count, privacy: .public)")
            } catch {
                self.stopCapture(); self.capture?.finish(); self.capture = nil
                await manager?.reset()
                self.releaseAudio()
                guard self.generation == token, !Task.isCancelled else { return }
                self.asrError = error.localizedDescription; self.asrState = .failed
                self.logger.error("asr_turn_failed")
                self.logger.error("asr_trial_failure id=\(token.uuidString, privacy: .public) uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public)")
            }
        }
    }

    func finishRecording() {
        guard asrState == .recording else { return }
        asrState = .transcribing
        submittedAt = ProcessInfo.processInfo.systemUptime
        stopCapture()
        capture?.finish() // Drain every accepted packet before finish/reset.
        logger.notice("asr_send")
        logger.notice("asr_trial_send id=\(self.generation.uuidString, privacy: .public) uptime=\(self.submittedAt!, privacy: .public)")
    }

    private func stopCapture() {
        limitTask?.cancel(); limitTask = nil
        if let engine = audioEngine {
            engine.stop()
            if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
            audioEngine = nil
        }
    }

    private struct Recognition: Sendable {
        let text: String
        let seconds: Double
        let finalizeSeconds: Double
        var notice: String? = nil
    }

    @concurrent private static func transcribe(_ stream: AsyncThrowingStream<AVReadOnlyAudioPCMBuffer, Error>,
        manager: StreamingNemotronMultilingualAsrManager?, whisper: WhisperRecognizer?,
        decoderWarmup: Task<Void, Error>?, parakeet: VietnameseEnglishRecognizer?, breeze: BreezeEnglishRecognizer?, fireRed: FireRedEnglishRecognizer?, limitSeconds: Int, turnID: UUID,
        sampleRate: Double, channelCount: AVAudioChannelCount,
        onLimit: @MainActor @Sendable () -> Void) async throws -> Recognition {
        guard let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channelCount, interleaved: false),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target) else { throw CaptureError.format }
        var frames = 0
        var convertedFrames = 0
        var turnSamples: [Float] = [] // Whisper decodes after Send; at most the selected turn limit in RAM.
        for try await packet in stream {
            try Task.checkCancellation()
            // Bound audio length as well as the wall-clock recording timer.
            let count = min(Int(packet.frameLength), max(0, Int(sampleRate * Double(limitSeconds)) - frames))
            guard count > 0 else { continue }
            guard packet.format.channelCount == channelCount, packet.format.sampleRate == sampleRate,
                  let pcm = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(count)),
                  let data = pcm.floatChannelData else { throw CaptureError.format }
            pcm.frameLength = AVAudioFrameCount(count)
            for channel in 0..<Int(channelCount) {
                guard case .float(let samples) = packet.channelData(channel) else { throw CaptureError.format }
                for index in 0..<count { data[channel][index] = samples[index] }
            }
            frames += count
            if frames == Int(sampleRate * Double(limitSeconds)) { await onLimit() }
            let capacity = AVAudioFrameCount(ceil(Double(count) * 16_000 / sampleRate) + 64)
            let samples = try convert(converter, input: pcm, target: target, capacity: capacity)
            convertedFrames += samples.count
            if let manager { _ = try await manager.process(samples: samples) }
            else { turnSamples.append(contentsOf: samples) }
        }
        try Task.checkCancellation()
        // Flush the resampler's trailing frames before finalizing the recognizer.
        let tail = try convert(converter, input: nil, target: target, capacity: 4096)
        let logger = Logger(subsystem: "no.william.mural", category: "LocalAudio")
        logger.notice("asr_input source_frames=\(frames, privacy: .public) source_hz=\(sampleRate, privacy: .public) converted_frames=\(convertedFrames + tail.count, privacy: .public)")
        #if MURAL_VAD_PROBE
        logger.notice("asr_vad_capture id=\(turnID.uuidString, privacy: .public) source_frames=\(frames, privacy: .public) source_hz=\(sampleRate, privacy: .public) channels=\(channelCount, privacy: .public) converted_body_samples=\(convertedFrames, privacy: .public) converter_tail_samples=\(tail.count, privacy: .public) converted_samples=\(convertedFrames + tail.count, privacy: .public)")
        #endif
        let started = ProcessInfo.processInfo.systemUptime
        let text: String
        if let manager {
            if !tail.isEmpty { _ = try await manager.process(samples: tail) }
            text = try await manager.finish()
            // Read before reset clears the library's blank-span counters.
            let stats = await manager.lastDecodeStats()
            let blankSpans = await manager.detectedBlankSpanCount
            let rescues = await manager.blankRescueCount
            logger.notice("asr_decode model=nemotron chunks=\(stats.processedChunks, privacy: .public) tokens=\(stats.tokenCount, privacy: .public) first_language=\(stats.detectedLanguage ?? "none", privacy: .public) blank_spans=\(blankSpans, privacy: .public) rescued_spans=\(rescues, privacy: .public)")
        } else if let fireRed {
            turnSamples.append(contentsOf: tail)
            text = try await fireRed.transcribe(turnSamples)
        } else if let breeze {
            turnSamples.append(contentsOf: tail)
            text = try await breeze.transcribe(turnSamples)
        } else if let parakeet {
            turnSamples.append(contentsOf: tail)
            text = try await parakeet.transcribe(turnSamples)
        } else if let whisper {
            turnSamples.append(contentsOf: tail)
            let analysis = try await whisper.analyzeSpeech(turnSamples, turnID: turnID)
            try Task.checkCancellation()
            let removed = turnSamples.count - analysis.samples.count
            let trimmed = !analysis.rejected && removed > 0
            logger.notice("asr_vad_audio id=\(turnID.uuidString, privacy: .public) original_samples=\(turnSamples.count, privacy: .public) original_seconds=\(Double(turnSamples.count) / 16000, privacy: .public) retained_samples=\(analysis.samples.count, privacy: .public) retained_seconds=\(Double(analysis.samples.count) / 16000, privacy: .public) removed_samples=\(removed, privacy: .public) removed_seconds=\(Double(removed) / 16000, privacy: .public) regions=\(analysis.regions.count, privacy: .public) pre_roll_samples=\(SpeechPresencePolicy.preRollSamples, privacy: .public) hangover_samples=\(SpeechPresencePolicy.hangoverSamples, privacy: .public) minimum_removed_samples=\(SpeechPresencePolicy.minimumRemovedSamples, privacy: .public) trimming_applied=\(trimmed, privacy: .public) failed_open=\(analysis.failedOpen, privacy: .public) rejected=\(analysis.rejected, privacy: .public)")
            for (index, region) in analysis.regions.enumerated() {
                logger.notice("asr_vad_region id=\(turnID.uuidString, privacy: .public) index=\(index, privacy: .public) start_sample=\(region.lowerBound, privacy: .public) end_sample_exclusive=\(region.upperBound, privacy: .public) start_seconds=\(Double(region.lowerBound) / 16000, privacy: .public) end_seconds_exclusive=\(Double(region.upperBound) / 16000, privacy: .public)")
            }
            #if MURAL_VAD_PROBE
            if await whisper.vadOnly {
                try Task.checkCancellation()
                guard !analysis.failedOpen else {
                    throw CaptureError.operation("VAD evidence unavailable. No gate decision or ASR result.")
                }
                var retained = ""
                if let directory = try vadFixtureDirectory() {
                    let digest = try writeVADFixture(turnSamples, turnID: turnID, directory: directory)
                    logger.notice("asr_vad_fixture id=\(turnID.uuidString, privacy: .public) session=\(directory.lastPathComponent, privacy: .public) samples=\(turnSamples.count, privacy: .public) pcm_sha256=\(digest, privacy: .public)")
                    retained = " Private audio fixture saved."
                }
                try Task.checkCancellation()
                return Recognition(text: "", seconds: Double(frames) / sampleRate,
                    finalizeSeconds: ProcessInfo.processInfo.systemUptime - started,
                    notice: (analysis.rejected ? "Gate would reject. No ASR ran." : "Gate would accept. No ASR ran.") + retained)
            }
            #endif
            if !analysis.rejected {
                if let decoderWarmup {
                    let waitStarted = ProcessInfo.processInfo.systemUptime
                    logger.notice("asr_staged_decoder_wait_begin")
                    do {
                        try await decoderWarmup.value
                    } catch {
                        logger.error("asr_staged_decoder_wait_failed")
                        throw error
                    }
                    try Task.checkCancellation()
                    logger.notice("asr_staged_decoder_wait_complete wait_seconds=\(ProcessInfo.processInfo.systemUptime - waitStarted, privacy: .public)")
                }
                text = try await whisper.transcribe(analysis.samples)
            } else {
                // The owned greeting prewarm may continue; later speech awaits it and Stop cancels it.
                text = ""
            }
        } else { throw SpeechError.busy }
        let finalizeSeconds = ProcessInfo.processInfo.systemUptime - started
        try Task.checkCancellation()
        return Recognition(text: text, seconds: Double(frames) / sampleRate, finalizeSeconds: finalizeSeconds)
    }

    #if MURAL_VAD_PROBE
    private nonisolated static func vadFixtureDirectory() throws -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        let prefix = "--asr-vad-fixtures="
        let flags = arguments.filter { $0 == "--asr-vad-fixtures" || $0.hasPrefix(prefix) }
        guard !flags.isEmpty else { return nil }
        guard arguments.contains("--asr-vad-only"), flags.count == 1, flags[0].hasPrefix(prefix),
              let session = UUID(uuidString: String(flags[0].dropFirst(prefix.count))) else {
            throw CaptureError.operation("Private fixtures require VAD-only and exactly one --asr-vad-fixtures=<UUID> argument.")
        }
        return URL.documentsDirectory.appending(path: "VADQualification/\(session.uuidString)")
    }

    private nonisolated static func writeVADFixture(_ samples: [Float], turnID: UUID, directory: URL) throws -> String {
        try Task.checkCancellation()
        guard (1...480_000).contains(samples.count), samples.allSatisfy(\.isFinite),
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let output = buffer.floatChannelData?[0] else { throw CaptureError.format }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard files.filter({ $0.pathExtension == "wav" }).count < 8 else {
            throw CaptureError.operation("This private fixture session is limited to 8 submitted recordings.")
        }
        let file = directory.appending(path: "\(turnID.uuidString).wav")
        let temporary = directory.appending(path: "\(turnID.uuidString).partial.wav")
        guard !manager.fileExists(atPath: file.path), !manager.fileExists(atPath: temporary.path) else {
            throw CaptureError.operation("The private fixture already exists; it will not be overwritten.")
        }
        defer { try? manager.removeItem(at: temporary) } // Only this call's new, incomplete file.
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { output.update(from: $0.baseAddress!, count: samples.count) }
        try Task.checkCancellation()
        do {
            let audio = try AVAudioFile(forWriting: temporary, settings: format.settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            try audio.write(from: buffer)
        }
        try Task.checkCancellation()
        try manager.moveItem(at: temporary, to: file)
        let pcm = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        return SHA256.hash(data: pcm).map { String(format: "%02x", $0) }.joined()
    }
    #endif

    private nonisolated static func convert(_ converter: AVAudioConverter, input: AVAudioPCMBuffer?,
        target: AVAudioFormat, capacity: AVAudioFrameCount) throws -> [Float] {
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw CaptureError.format }
        var supplied = false
        var samples: [Float] = []
        while true {
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                if let input, !supplied { supplied = true; state.pointee = .haveData; return input }
                state.pointee = input == nil ? .endOfStream : .noDataNow
                return nil
            }
            if let error { throw error }
            guard status != .error, let data = output.floatChannelData else { throw CaptureError.format }
            samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
            switch status {
            case .inputRanDry, .endOfStream: return samples
            case .haveData:
                // Buffered output can fill capacity BEFORE this packet is requested.
                // Keep the input alive and drain until it is consumed, including at Send.
                guard output.frameLength > 0 else { throw CaptureError.format }
            default: throw CaptureError.format
            }
        }
    }

    #if (DEBUG || MURAL_COREAI_W8) && canImport(CoreAI)
    /// Private, bounded phone qualification through the actual Talk recognizer.
    /// Called only by the existing in-memory probe; never captures or edits recordings.
    @concurrent static func replayVADRecordings(directory: URL, reportURL: URL) async throws {
        struct Row: Codable {
            let file: String
            let turnID: UUID
            let pcmSHA256: String
            let originalSamples: Int
            let retainedSamples: Int
            let regions: [[Int]]
            let rejected: Bool
            let originalText: String
            let retainedText: String
        }
        let selection = try PhoWhisperStagedEncoder.resolveSelection()
        guard selection.v3?.format == "fp8", selection.supportIdentity == "phowhisper-cs-pal8-g16-v1",
              try !DecoderTrialPolicy.once(ProcessInfo.processInfo.arguments),
              try SpeechPresencePolicy.Mode(arguments: ProcessInfo.processInfo.arguments) == .gate else {
            throw CaptureError.operation("VAD replay requires retained FP8/PAL8, prewarm always and VAD gate.")
        }
        let recognizer = WhisperRecognizer(phoWhisper: true)
        _ = try await recognizer.prepare(directory: WhisperRecognizer.localPhoWhisperDirectory())
        var rows: [Row] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for index in 1...22 {
            try Task.checkCancellation()
            let file = directory.appending(path: String(format: "%03d.wav", index))
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: file.path)
            let turnID = UUID()
            let analysis = try await recognizer.analyzeSpeech(samples, turnID: turnID)
            guard !analysis.failedOpen else { throw CaptureError.operation("VAD replay has no complete evidence.") }
            let originalText = try await recognizer.transcribe(samples)
            try Task.checkCancellation()
            // Byte-identical inputs need no duplicate inference. Changed inputs use the same decoder.
            let retainedText: String
            if analysis.rejected { retainedText = "" }
            else if analysis.samples == samples { retainedText = originalText }
            else { retainedText = try await recognizer.transcribe(analysis.samples) }
            try Task.checkCancellation()
            rows.append(Row(file: file.lastPathComponent, turnID: turnID,
                pcmSHA256: samples.withUnsafeBufferPointer { PhoWhisperStagedEncoder.sha256(Data(buffer: $0)) },
                originalSamples: samples.count, retainedSamples: analysis.samples.count,
                regions: analysis.regions.map { [$0.lowerBound, $0.upperBound] }, rejected: analysis.rejected,
                originalText: originalText, retainedText: retainedText))
            // Private transcripts stay in this unique development run, never in unified logs or the store.
            try encoder.encode(rows).write(to: reportURL, options: .atomic)
            Logger(subsystem: "no.william.mural", category: "LocalAudio")
                .notice("asr_vad_replay completed=\(index, privacy: .public) original_samples=\(samples.count, privacy: .public) retained_samples=\(analysis.samples.count, privacy: .public) rejected=\(analysis.rejected, privacy: .public)")
        }
    }
    #endif

    /// One ordered task owns this actor. Stop drops ownership but never unloads a
    /// decoder during inference; the task retains it until cancellation completes.
    private actor WhisperRecognizer {
        private static let variant = "openai_whisper-large-v3-v20240930_626MB"
        private static let revision = "0f63a7800b00dd0226abd051b906c246e1907482"
        private var kit: WhisperKit?
        private let phoWhisper: Bool
        private var suppressedTokens: [Int] = []
        private var inferenceCount = 0
        private var vad: VadManager?
        private var vadMode: SpeechPresencePolicy.Mode = .off
        #if canImport(CoreAI)
        private static let stagedDecoderCompute: MLComputeUnits = .cpuAndNeuralEngine
        private var stagedDirectory: URL?
        private var stagedSelection: PhoWhisperStagedEncoder.Selection?
        private var stagedTokenizer: (any WhisperTokenizer)?
        private var stagedDecoderPrewarmedAt: URL? // Only successful prewarm, not a retained model.
        private var stagedPreparation: CoreMLPreparationReceipt?
        private var usesStagedEncoder: Bool { phoWhisper && PhoWhisperStagedEncoder.enabled }

        /// Normal Talk reuses durable preparation; explicit qualification keeps its old policy.
        private static func preparationMode(_ arguments: [String]) throws -> CoreMLPreparationReceipt.Mode {
            let once = try DecoderTrialPolicy.once(arguments) // Keep all existing flag validation.
            let trial = arguments.contains {
                $0.hasPrefix("--coreai-w8-v3-") || $0.hasPrefix("--coreai-product-") ||
                $0.hasPrefix("--coreai-compressed-encoder=")
            }
            return trial ? (once ? .sessionOnly : .always) : .automatic
        }
        #endif

        init(phoWhisper: Bool = false) { self.phoWhisper = phoWhisper }

        #if MURAL_VAD_PROBE
        private(set) var vadOnly = false

        func prepareVADOnly() async throws {
            vadOnly = true
            try Task.checkCancellation()
            vadMode = try SpeechPresencePolicy.Mode(arguments: ProcessInfo.processInfo.arguments)
            guard vadMode == .gate else {
                throw CaptureError.operation("VAD-only qualification requires the unchanged gate mode.")
            }
            // Load the existing cache directly: no recovery deletion or repair download.
            let url = URL.applicationSupportDirectory.appending(path:
                "FluidAudio/Models/\(Repo.vad.folderName)/\(ModelNames.VAD.sileroVadFile)")
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            VietnameseEnglishRecognizer.logMemory(stage: "vad-only-load-begin", model: ModelNames.VAD.sileroVadFile)
            let model = try MLModel(contentsOf: url, configuration: configuration)
            try Task.checkCancellation()
            vad = VadManager(config: VadConfig(defaultThreshold: SpeechPresencePolicy.threshold,
                computeUnits: .cpuAndNeuralEngine), vadModel: model)
            VietnameseEnglishRecognizer.logMemory(stage: "vad-only-loaded", model: ModelNames.VAD.sileroVadFile)
        }
        #endif

        private struct LocalManifest: Decodable {
            struct File: Decodable { let bytes: Int; let sha256: String }
            let files: [String: File]
        }

        @concurrent static func localPhoWhisperDirectory() async throws -> URL {
            let started = ProcessInfo.processInfo.systemUptime
            let logger = Logger(subsystem: "no.william.mural", category: "LocalAudio")
            var verified = false
            logger.notice("phowhisper_asset_verification_begin")
            defer {
                logger.notice("phowhisper_asset_verification_end success=\(verified, privacy: .public) seconds=\(ProcessInfo.processInfo.systemUptime - started, privacy: .public)")
            }
            var identity = "phowhisper-cs-fp16-v1"
            var manifestHash = "7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52"
            var selectedSupport: URL?
            #if canImport(CoreAI)
            if PhoWhisperStagedEncoder.enabled {
                let selection = try PhoWhisperStagedEncoder.resolveSelection()
                identity = selection.supportIdentity
                manifestHash = selection.supportManifest
                selectedSupport = selection.supportURL
            }
            #endif
            var folder = selectedSupport ?? URL.applicationSupportDirectory.appending(path: "PhoWhisperCS/\(identity)", directoryHint: .isDirectory)
            let manifest = try Data(contentsOf: folder.appending(path: "manifest.json"))
            guard SHA256.hash(data: manifest).map({ String(format: "%02x", $0) }).joined() == manifestHash else { throw CocoaError(.fileReadCorruptFile) }
            let files = try JSONDecoder().decode(LocalManifest.self, from: manifest).files
            // Verify the fixed local transfer before loading, off the audio/main threads.
            for (path, expected) in files {
                let handle = try FileHandle(forReadingFrom: folder.appending(path: path))
                defer { try? handle.close() }
                var hash = SHA256(), bytes = 0
                // Foundation read buffers must drain per chunk, not after the multi-GB scan.
                while try autoreleasepool(invoking: { () throws -> Bool in
                    try Task.checkCancellation()
                    guard let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty else { return false }
                    hash.update(data: chunk); bytes += chunk.count
                    return true
                }) {}
                guard bytes == expected.bytes,
                      hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected.sha256
                else { throw CocoaError(.fileReadCorruptFile) }
            }
            var resources = URLResourceValues(); resources.isExcludedFromBackup = true
            try folder.setResourceValues(resources)
            try Task.checkCancellation()
            verified = true
            return folder
        }

        static func download(repair: Bool) async throws -> URL {
            var base = URL.applicationSupportDirectory.appending(path: "WhisperKit", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            var resources = URLResourceValues(); resources.isExcludedFromBackup = true
            try base.setResourceValues(resources)
            let hub = HubApiWrapper(downloadBase: base)
            let repo = HubApiWrapper.Repo(id: "argmaxinc/whisperkit-coreml")
            let folder = hub.localRepoLocation(repo).appending(path: variant, directoryHint: .isDirectory)
            let complete = ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy { model in
                ["coremldata.bin", "metadata.json", "model.mil", "weights/weight.bin"].allSatisfy { file in
                    FileManager.default.fileExists(atPath: folder.appending(path: "\(model).mlmodelc/\(file)").path)
                }
            }
            if repair || !complete {
                _ = try await hub.snapshot(from: repo, revision: revision, matching: ["\(variant)/*"])
            }
            return folder
        }

        func prepare(directory: URL, progress: @escaping @MainActor @Sendable (String) -> Void = { _ in }) async throws -> (prewarm: Double, load: Double) {
            try await prepareVAD()
            #if canImport(CoreAI)
            if usesStagedEncoder {
                let started = ProcessInfo.processInfo.systemUptime
                let selection = try await PhoWhisperStagedEncoder.verifiedSelection()
                if try Self.preparationMode(ProcessInfo.processInfo.arguments) == .automatic {
                    await progress("Preparing the verified encoder on this iPhone… Keep Mural open. End cancels safely.")
                    try await PhoWhisperStagedEncoder.prepareForConversation(selection)
                    try Task.checkCancellation()
                }
                struct Generation: Decodable { let suppress_tokens: [Int] }
                suppressedTokens = try JSONDecoder().decode(Generation.self,
                    from: Data(contentsOf: directory.appending(path: "generation_config.json"))).suppress_tokens
                let tokenizer = try await PhoWhisperTokenizer.load(from: directory)
                try Task.checkCancellation()
                guard directory.standardizedFileURL == selection.supportURL.standardizedFileURL else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                // This receipt covers ONLY the Core ML decoder. The staged encoder still
                // requires its independently verified Core AI asset/cache on every preparation.
                stagedPreparation = try CoreMLPreparationReceipt(verifiedDirectory: directory,
                    scope: .stagedDecoder, computeUnits: ["decoder": Self.stagedDecoderCompute.rawValue])
                stagedDirectory = directory; stagedSelection = selection; stagedTokenizer = tokenizer
                stagedDecoderPrewarmedAt = nil
                if try Self.preparationMode(ProcessInfo.processInfo.arguments) == .automatic {
                    await progress("Preparing and validating speech on this iPhone…")
                    try await validateStagedDecoderForConversation()
                    try Task.checkCancellation()
                }
                inferenceCount = 0
                Logger(subsystem: "no.william.mural", category: "LocalAudio")
                    .notice("asr_staged_prepared backend=coreai-gpu encoder_deferred_until_send=true decoder_prewarm=with-greeting receipt_reuse=true encoder=\(selection.encoderURL.lastPathComponent, privacy: .public) selection=\(selection.v3?.format ?? selection.legacy?.rawValue ?? "original", privacy: .public) decoder_support=\(selection.supportIdentity, privacy: .public)")
                return (0, ProcessInfo.processInfo.systemUptime - started)
            }
            #endif
            // Only Prepare can fetch missing tokenizer assets. Loaded inference uses
            // in-memory weights/tokenizer; no hosted endpoint or automatic fallback.
            let config = WhisperKitConfig(modelFolder: directory.path,
                tokenizerFolder: phoWhisper ? directory : URL.applicationSupportDirectory.appending(path: "WhisperKit"),
                computeOptions: phoWhisper ? ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine) : nil,
                featureExtractor: CancellableWhisperModel(FeatureExtractor()),
                audioEncoder: CancellableWhisperModel(AudioEncoder()),
                textDecoder: CancellableWhisperModel(TextDecoder()),
                verbose: false, prewarm: false, load: false, download: false)
            let loaded = try await WhisperKit(config)
            let tokenizerStarted = ProcessInfo.processInfo.systemUptime
            if phoWhisper {
                struct Generation: Decodable { let suppress_tokens: [Int] }
                suppressedTokens = try JSONDecoder().decode(Generation.self,
                    from: Data(contentsOf: directory.appending(path: "generation_config.json"))).suppress_tokens
                loaded.tokenizer = try await PhoWhisperTokenizer.load(from: directory)
                loaded.textDecoder.isModelMultilingual = true
            }
            let localTokenizerSeconds = phoWhisper ? ProcessInfo.processInfo.systemUptime - tokenizerStarted : 0
            let logger = Logger(subsystem: "no.william.mural", category: "LocalAudio")
            if phoWhisper {
                logger.notice("asr_configuration model=phowhisper-cs-fp16-v1 encoder_permitted=CPU_AND_NE decoder_permitted=CPU_AND_NE local_tokenizer_seconds=\(localTokenizerSeconds, privacy: .public)")
            }
            do {
                try Task.checkCancellation()
                let prewarm: Double
                let loadSeconds: Double
                if phoWhisper {
                    let receipt = try CoreMLPreparationReceipt(verifiedDirectory: directory, scope: .eager,
                        computeUnits: ["mel": loaded.modelCompute.melCompute.rawValue,
                                       "encoder": loaded.modelCompute.audioEncoderCompute.rawValue,
                                       "decoder": loaded.modelCompute.textDecoderCompute.rawValue])
                    let preparation = try await receipt.prepare(prewarm: {
                        VietnameseEnglishRecognizer.logMemory(stage: "prewarm-begin", model: "phowhisper-cs-fp16-v1")
                        defer { VietnameseEnglishRecognizer.logMemory(stage: "prewarm-end", model: "phowhisper-cs-fp16-v1") }
                        try await loaded.prewarmModels()
                    }, loadAndValidate: {
                        VietnameseEnglishRecognizer.logMemory(stage: "load-begin", model: "phowhisper-cs-fp16-v1")
                        defer { VietnameseEnglishRecognizer.logMemory(stage: "load-end", model: "phowhisper-cs-fp16-v1") }
                        try await loaded.loadModels()
                        try Task.checkCancellation()
                        guard loaded.textDecoder.logitsSize == 51865, loaded.audioEncoder.embedSize == 1280 else {
                            throw CocoaError(.fileReadCorruptFile)
                        }
                    })
                    prewarm = preparation.prewarm; loadSeconds = preparation.load
                    VietnameseEnglishRecognizer.logMemory(stage: "loaded", model: "phowhisper-cs-fp16-v1")
                    let timing = loaded.currentTimings
                    // SDK specialization fields time prewarm loads, not proven compilation.
                    logger.notice("asr_model_timing model=phowhisper-cs-fp16-v1 prewarm_seconds=\(prewarm, privacy: .public) load_seconds=\(loadSeconds, privacy: .public) encoder_specialization_seconds=\(timing.encoderSpecializationTime, privacy: .public) decoder_specialization_seconds=\(timing.decoderSpecializationTime, privacy: .public) encoder_load_seconds=\(timing.encoderLoadTime, privacy: .public) decoder_load_seconds=\(timing.decoderLoadTime, privacy: .public)")
                } else {
                    // Stock Whisper is not a locally pinned PhoWhisper artifact.
                    // Leave its existing preparation and download policy unchanged.
                    let started = ProcessInfo.processInfo.systemUptime
                    try await loaded.prewarmModels()
                    try Task.checkCancellation()
                    prewarm = ProcessInfo.processInfo.systemUptime - started
                    let loadStarted = ProcessInfo.processInfo.systemUptime
                    try await loaded.loadModels()
                    try Task.checkCancellation()
                    loadSeconds = ProcessInfo.processInfo.systemUptime - loadStarted
                }
                try Task.checkCancellation()
                logger.notice("asr_prewarmed model=\(self.phoWhisper ? "phowhisper-cs-fp16-v1" : "whisper", privacy: .public) seconds=\(prewarm, privacy: .public)")
                kit = loaded
                inferenceCount = 0
                return (prewarm, loadSeconds + localTokenizerSeconds)
            } catch {
                // Stop/cancellation never releases admission before native work has returned.
                await loaded.unloadModels()
                loaded.tokenizer = nil
                throw error
            }
        }

        // Keep VAD under the existing ASR owner; explicit off/observe modes remain available.
        private func prepareVAD() async throws {
            guard phoWhisper else { return }
            vadMode = try SpeechPresencePolicy.Mode(arguments: ProcessInfo.processInfo.arguments)
            guard vadMode != .off else { return }
            let logger = Logger(subsystem: "no.william.mural", category: "LocalAudio")
            do {
                try Task.checkCancellation()
                let prepared = try await VadManager(config: VadConfig(
                    defaultThreshold: SpeechPresencePolicy.threshold, computeUnits: .cpuAndNeuralEngine))
                try Task.checkCancellation()
                vad = prepared
                logger.notice("asr_vad_prepared mode=\(self.vadMode.rawValue, privacy: .public) model=\(ModelNames.VAD.sileroVadFile, privacy: .public) threshold=\(SpeechPresencePolicy.threshold, privacy: .public) speech_score_threshold=\(SpeechPresencePolicy.speechScoreThreshold, privacy: .public) permitted=CPU_AND_NE")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                vad = nil
                // An unavailable VAD is not evidence of silence. Do not change ASR models.
                logger.warning("asr_vad_unavailable phase=prepare action=allow_asr")
            }
        }

        func analyzeSpeech(_ samples: [Float], turnID: UUID) async throws -> SpeechPresencePolicy.Analysis {
            try Task.checkCancellation()
            // Both recurrent state and segmentation evidence are owned by this call only.
            var evidence = SpeechPresencePolicy.Evidence(sampleCount: samples.count)
            let original = evidence.analyze(samples, mode: phoWhisper ? vadMode : .off)
            guard phoWhisper, vadMode != .off else { return original }
            guard samples.count <= 480_000, samples.allSatisfy(\.isFinite) else { throw CaptureError.tooLong }
            let logger = Logger(subsystem: "no.william.mural", category: "LocalAudio")
            guard let vad else {
                logger.warning("asr_vad_result id=\(turnID.uuidString, privacy: .public) mode=\(self.vadMode.rawValue, privacy: .public) evidence=unavailable rejected=false")
                return original
            }
            let started = ProcessInfo.processInfo.systemUptime
            VietnameseEnglishRecognizer.logMemory(stage: "vad-begin", model: ModelNames.VAD.sileroVadFile)
            // These values belong to this turn, never to the reusable manager or next recording.
            var state = VadStreamState.initial()
            do {
                for offset in stride(from: 0, to: samples.count, by: SpeechPresencePolicy.chunkSize) {
                    try Task.checkCancellation()
                    let end = min(offset + SpeechPresencePolicy.chunkSize, samples.count)
                    let result = try await vad.processStreamingChunk(Array(samples[offset..<end]), state: state)
                    // FluidAudio's native prediction is synchronous. Await it, then honor cancellation.
                    try Task.checkCancellation()
                    state = result.state
                    evidence.append(probability: result.probability, sampleCount: end - offset)
                    logger.notice("asr_vad_window id=\(turnID.uuidString, privacy: .public) start_sample=\(offset, privacy: .public) samples=\(end - offset, privacy: .public) probability=\(result.probability, privacy: .public)")
                }
                try Task.checkCancellation()
                VietnameseEnglishRecognizer.logMemory(stage: "vad-end", model: ModelNames.VAD.sileroVadFile)
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                let analysis = evidence.analyze(samples, mode: vadMode)
                let rejected = analysis.rejected
                #if MURAL_VAD_PROBE
                if vadOnly {
                    logger.notice("asr_vad_short_pair id=\(turnID.uuidString, privacy: .public) present=\(evidence.hasStrongSpeechPair, privacy: .public) threshold=\(SpeechPresencePolicy.shortSpeechThreshold, privacy: .public) full_window_samples=\(SpeechPresencePolicy.chunkSize, privacy: .public)")
                }
                #endif
                logger.notice("asr_vad_result id=\(turnID.uuidString, privacy: .public) mode=\(self.vadMode.rawValue, privacy: .public) samples=\(samples.count, privacy: .public) duration_seconds=\(Double(samples.count) / 16000, privacy: .public) windows=\(evidence.windowCount, privacy: .public) max_probability=\(evidence.maxProbability, privacy: .public) mean_probability=\(evidence.meanProbability, privacy: .public) speech_score=\(evidence.speechScore, privacy: .public) active_windows=\(evidence.activeWindows, privacy: .public) active_window_seconds=\(Double(evidence.activeWindowSamples) / 16000, privacy: .public) first_active_sample=\(evidence.firstActiveSample ?? -1, privacy: .public) last_active_sample_exclusive=\(evidence.lastActiveSampleExclusive ?? -1, privacy: .public) complete=\(evidence.complete, privacy: .public) would_reject=\(evidence.wouldReject, privacy: .public) rejected=\(rejected, privacy: .public) analysis_seconds=\(elapsed, privacy: .public)")
                return analysis
            } catch is CancellationError {
                logger.notice("asr_vad_cancelled id=\(turnID.uuidString, privacy: .public)")
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                logger.warning("asr_vad_result id=\(turnID.uuidString, privacy: .public) mode=\(self.vadMode.rawValue, privacy: .public) evidence=error rejected=false analysis_seconds=\(ProcessInfo.processInfo.systemUptime - started, privacy: .public)")
                return original
            }
        }

        #if canImport(CoreAI)
        /// Readiness means successful normal decoder/frontend loading, not just verified files.
        /// Keep the staged residency boundary: load, validate and release before recording.
        private func validateStagedDecoderForConversation() async throws {
            guard let directory = stagedDirectory, let receipt = stagedPreparation else { throw SpeechError.busy }
            let decoder = CancellableWhisperModel(TextDecoder())
            let mel = CancellableWhisperModel(FeatureExtractor())
            defer { decoder.unloadModel(); mel.unloadModel() }
            _ = try await receipt.prepare(prewarm: {
                try await decoder.loadModel(at: directory.appending(path: "TextDecoder.mlmodelc"),
                    computeUnits: Self.stagedDecoderCompute, prewarmMode: true)
            }, loadAndValidate: {
                try await decoder.loadModel(at: directory.appending(path: "TextDecoder.mlmodelc"), computeUnits: Self.stagedDecoderCompute)
                try Task.checkCancellation()
                guard decoder.logitsSize == 51865 else { throw CocoaError(.fileReadCorruptFile) }
                try await mel.loadModel(at: directory.appending(path: "MelSpectrogram.mlmodelc"), computeUnits: .cpuAndGPU)
                try Task.checkCancellation()
                guard mel.melCount == 80, mel.windowSamples == 480_000 else { throw CocoaError(.fileReadCorruptFile) }
            })
            try Task.checkCancellation()
            stagedDecoderPrewarmedAt = directory // Also reusable when an atomic receipt write was unavailable.
        }

        func prewarmStagedDecoder() async throws {
            guard usesStagedEncoder, let directory = stagedDirectory,
                  let receipt = stagedPreparation else { return }
            try Task.checkCancellation()
            let mode = try Self.preparationMode(ProcessInfo.processInfo.arguments)
            let logger = Logger(subsystem: "no.william.mural", category: "LocalAudio")
            if !receipt.needsPrewarm(mode: mode, alreadyPrewarmed: stagedDecoderPrewarmedAt == directory) {
                logger.notice("asr_staged_decoder_speculative_skipped prewarm_reused=true")
                return
            }
            let started = ProcessInfo.processInfo.systemUptime
            logger.notice("asr_staged_decoder_speculative_begin uptime=\(started, privacy: .public) decoder_support=\(directory.lastPathComponent, privacy: .public)")
            VietnameseEnglishRecognizer.logMemory(stage: "speculative-decoder-begin", model: directory.lastPathComponent)
            let decoder = CancellableWhisperModel(TextDecoder())
            defer {
                decoder.unloadModel()
                VietnameseEnglishRecognizer.logMemory(stage: "speculative-decoder-end", model: directory.lastPathComponent)
            }
            do {
                try Task.checkCancellation()
                try await decoder.loadModel(at: directory.appending(path: "TextDecoder.mlmodelc"),
                                            computeUnits: Self.stagedDecoderCompute, prewarmMode: true)
                try Task.checkCancellation()
                stagedDecoderPrewarmedAt = directory
                logger.notice("asr_staged_decoder_speculative_complete seconds=\(ProcessInfo.processInfo.systemUptime - started, privacy: .public)")
            } catch is CancellationError {
                logger.notice("asr_staged_decoder_speculative_cancelled")
                throw CancellationError()
            } catch {
                let failure = error as NSError
                logger.error("asr_staged_decoder_speculative_failed domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public)")
                throw error
            }
        }

        private func transcribeStaged(_ samples: [Float]) async throws -> String {
            guard let directory = stagedDirectory, let selection = stagedSelection,
                  let tokenizer = stagedTokenizer, let receipt = stagedPreparation else { throw SpeechError.busy }
            guard samples.count <= 480_000, samples.allSatisfy(\.isFinite) else { throw CaptureError.tooLong }
            guard !samples.isEmpty else { return "" }
            let logger = Logger(subsystem: "no.william.mural", category: "LocalAudio")
            inferenceCount += 1
            let turn = inferenceCount, started = ProcessInfo.processInfo.systemUptime
            logger.notice("asr_staged_turn_begin turn=\(turn, privacy: .public) encoder=\(selection.encoderURL.lastPathComponent, privacy: .public) selection=\(selection.v3?.format ?? selection.legacy?.rawValue ?? "original", privacy: .public) decoder_support=\(selection.supportIdentity, privacy: .public)")
            // Always await the scope, even when Stop cancels its outer owner.
            _ = VietnameseEnglishRecognizer.logMemory(stage: "trial-before-encoder", model: selection.supportIdentity)
            let encoderTask = Task { try await PhoWhisperStagedEncoder.encode(samples, support: directory, selection: selection, challengeSeed: turn & 31) }
            let encoded = try await withTaskCancellationHandler {
                try await encoderTask.value // Still drain native work before releasing the owner.
            } onCancel: { encoderTask.cancel() }
            try Task.checkCancellation()
            logger.notice("asr_staged_encoder_released turn=\(turn, privacy: .public)")
            _ = VietnameseEnglishRecognizer.logMemory(stage: "trial-after-encoder-scope", model: selection.supportIdentity)
            let loaded = try await WhisperKit(WhisperKitConfig(modelFolder: directory.path,
                tokenizerFolder: directory,
                computeOptions: ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine,
                                                    textDecoderCompute: Self.stagedDecoderCompute),
                featureExtractor: CancellableWhisperModel(FeatureExtractor()),
                audioEncoder: PhoWhisperStagedEncoder.Replay(encoded),
                textDecoder: CancellableWhisperModel(TextDecoder()),
                verbose: false, prewarm: false, load: false, download: false))
            loaded.tokenizer = tokenizer
            loaded.textDecoder.isModelMultilingual = true
            do {
                try Task.checkCancellation()
                let mode = try Self.preparationMode(ProcessInfo.processInfo.arguments)
                let preparation = try await receipt.prepare(mode: mode,
                    alreadyPrewarmed: stagedDecoderPrewarmedAt == directory, prewarm: {
                        if mode == .automatic {
                            // The staged encoder already loaded the mel frontend. Warm only
                            // the decoder here, exactly like the successful greeting path.
                            let decoder = CancellableWhisperModel(TextDecoder())
                            defer { decoder.unloadModel() }
                            try await decoder.loadModel(at: directory.appending(path: "TextDecoder.mlmodelc"),
                                computeUnits: Self.stagedDecoderCompute, prewarmMode: true)
                        } else {
                            // Preserve historical full prewarm counts for explicit trials.
                            try await loaded.prewarmModels()
                        }
                        try Task.checkCancellation()
                        self.stagedDecoderPrewarmedAt = directory
                    }, loadAndValidate: {
                        try await loaded.loadModels()
                        try Task.checkCancellation()
                        guard loaded.textDecoder.logitsSize == 51865 else { throw CocoaError(.fileReadCorruptFile) }
                    })
                try Task.checkCancellation()
                logger.notice("asr_trial_prewarm turn=\(turn, privacy: .public) reused=\(!preparation.didPrewarm, privacy: .public)")
                // Legacy duration keys retained; coreml_preparation supplies actual phase boundaries.
                logger.notice("asr_staged_decoder_send_prewarm_complete turn=\(turn, privacy: .public) seconds=\(preparation.prewarm, privacy: .public)")
                logger.notice("asr_staged_decoder_send_load_complete turn=\(turn, privacy: .public) seconds=\(preparation.load, privacy: .public)")
                _ = VietnameseEnglishRecognizer.logMemory(stage: "trial-decoder-loaded", model: selection.supportIdentity)
                let decodeStarted = ProcessInfo.processInfo.systemUptime
                let results = try await loaded.transcribe(audioArray: samples, decodeOptions: decodingOptions())
                try Task.checkCancellation()
                logger.notice("asr_staged_decoder_decode_complete turn=\(turn, privacy: .public) seconds=\(ProcessInfo.processInfo.systemUptime - decodeStarted, privacy: .public) tokens=\(results.flatMap { $0.segments.flatMap(\.tokens) }.count, privacy: .public) loop_seconds=\(results.reduce(0) { $0 + $1.timings.decodingLoop }, privacy: .public) prediction_seconds=\(results.reduce(0) { $0 + $1.timings.decodingPredictions }, privacy: .public) scope=replay-transcription-not-native-decoder")
                _ = VietnameseEnglishRecognizer.logMemory(stage: "trial-decoder-finished", model: selection.supportIdentity)
                let unloadStarted = ProcessInfo.processInfo.systemUptime
                await loaded.unloadModels()
                loaded.tokenizer = nil
                _ = VietnameseEnglishRecognizer.logMemory(stage: "trial-decoder-unloaded", model: selection.supportIdentity)
                logger.notice("asr_staged_decoder_unload_complete turn=\(turn, privacy: .public) seconds=\(ProcessInfo.processInfo.systemUptime - unloadStarted, privacy: .public)")
                // Legacy timer key retained for log readers; this excludes the UI Send boundary.
                logger.notice("asr_staged_turn_complete turn=\(turn, privacy: .public) end_to_end_seconds=\(ProcessInfo.processInfo.systemUptime - started, privacy: .public) scope=staged-transcribe-through-unload-not-ui-send")
                return results.map(\.text).joined(separator: " ")
            } catch {
                // No fallback or new turn can start until this task and its locals return.
                await loaded.unloadModels()
                loaded.tokenizer = nil
                logger.notice("asr_staged_turn_drained turn=\(turn, privacy: .public)")
                throw error
            }
        }
        #endif

        private func decodingOptions() -> DecodingOptions {
            // No expected words, translation, or cross-turn prompt. Zero clipping
            // allows sub-second Yes/No; retain native no-speech/fallback thresholds.
            var options = DecodingOptions(task: .transcribe, detectLanguage: true,
                skipSpecialTokens: true, windowClipTime: 0, concurrentWorkerCount: 1)
            if phoWhisper {
                // Exact Mac parity settings: greedy, no timestamps or threshold-based
                // turn dropping. VAD qualification is separate; keep decoder heuristics unchanged.
                options.temperatureFallbackCount = 0
                options.withoutTimestamps = true
                options.suppressBlank = true
                options.suppressTokens = suppressedTokens
                options.compressionRatioThreshold = nil
                options.logProbThreshold = nil
                options.firstTokenLogProbThreshold = nil
                options.noSpeechThreshold = nil
            }
            return options
        }

        func transcribe(_ samples: [Float]) async throws -> String {
            try Task.checkCancellation()
            #if MURAL_VAD_PROBE
            guard !vadOnly else { throw CaptureError.operation("VAD-only cannot invoke ASR.") }
            #endif
            #if canImport(CoreAI)
            if usesStagedEncoder {
                return try await transcribeStaged(samples)
            }
            #endif
            guard let kit else { throw SpeechError.busy }
            guard samples.count <= 480_000, samples.allSatisfy(\.isFinite) else { throw CaptureError.tooLong }
            guard !samples.isEmpty else { return "" }
            let options = decodingOptions()
            inferenceCount += 1
            let turn = inferenceCount
            let started = ProcessInfo.processInfo.systemUptime
            let logger = Logger(subsystem: "no.william.mural", category: "LocalAudio")
            if phoWhisper {
                logger.notice("asr_inference_started model=phowhisper-cs-fp16-v1 turn=\(turn, privacy: .public) first_since_prepare=\(turn == 1, privacy: .public)")
            }
            let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
            let inferenceSeconds = ProcessInfo.processInfo.systemUptime - started
            try Task.checkCancellation()
            if phoWhisper {
                logger.notice("asr_inference_finished model=phowhisper-cs-fp16-v1 turn=\(turn, privacy: .public) wall_seconds=\(inferenceSeconds, privacy: .public) windows=\(results.count, privacy: .public)")
                for (window, result) in results.enumerated() {
                    let timing = result.timings
                    // These fields overlap: predictions include language detection;
                    // WhisperKit 1.1.0 exposes no separate language-detection total.
                    logger.notice("asr_component_timing turn=\(turn, privacy: .public) window=\(window, privacy: .public) mel_seconds=\(timing.logmels, privacy: .public) encoding_seconds=\(timing.encoding, privacy: .public) decoding_init_seconds=\(timing.decodingInit, privacy: .public) decoding_loop_seconds=\(timing.decodingLoop, privacy: .public) predictions_including_language_seconds=\(timing.decodingPredictions, privacy: .public) nonprediction_seconds=\(timing.decodingNonPrediction, privacy: .public) pipeline_seconds=\(timing.fullPipeline, privacy: .public)")
                }
                VietnameseEnglishRecognizer.logMemory(stage: "finalized", model: "phowhisper-cs-fp16-v1")
            }
            return results.map(\.text).joined(separator: " ")
        }
    }

    private enum CaptureError: LocalizedError {
        case microphone, format, overloaded, audioSession, tooLong, operation(String)
        var errorDescription: String? {
            switch self {
            case .operation(let message): message
            case .microphone: "Allow microphone access in iPhone Settings > Mural, then tap Record again."
            case .format: "The microphone format is unavailable. Disconnect other audio devices and reopen the probe."
            case .overloaded: "Speech processing could not keep up. No partial turn was accepted. Try a shorter recording."
            case .audioSession: "The microphone or speaker could not start. Close other audio apps and try again."
            case .tooLong: "The recognizer requires finite 16 kHz audio of at most 30 seconds. No truncated turn was accepted."
            }
        }
    }

    private enum SpeechError: LocalizedError {
        case busy, noVoice
        var errorDescription: String? {
            switch self {
            case .busy: "Wait for the current speech to finish."
            case .noVoice: "No English voice is available. Download an English voice in iPhone Settings > Accessibility > Read & Speak > Voices, then try again."
            }
        }
    }
}

#if canImport(CoreAI)
/// Shared frozen tensor/asset contracts; no decoder or provider ownership.
enum PhoWhisperStagedEncoder {
    // Default packed-v3 FP8/PAL8 Talk path. Legacy candidates and diagnostic trials remain explicit.
    enum CompressionCandidate: String, Sendable {
        case fp8, int8
        case originalPAL8 = "original-pal8", fp8PAL8 = "fp8-pal8", int8PAL8 = "int8-pal8"
        var encoder: String {
            switch self {
            case .fp8, .fp8PAL8: "fp8"
            case .int8, .int8PAL8: "int8"
            case .originalPAL8: "original"
            }
        }
        var supportIdentity: String {
            switch self {
            case .fp8, .int8: "phowhisper-cs-fp16-v1"
            default: "phowhisper-cs-pal8-g16-v1"
            }
        }
        var supportManifest: String {
            switch self {
            case .fp8, .int8: "7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52"
            default: "430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336"
            }
        }
        var fingerprint: String {
            switch self {
            case .fp8, .fp8PAL8: "cf920ab8ee572096f6dbc6adc0480999e1b4d95fdabcc4227845152d259274ef"
            case .int8, .int8PAL8: "4f14f0195c12bd8fbde152e30170c601bddb726b57a2724ccdc6dfa5e40b6ff6"
            case .originalPAL8: "f783c9b539d90a589e1449e514599e240ce6036b3bab6c298858e49bba112829"
            }
        }
        var url: URL {
            if self == .originalPAL8 {
                return URL.applicationSupportDirectory.appending(path:
                    "CoreAI/PhoWhisperGPU/phowhisper-cs-fp16-v1.encoder.h18p.aimodelc")
            }
            return URL.applicationSupportDirectory.appending(path:
                "CoreAI/PhoWhisperW8/\(encoder)-pc-v1/phowhisper-cs-\(encoder)-pc-v1.encoder.h18p.aimodelc")
        }
        static func resolve() throws -> Self? {
            let flags = ProcessInfo.processInfo.arguments.filter { $0.hasPrefix("--coreai-compressed-encoder=") }
            guard !flags.isEmpty else { return nil }
            guard flags.count == 1, let candidate = Self(rawValue: String(flags[0].dropFirst("--coreai-compressed-encoder=".count))),
                  AIModel.deviceArchitectureName == "h18p" else {
                throw Failure("Compression trial requires one pinned candidate on an h18p device.")
            }
            // coreai-build 3600.83.1 emitted the same AOT main.hash for FP8 and INT8.
            // AIModelCache then returned INT8 for the FP8 asset. Do not load either
            // candidate until independently keyed artifacts are qualified. No cache deletion.
            guard candidate == .originalPAL8 else {
                throw Failure("Compressed encoder trial blocked: FP8 and INT8 alias the same native cache identity. No model was loaded.")
            }
            return candidate
        }
    }

    struct V3Selection: Sendable {
        let format: String
        let encoderURL: URL
        let manifestURL: URL
        let manifestSHA256: String
        let artifactFingerprint: String
        let artifactBytes: Int
        let identity: W8RuntimeIdentitySpec
        let supportIdentity: String
        let supportManifest: String
        let supportURL: URL
    }

    struct Selection: Sendable {
        let encoderURL: URL
        let encoderFingerprint: String
        let supportIdentity: String
        let supportManifest: String
        let supportURL: URL
        let legacy: CompressionCandidate?
        let v3: V3Selection?
    }

    private struct V3Manifest: Decodable {
        struct Artifact: Decodable {
            let path: String
            let fingerprint: String
            let bytes: Int
        }
        let schema: String
        let status: String
        let identity: W8RuntimeIdentitySpec
        let source: Artifact
        let aot: Artifact
    }

    private static let fullManifestPins: [String: String] = [
        "packed:fp16": "3c87a4cc096d842c2ddb530d23ec2c808c034da5839f1589dde26a13582d9b14",
        "packed:fp8": "73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13",
        "packed:int8": "93b4706943dcc5612d67c73d7f6a6ab11acb48fe1d588d7e3510a4133f081acc",
        "packed:pal6": "b3437340b110c14349cd3f12ae0955adb8254fdc277e263907eaa3d96e651966",
        "packed:pal4": "96c7c788ec49b76aa8a4d52ac961a1f93869676d05fcb5109eeb8be581bf765f"
    ]

    static func resolveSelection() throws -> Selection {
        let arguments = ProcessInfo.processInfo.arguments
        _ = try DecoderTrialPolicy.once(arguments) // Reject unsupported/ambiguous policy before loading.
        let encoderFlags = arguments.filter { $0.hasPrefix("--coreai-w8-v3-encoder=") }
        let decoderFlags = arguments.filter { $0.hasPrefix("--coreai-w8-v3-decoder=") }
        guard encoderFlags.count <= 1, decoderFlags.count <= 1 else {
            throw Failure("The v3 encoder and decoder selections must each be specified once.")
        }
        if let encoderFlag = encoderFlags.first {
            guard AIModel.deviceArchitectureName == "h18p" else {
                throw Failure("The v3 encoder requires an h18p device.")
            }
            guard !arguments.contains(where: { $0.hasPrefix("--coreai-compressed-encoder=") }) else {
                throw Failure("The v3 selection cannot be combined with the old compressed-encoder guard.")
            }
            let format = String(encoderFlag.dropFirst("--coreai-w8-v3-encoder=".count))
            guard ["fp16", "fp8", "int8", "pal6", "pal4"].contains(format) else {
                throw Failure("The v3 encoder must be fp16, fp8, int8, pal6, or pal4.")
            }
            let decoder: String
            if let decoderFlag = decoderFlags.first {
                decoder = String(decoderFlag.dropFirst("--coreai-w8-v3-decoder=".count))
            } else {
                decoder = "fp16"
            }
            guard ["fp16", "pal8", "pal6", "pal4"].contains(decoder) else {
                throw Failure("The v3 decoder must be fp16, pal8, pal6, or pal4.")
            }
            try DecoderTrialPolicy.validatePair(encoder: format, decoder: decoder, arguments: arguments)
            return try makeV3Selection(format: format, decoder: decoder)
        }
        guard decoderFlags.isEmpty else {
            throw Failure("The v3 decoder selection requires a v3 encoder selection.")
        }
        let candidate = try CompressionCandidate.resolve()
        if candidate == nil && !arguments.contains(where: { $0.hasPrefix("--coreai-product-") }) {
            return try makeV3Selection(format: "fp8", decoder: "pal8")
        }
        let supportIdentity = candidate?.supportIdentity ?? "phowhisper-cs-fp16-v1"
        let supportManifest = candidate?.supportManifest ?? "7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52"
        let supportURL = URL.applicationSupportDirectory.appending(path:
            "PhoWhisperCS/\(supportIdentity)", directoryHint: .isDirectory)
        let encoderURL = candidate?.url ?? URL.applicationSupportDirectory.appending(path:
            "CoreAI/PhoWhisperGPU/phowhisper-cs-fp16-v1.encoder.h18p.aimodelc")
        return Selection(encoderURL: encoderURL,
                         encoderFingerprint: candidate?.fingerprint ?? "f783c9b539d90a589e1449e514599e240ce6036b3bab6c298858e49bba112829",
                         supportIdentity: supportIdentity, supportManifest: supportManifest,
                         supportURL: supportURL, legacy: candidate, v3: nil)
    }

    private static func makeV3Selection(format: String, decoder: String) throws -> Selection {
        let supportIdentity: String
        let supportManifest: String
        switch decoder {
        case "pal6": supportIdentity = "phowhisper-cs-pal6-g16-v1"
            supportManifest = "13f9bbd0d08bf0b6a111f8415ddffad158f8d1fb4e4014c17585066e37fd23bb"
        case "pal4": supportIdentity = "phowhisper-cs-pal4-g16-v1"
            supportManifest = "bbdee2a57bbb29e538389364969e75f731dd4f0baf2dd977830f966857095702"
        case "pal8": supportIdentity = "phowhisper-cs-pal8-g16-v1"
            supportManifest = "430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336"
        default: supportIdentity = "phowhisper-cs-fp16-v1"
            supportManifest = "7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52"
        }
        guard AIModel.deviceArchitectureName == "h18p" else {
            throw Failure("The v3 encoder requires an h18p device.")
        }
        let production = !ProcessInfo.processInfo.arguments.contains {
            $0.hasPrefix("--coreai-w8-v3-") || $0.hasPrefix("--coreai-product-") || $0.hasPrefix("--coreai-compressed-encoder=")
        }
        let managedSupport = production ? try LocalSpeechProvisioning.installedDirectory(for: .vietnameseEnglish, component: "support") : nil
        let managedEncoder = production ? try LocalSpeechProvisioning.installedDirectory(for: .vietnameseEnglish, component: "encoder") : nil
        let supportURL = managedSupport ?? URL.applicationSupportDirectory.appending(path:
            "PhoWhisperCS/\(supportIdentity)", directoryHint: .isDirectory)
        let folder = managedEncoder ?? URL.documentsDirectory.appending(path:
            "CoreAI/W8FullV3/packed/encoder-\(format)", directoryHint: .isDirectory)
        let manifestURL = folder.appending(path: "manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifestHash = sha256(manifestData)
        guard manifestHash == fullManifestPins["packed:\(format)"] else {
            throw Failure("The v3 \(format) manifest is not the audited pinned manifest.")
        }
        let manifest = try JSONDecoder().decode(V3Manifest.self, from: manifestData)
        guard manifest.schema == "mural-w8-runtime-identity-v3", manifest.status == "aot-static-only",
              manifest.identity.kind == "encoder", manifest.identity.format == format,
              manifest.identity.transport == "packed", manifest.source.bytes > 0,
              manifest.aot.bytes > 0 else {
            throw Failure("The v3 \(format) manifest is not a packed full encoder artifact.")
        }
        try manifest.identity.validate()
        let sourceURL = folder.appending(path: URL(fileURLWithPath: manifest.source.path).lastPathComponent)
        let artifactURL = folder.appending(path: "aot/\(URL(fileURLWithPath: manifest.aot.path).lastPathComponent)")
        guard FileManager.default.fileExists(atPath: sourceURL.path),
              FileManager.default.fileExists(atPath: artifactURL.path),
              try bundleBytes(sourceURL) == manifest.source.bytes,
              try bundleBytes(artifactURL) == manifest.aot.bytes else {
            throw Failure("The v3 \(format) source or AOT artifact is missing or truncated.")
        }
        guard try fingerprint(artifactURL, includeHiddenFiles: true) == manifest.aot.fingerprint else {
            throw Failure("The v3 \(format) AOT artifact failed its manifest fingerprint.")
        }
        let v3 = V3Selection(format: format, encoderURL: artifactURL, manifestURL: manifestURL,
                             manifestSHA256: manifestHash, artifactFingerprint: manifest.aot.fingerprint,
                             artifactBytes: manifest.aot.bytes, identity: manifest.identity,
                             supportIdentity: supportIdentity, supportManifest: supportManifest,
                             supportURL: supportURL)
        return Selection(encoderURL: artifactURL, encoderFingerprint: manifest.aot.fingerprint,
                         supportIdentity: supportIdentity, supportManifest: supportManifest,
                         supportURL: supportURL, legacy: nil, v3: v3)
    }

    @concurrent static func verifiedSelection() async throws -> Selection {
        let selection = try resolveSelection()
        if selection.v3 == nil {
            guard AIModel.deviceArchitectureName == "h18p",
                  try fingerprint(selection.encoderURL) == selection.encoderFingerprint else {
                throw Failure("The legacy staged encoder is missing, changed, or unqualified for this device. No fallback was attempted.")
            }
        }
        return selection
    }

    static var enabled: Bool { true }

    /// Same persistent specialization API as the existing phone harness. No precision/backend fallback.
    @concurrent static func prepareForConversation(_ selection: Selection) async throws {
        try Task.checkCancellation()
        guard let v3 = selection.v3, v3.format == "fp8", selection.supportIdentity == "phowhisper-cs-pal8-g16-v1" else {
            throw Failure("This speech package is not qualified for normal Talk. Choose another speech option.")
        }
        let options = SpecializationOptions(preferredComputeUnitKind: .gpu)
        let model: AIModel
        if let cached = try AIModelCache.default.model(for: selection.encoderURL, options: options) {
            model = cached
        } else {
            Logger(subsystem: "no.william.mural", category: "LocalAudio").notice("speech_encoder_specialization_begin")
            model = try await AIModel.specialize(contentsOf: selection.encoderURL, options: options, cachePolicy: .persistent)
            try Task.checkCancellation()
            Logger(subsystem: "no.william.mural", category: "LocalAudio").notice("speech_encoder_specialization_end")
        }
        try Task.checkCancellation()
        try v3.identity.requireModel(model)
        guard let descriptor = model.functionDescriptor(for: v3.identity.entrypoint),
              case .ndArray(let input) = descriptor.inputDescriptor(of: "input_features"),
              case .ndArray(let challenge) = descriptor.inputDescriptor(of: v3.identity.challengeInput),
              case .ndArray(let output) = descriptor.outputDescriptor(of: v3.identity.packedOutput),
              input.scalarType == .float16, input.shape == v3.identity.inputShape,
              challenge.scalarType == .float16, challenge.shape == v3.identity.challengeShape,
              output.scalarType == .float16, output.shape == v3.identity.packetShape,
              let _ = try model.loadFunction(named: v3.identity.entrypoint) else {
            throw Failure("The speech encoder failed validation. Retry preparation or choose another speech option; no transcript was accepted.")
        }
        try Task.checkCancellation()
        Logger(subsystem: "no.william.mural", category: "LocalAudio").notice("speech_encoder_ready")
    }

    @concurrent static func verifiedURL() async throws -> URL {
        try await verifiedSelection().encoderURL
    }

    struct Encoded: Sendable {
        let hidden: [Float16]
        let melHash: String
    }

    @concurrent static func encode(_ samples: [Float], support: URL, encoderURL: URL) async throws -> Encoded {
        let selection = try resolveSelection()
        guard selection.v3 == nil, selection.encoderURL == encoderURL else {
            throw Failure("The legacy encoder entry point cannot consume a v3 selection.")
        }
        return try await encode(samples, support: support, selection: selection, challengeSeed: 0)
    }

    @concurrent static func encode(_ samples: [Float], support: URL, selection: Selection,
                                   challengeSeed: Int) async throws -> Encoded {
        guard !samples.isEmpty, samples.count <= 480_000, samples.allSatisfy(\.isFinite) else {
            throw Failure("Expected finite 16 kHz audio of at most 30 seconds.")
        }
        let mel = FeatureExtractor()
        try await mel.loadModel(at: support.appending(path: "MelSpectrogram.mlmodelc"), computeUnits: .cpuAndGPU)
        defer { mel.unloadModel() }
        guard let padded = AudioProcessor.padOrTrimAudio(fromArray: samples, startAt: 0, toLength: 480_000, saveSegment: false),
              let features = try await mel.logMelSpectrogram(fromAudio: padded) as? MLMultiArray else {
            throw Failure("The speech frontend produced no mel tensor.")
        }
        let values = try readAcceptedMel(features)
        let options = SpecializationOptions(preferredComputeUnitKind: .gpu)
        let model: AIModel
        if let cached = try AIModelCache.default.model(for: selection.encoderURL, options: options) {
            model = cached
        } else {
            let trial = ProcessInfo.processInfo.arguments.contains {
                $0.hasPrefix("--coreai-w8-v3-") || $0.hasPrefix("--coreai-product-") || $0.hasPrefix("--coreai-compressed-encoder=")
            }
            guard !trial, selection.v3?.format == "fp8", selection.supportIdentity == "phowhisper-cs-pal8-g16-v1" else {
                throw Failure("The qualification trial requires its prepared encoder cache. No automatic rebuild or fallback was attempted.")
            }
            // Handles a cache purge after Ready as well as one between launches.
            try Task.checkCancellation()
            model = try await AIModel.specialize(contentsOf: selection.encoderURL, options: options, cachePolicy: .persistent)
            try Task.checkCancellation()
        }
        let hidden: [Float16]
        if let v3 = selection.v3 {
            try v3.identity.requireModel(model)
            guard let descriptor = model.functionDescriptor(for: v3.identity.entrypoint),
                  case .ndArray(let inputDescriptor) = descriptor.inputDescriptor(of: "input_features"),
                  case .ndArray(let challengeDescriptor) = descriptor.inputDescriptor(of: v3.identity.challengeInput),
                  case .ndArray(let outputDescriptor) = descriptor.outputDescriptor(of: v3.identity.packedOutput),
                  inputDescriptor.scalarType == .float16, inputDescriptor.shape == v3.identity.inputShape,
                  challengeDescriptor.scalarType == .float16, challengeDescriptor.shape == v3.identity.challengeShape,
                  outputDescriptor.scalarType == .float16, outputDescriptor.shape == v3.identity.packetShape,
                  let function = try model.loadFunction(named: v3.identity.entrypoint) else {
                throw Failure("The v3 speech encoder ABI changed; no hidden output was accepted.")
            }
            let challenge = try v3.identity.challenge(seed: challengeSeed & 31)
            var input = NDArray(descriptor: inputDescriptor)
            var inputView = input.mutableView(as: Float16.self)
            inputView.copyElements(fromContentsOf: values.map(Float16.init))
            var challengeArray = NDArray(descriptor: challengeDescriptor)
            var challengeView = challengeArray.mutableView(as: Float16.self)
            challengeView.copyElements(fromContentsOf: challenge)
            let nativeStart = ProcessInfo.processInfo.systemUptime
            var outputs = try await function.run(inputs: ["input_features": input,
                                                            v3.identity.challengeInput: challengeArray])
            let nativeSeconds = ProcessInfo.processInfo.systemUptime - nativeStart
            guard let packet = outputs.remove(v3.identity.packedOutput)?.ndArray else {
                throw Failure("The v3 speech encoder produced no packed output.")
            }
            let packed = try W8RuntimeIdentitySpec.readFP16(packet, shape: v3.identity.packetShape)
            hidden = try v3.identity.unpack(packed, challenge: challenge)
            guard hidden.count == v3.identity.hiddenCount else {
                throw Failure("The v3 speech encoder returned the wrong hidden count.")
            }
            Logger(subsystem: "no.william.mural", category: "LocalAudio").notice(
                "asr_staged_v3_encoder_native_complete format=\(v3.format, privacy: .public) seed=\(challengeSeed & 31, privacy: .public) native_seconds=\(nativeSeconds, privacy: .public) validation_copy_seconds=\(ProcessInfo.processInfo.systemUptime - nativeStart - nativeSeconds, privacy: .public)")
        } else {
            guard let descriptor = model.functionDescriptor(for: "main"),
                  case .ndArray(let inputDescriptor) = descriptor.inputDescriptor(of: "input_features"),
                  inputDescriptor.scalarType == .float16, inputDescriptor.shape == [1, 80, 3000],
                  let function = try model.loadFunction(named: "main") else {
                throw Failure("The experimental speech encoder could not load its frozen FP16 function.")
            }
            var input = NDArray(descriptor: inputDescriptor)
            var view = input.mutableView(as: Float16.self)
            view.copyElements(fromContentsOf: values.map(Float16.init))
            var outputs = try await function.run(inputs: ["input_features": input])
            guard let output = outputs.remove("encoder_hidden_states")?.ndArray else {
                throw Failure("The speech encoder produced no embeddings.")
            }
            hidden = try copyEncoderOutput(output)
        }
        return Encoded(hidden: hidden,
                       melHash: values.withUnsafeBufferPointer { sha256(Data(buffer: $0)) })
    }

    final class Replay: AudioEncoding {
        let embedSize: Int? = 1280
        private let encoded: Encoded
        init(_ encoded: Encoded) { self.encoded = encoded }
        func encodeFeatures(_ features: any FeatureExtractorOutputType) async throws -> (any AudioEncoderOutputType)? {
            guard let array = features as? MLMultiArray else { throw Failure("Missing replay mel tensor.") }
            let values = try readAcceptedMel(array)
            guard values.withUnsafeBufferPointer({ sha256(Data(buffer: $0)) }) == encoded.melHash else {
                throw Failure("Replay mel differs from the accepted frontend; no mismatched window was decoded.")
            }
            return try decoderEmbeddings(encoded.hidden)
        }
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
    static func copyEncoderOutput(_ hidden: NDArray) throws -> [Float16] {
        guard hidden.shape == [1, 1500, 1280], hidden.scalarType == .float16 else {
            throw Failure("Encoder output must remain FP16 [1,1500,1280].")
        }
        var owned = [Float16](repeating: 0, count: 1500 * 1280)
        hidden.view(as: Float16.self).withUnsafePointer { p, _, strides in
            for t in 0..<1500 { for c in 0..<1280 {
                owned[t * 1280 + c] = p[t * strides[1] + c * strides[2]]
            }}
        }
        guard owned.allSatisfy(\.isFinite) else { throw Failure("Non-finite encoder output.") }
        return owned
    }

    static func readAcceptedMel(_ a: MLMultiArray) throws -> [Float] {
        let shape = a.shape.map(\.intValue), strides = a.strides.map(\.intValue)
        guard shape == [1, 80, 3000] || shape == [1, 80, 1, 3000] else {
            throw Failure("Unexpected mel shape \(shape).")
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
        default: throw Failure("Unsupported mel type \(a.dataType).")
        }
        guard out.allSatisfy(\.isFinite) else { throw Failure("Non-finite mel.") }
        return out
    }

    static func decoderEmbeddings(_ values: [Float16]) throws -> MLMultiArray {
        guard values.count == 1500 * 1280, values.allSatisfy(\.isFinite) else {
            throw Failure("Expected finite FP16 [1,1500,1280] values.")
        }
        let result = try MLMultiArray(shape: [1, 1280, 1, 1500], dataType: .float16)
        let strides = result.strides.map(\.intValue)
        let p = result.dataPointer.assumingMemoryBound(to: Float16.self)
        for t in 0..<1500 { for c in 0..<1280 {
            p[c * strides[1] + t * strides[3]] = values[t * 1280 + c]
        }}
        return result
    }

    static func readDecoderEmbeddings(_ a: MLMultiArray) throws -> [Float16] {
        guard a.shape.map(\.intValue) == [1, 1280, 1, 1500], a.dataType == .float16 else {
            throw Failure("WhisperKit embeddings must be FP16 [1,1280,1,1500].")
        }
        let strides = a.strides.map(\.intValue)
        let p = a.dataPointer.assumingMemoryBound(to: Float16.self)
        var values = [Float16](repeating: 0, count: 1500 * 1280)
        for t in 0..<1500 { for c in 0..<1280 {
            values[t * 1280 + c] = p[c * strides[1] + t * strides[3]]
        }}
        guard values.allSatisfy(\.isFinite) else { throw Failure("Non-finite decoder embeddings.") }
        return values
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func bundleBytes(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true else { throw Failure("Symlinks are not diagnostic assets.") }
        if values.isDirectory == true {
            return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                                options: []).reduce(0) { total, child in
                total + (try bundleBytes(child))
            }
        }
        guard let size = values.fileSize else { throw Failure("Missing artifact file size.") }
        return size
    }

    // V3 uses the exporter's complete bundle inventory. Preserve the historical
    // visible-file-only hash contract for legacy assets; never rewrite their pins.
    static func fingerprint(_ url: URL, includeHiddenFiles: Bool = false) throws -> String {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw Failure("Symlinks are not diagnostic assets.") }
        if values.isDirectory == true {
            var children: [String: String] = [:]
            for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                                     options: includeHiddenFiles ? [] : [.skipsHiddenFiles]) {
                children[child.lastPathComponent] = try fingerprint(child, includeHiddenFiles: includeHiddenFiles)
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
}
#endif

/// Explicit offline trials only. No model ownership, cache mutation or default switch.
enum DecoderTrialPolicy {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let combinedFlag = "--coreai-w8-v3-combined=pal6-pal6"
    static let combined4Flag = "--coreai-w8-v3-combined=pal4-pal4"

    /// The extra flag is required ONLY for the previously unqualified joint pair.
    /// The runtime still checks the h18p build, pinned manifests, ABI and response.
    static func combined(_ arguments: [String]) throws -> Bool {
        let flags = arguments.filter { $0.hasPrefix("--coreai-w8-v3-combined") }
        guard flags.count <= 1 else { throw Failure(message: "Duplicate combined precision trial flag") }
        guard let flag = flags.first else { return false }
        let pair: (String, String)
        switch flag {
        case combinedFlag: pair = ("pal6", "pal6")
        case combined4Flag: pair = ("pal4", "pal4")
        default: throw Failure(message: "Unknown combined precision trial")
        }
        guard arguments.filter({ $0.hasPrefix("--coreai-w8-v3-encoder=") }) == ["--coreai-w8-v3-encoder=\(pair.0)"],
              arguments.filter({ $0.hasPrefix("--coreai-w8-v3-decoder=") }) == ["--coreai-w8-v3-decoder=\(pair.1)"],
              !arguments.contains(where: { $0.hasPrefix("--coreai-compressed-encoder=") }) else {
            throw Failure(message: "Combined trial requires matching explicit PAL4 or PAL6 encoder and decoder")
        }
        let product = arguments.contains { $0.hasPrefix("--coreai-product-") }
        let modes = arguments.filter { $0.hasPrefix("--coreai-product-mode=") }
        guard !product || modes == ["--coreai-product-mode=staged-gpu"] ||
                modes == ["--coreai-product-mode=staged-gpu-encode"] else {
            throw Failure(message: "Combined trial requires the sequential GPU owner or explicit live Talk")
        }
        guard !arguments.contains("--coreai-product-coexistence") else {
            throw Failure(message: "Combined precision qualification does not authorize concurrent probe companions")
        }
        return true
    }

    static func validatePair(encoder: String, decoder: String, arguments: [String]) throws {
        let joint = try combined(arguments)
        guard ["fp16", "fp8", "int8", "pal6", "pal4"].contains(encoder),
              ["fp16", "pal8", "pal6", "pal4"].contains(decoder) else {
            throw Failure(message: "Unknown encoder/decoder precision")
        }
        guard !joint || (encoder == "pal6" && decoder == "pal6") ||
                (encoder == "pal4" && decoder == "pal4") else {
            throw Failure(message: "Combined flag does not match the resolved pair")
        }
        guard decoder != "pal6" || encoder == "fp8" || (joint && encoder == "pal6") else {
            throw Failure(message: "PAL6 decoder requires fixed FP8 or the explicit combined PAL6 trial")
        }
        guard decoder != "pal4" || encoder == "fp8" || (joint && encoder == "pal4") else {
            throw Failure(message: "PAL4 decoder requires fixed FP8 or the explicit combined PAL4 trial")
        }
        guard encoder != "pal6" || decoder == "pal8" || (joint && decoder == "pal6") else {
            throw Failure(message: "PAL6 encoder requires PAL8 or the explicit combined PAL6 trial")
        }
        guard encoder != "pal4" || decoder == "pal8" || (joint && decoder == "pal4") else {
            throw Failure(message: "PAL4 encoder requires PAL8 or the explicit combined PAL4 trial")
        }
    }

    static func once(_ arguments: [String]) throws -> Bool {
        let joint = try combined(arguments) // Reject stray flags even with the default policy.
        let prefix = "--coreai-w8-v3-prewarm="
        let flags = arguments.filter { $0.hasPrefix("--coreai-w8-v3-prewarm") }
        guard flags.count <= 1 else { throw Failure(message: "Duplicate decoder prewarm policy") }
        guard let flag = flags.first else { return false } // Default is unchanged: always.
        guard [prefix + "always", prefix + "once"].contains(flag) else {
            throw Failure(message: "Decoder prewarm policy must be always or once")
        }
        let encoders = arguments.filter { $0.hasPrefix("--coreai-w8-v3-encoder=") }
        let decoders = arguments.filter { $0.hasPrefix("--coreai-w8-v3-decoder=") }
        let fixedFP8 = encoders == ["--coreai-w8-v3-encoder=fp8"] && decoders.count == 1 &&
            ["--coreai-w8-v3-decoder=pal8", "--coreai-w8-v3-decoder=pal6", "--coreai-w8-v3-decoder=pal4"].contains(decoders[0])
        // Explicit always also supports the historical encoder-only controls.
        let encoderControl = (encoders == ["--coreai-w8-v3-encoder=pal6"] ||
            encoders == ["--coreai-w8-v3-encoder=pal4"]) &&
            decoders == ["--coreai-w8-v3-decoder=pal8"] && flag == prefix + "always"
        guard fixedFP8 || joint || encoderControl else {
            throw Failure(message: "Prewarm policy requires an explicit qualified precision trial")
        }
        let modes = arguments.filter { $0.hasPrefix("--coreai-product-mode=") }
        let product = arguments.contains { $0.hasPrefix("--coreai-product-") }
        let encodeOnly = joint && flag == prefix + "always" && modes == ["--coreai-product-mode=staged-gpu-encode"]
        guard !product || modes == ["--coreai-product-mode=staged-gpu"] || encodeOnly else {
            throw Failure(message: "Prewarm experiment requires sequential staged-gpu mode or live Talk")
        }
        return flag == prefix + "once" // Joint once is a LATER, separately reviewed policy experiment.
    }
}
