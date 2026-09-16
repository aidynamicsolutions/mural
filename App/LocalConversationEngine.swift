import AVFoundation
import CryptoKit
import Foundation
import Observation
import OSLog
import FluidAudio
import WhisperKit
#if canImport(CoreAI)
import CoreAI
import CoreML
import ArgmaxCore
#endif

/// Half-duplex local audio owner. The Phase 2 probe exposes ASR without tutor inference.
@MainActor @Observable final class LocalConversationEngine: NSObject, AVSpeechSynthesizerDelegate {
    @ObservationIgnored var onPlayback: ((Double, Double?, Bool) -> Void)?
    private(set) var playbackStartSeconds: Double?
    private(set) var playbackDurationSeconds: Double?
    private(set) var voiceDescription = "English system voice"
    enum ASRState: String {
        case idle = "Prepare speech models", downloading = "Downloading or checking cached assets…"
        case warming = "Warming speech models…", ready = "Ready to record"
        case recording = "Recording", transcribing = "Finalizing speech…", ended = "Stopped", failed = "Speech unavailable"
    }
    enum ASRModel: String, CaseIterable {
        case phoWhisper = "PhoWhisper CS", parakeet = "Parakeet VI–EN", whisper = "Whisper", nemotron = "Nemotron"
    }
    private(set) var asrModel: ASRModel = .phoWhisper
    private var whisper: WhisperRecognizer?
    private var parakeet: VietnameseEnglishRecognizer?
    var recordingLimitSeconds: Int { asrModel == .parakeet ? VietnameseEnglishRecognizer.maxSeconds : 30 }
    private(set) var preparationDetail = ""
    private(set) var asrState: ASRState = .idle
    private(set) var asrText = ""
    private(set) var asrError: String?
    private(set) var asrNotice: String?
    private(set) var capturedSeconds = 0.0
    private(set) var finalizeSeconds: Double?
    private(set) var preparationSeconds: Double?
    private(set) var inputDescription = "Microphone off"
    private var asr: StreamingNemotronMultilingualAsrManager?
    private var asrTask: Task<Void, Never>?
    private var stagedDecoderWarmup: Task<Void, Error>?
    private var limitTask: Task<Void, Never>?
    private var tapInstalled = false
    private var audioEngine: AVAudioEngine?
    private var capture: AsyncThrowingStream<AVReadOnlyAudioPCMBuffer, Error>.Continuation?
    private var generation = UUID()
    private var submittedAt: Double?
    var lastSubmissionTime: Double? { submittedAt }
    private(set) var sendToPlaybackSeconds: Double?
    private var variantDirectory: URL?
    private var ownsAudio = false
    private var audioRelease: Task<Void, Never>?
    var asrBusy: Bool { asrTask != nil }
    var canRecord: Bool { (asr != nil || whisper != nil || parakeet != nil) && asrTask == nil && completion == nil }
    var canPrepare: Bool { !stagedMemoryWarning && asrTask == nil && completion == nil && asr == nil && whisper == nil && parakeet == nil }
    private var stagedMemoryWarning = false
    @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol?
    private let synthesizer = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?
    private var completion: CheckedContinuation<Void, Error>?
    private var requestedAt = 0.0
    private var playbackStartedAt: Double?
    private let logger = Logger(subsystem: "no.william.mural", category: "LocalAudio")

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        #if canImport(CoreAI)
        if PhoWhisperStagedEncoder.enabled {
            memoryWarningObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name("UIApplicationDidReceiveMemoryWarningNotification"),
                object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.stagedMemoryWarning = true
                        self.stop()
                        self.asrState = .failed
                        self.asrError = "Speech stopped after a memory warning. End this session and use the default build; no automatic fallback was attempted."
                        self.logger.fault("asr_staged_memory_warning stopped=true")
                    }
                }
        }
        #endif
    }

    deinit {
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
    }

    func speak(_ text: String) async throws {
        try Task.checkCancellation()
        guard completion == nil else { throw SpeechError.busy }
        guard let voice = AVSpeechSynthesisVoice(language: "en-US") else { throw SpeechError.noVoice }
        guard asrTask == nil else { throw SpeechError.busy }
        try await activateAudio(category: .playback)
        let current = AVSpeechUtterance(string: text)
        current.voice = voice
        voiceDescription = "\(voice.name) (\(voice.language))"
        utterance = current
        playbackStartSeconds = nil; playbackDurationSeconds = nil; playbackStartedAt = nil
        requestedAt = ProcessInfo.processInfo.systemUptime
        let requestTime = requestedAt
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion = continuation
                synthesizer.speak(current)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.requestedAt == requestTime else { return }
                self?.stop()
            }
        }
    }

    func stop() {
        generation = UUID()
        limitTask?.cancel(); limitTask = nil
        stopCapture()
        capture?.finish(throwing: CancellationError()); capture = nil
        asrTask?.cancel()
        stagedDecoderWarmup?.cancel()
        asr = nil; whisper = nil; parakeet = nil
        asrState = .ended
        asrNotice = "Stopped. Prepare speech models again to restart."
        if utterance != nil, let start = playbackStartedAt {
            let end = ProcessInfo.processInfo.systemUptime
            playbackDurationSeconds = end - start
            onPlayback?(start, end, false)
        }
        utterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        let pending = completion; completion = nil
        pending?.resume(throwing: CancellationError())
        releaseAudio()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let time = ProcessInfo.processInfo.systemUptime
        Task { @MainActor [weak self] in
            guard let self, self.utterance === utterance else { return }
            self.playbackStartedAt = time
            self.onPlayback?(time, nil, false)
            self.playbackStartSeconds = time - self.requestedAt
            self.sendToPlaybackSeconds = self.submittedAt.map { time - $0 }
            if let gap = self.sendToPlaybackSeconds {
                self.logger.notice("local_audio_started send_to_audio_seconds=\(gap, privacy: .public)")
            }
            self.logger.notice("tts_started startup_seconds=\(time - self.requestedAt, privacy: .public)")
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let time = ProcessInfo.processInfo.systemUptime
        Task { @MainActor [weak self] in
            guard let self, self.utterance === utterance else { return }
            self.playbackDurationSeconds = self.playbackStartedAt.map { time - $0 }
            if let start = self.playbackStartedAt { self.onPlayback?(start, time, true) }
            self.logger.notice("tts_finished")
            self.utterance = nil
            let pending = self.completion; self.completion = nil
            self.releaseAudio()
            self.startStagedDecoderPrewarmIfNeeded()
            pending?.resume()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.utterance === utterance else { return }
            self.stop()
        }
    }

    private func startStagedDecoderPrewarmIfNeeded() {
        #if canImport(CoreAI)
        guard PhoWhisperStagedEncoder.enabled, stagedDecoderWarmup == nil, let whisper else { return }
        stagedDecoderWarmup = Task { try await whisper.prewarmStagedDecoder() }
        #endif
    }

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

    /// Await the existing single ASR owner, including its defer cleanup, before TTS.
    func prepareConversation() async throws {
        try Task.checkCancellation()
        if let warmup = stagedDecoderWarmup {
            warmup.cancel()
            _ = await warmup.result
            stagedDecoderWarmup = nil
            try Task.checkCancellation()
        }
        guard !stagedMemoryWarning else {
            throw CaptureError.operation(asrError ?? "Speech is disabled after a memory warning. Use the default build.")
        }
        guard canPrepare else { throw SpeechError.busy }
        selectASR(.phoWhisper)
        submittedAt = nil; sendToPlaybackSeconds = nil
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
        guard !asrBusy, completion == nil, model != asrModel else { return }
        stop() // Release weights, never delete either model's cached assets.
        asrModel = model; asrState = .idle
        asrText = ""; asrError = nil; asrNotice = nil
        preparationDetail = ""
        preparationSeconds = nil; finalizeSeconds = nil; capturedSeconds = 0
        inputDescription = "Microphone off"
    }

    func prepareASR(repairDownload: Bool = false) {
        guard canPrepare else { return }
        let previousWarmup = stagedDecoderWarmup
        previousWarmup?.cancel()
        let token = UUID(); generation = token
        let selected = asrModel
        asrError = nil; asrNotice = nil; preparationSeconds = nil; preparationDetail = ""; asrState = .downloading
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
                let directory: URL
                switch selected {
                case .phoWhisper:
                    VietnameseEnglishRecognizer.logMemory(stage: "asset-verification-begin", model: "phowhisper-cs-fp16-v1")
                    directory = try await WhisperRecognizer.localPhoWhisperDirectory()
                    VietnameseEnglishRecognizer.logMemory(stage: "asset-verification-end", model: "phowhisper-cs-fp16-v1")
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
                let loadingStarted = ProcessInfo.processInfo.systemUptime
                switch selected {
                case .parakeet:
                    let recognizer = VietnameseEnglishRecognizer()
                    try await recognizer.prepare(directory: directory)
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    self.parakeet = recognizer
                case .whisper, .phoWhisper:
                    let recognizer = WhisperRecognizer(phoWhisper: selected == .phoWhisper)
                    let timing = try await recognizer.prepare(directory: directory)
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    self.whisper = recognizer
                    #if canImport(CoreAI)
                    if selected == .phoWhisper, PhoWhisperStagedEncoder.enabled {
                        self.preparationDetail += " · Experimental Core AI GPU: models load after Send, release after each turn."
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
                    ? "PhoWhisper CS could not be prepared. Report this error rather than retrying repeatedly. Its development-only assets must be installed from this Mac; there is no download source. (\(error.localizedDescription))"
                    : "Speech models could not be prepared. Connect to Wi-Fi and try Prepare again. If cached assets are incomplete, use Repair download. (\(error.localizedDescription))"
                self.asrState = .failed
                self.logger.error("asr_preparation_failed model=\(selected.rawValue, privacy: .public)")
            }
        }
    }

    func record() {
        guard canRecord else { return }
        let manager = asr, whisper = whisper, parakeet = parakeet
        let decoderWarmup = stagedDecoderWarmup
        let limit = recordingLimitSeconds
        let model = asrModel.rawValue
        let token = UUID(); generation = token
        asrText = ""; asrError = nil; asrNotice = nil; finalizeSeconds = nil; submittedAt = nil; capturedSeconds = 0
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
                self.limitTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(limit)) } catch { return }
                    guard let self, self.generation == token, self.asrState == .recording else { return }
                    self.asrNotice = "\(limit)-second limit reached. Your turn was sent automatically."
                    self.finishRecording()
                }
                let result = try await Self.transcribe(stream, manager: manager, whisper: whisper,
                    decoderWarmup: decoderWarmup, parakeet: parakeet, limitSeconds: limit,
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
                self.asrText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.capturedSeconds = result.seconds
                self.finalizeSeconds = self.submittedAt.map { ProcessInfo.processInfo.systemUptime - $0 } ?? result.finalizeSeconds
                if self.asrText.isEmpty { self.asrNotice = "No speech recognized. Try another recording." }
                self.asrState = .ready
                self.logger.notice("asr_final model=\(model, privacy: .public) captured_seconds=\(result.seconds, privacy: .public) finish_seconds=\(result.finalizeSeconds, privacy: .public) send_to_final_seconds=\(self.finalizeSeconds!, privacy: .public) characters=\(self.asrText.count, privacy: .public)")
            } catch {
                self.stopCapture(); self.capture?.finish(); self.capture = nil
                await manager?.reset()
                self.releaseAudio()
                guard self.generation == token, !Task.isCancelled else { return }
                self.asrError = error.localizedDescription; self.asrState = .failed
                self.logger.error("asr_turn_failed")
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
    }

    private func stopCapture() {
        limitTask?.cancel(); limitTask = nil
        if let engine = audioEngine {
            engine.stop()
            if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
            audioEngine = nil
        }
    }

    private struct Recognition: Sendable { let text: String; let seconds: Double; let finalizeSeconds: Double }

    @concurrent private static func transcribe(_ stream: AsyncThrowingStream<AVReadOnlyAudioPCMBuffer, Error>,
        manager: StreamingNemotronMultilingualAsrManager?, whisper: WhisperRecognizer?,
        decoderWarmup: Task<Void, Error>?, parakeet: VietnameseEnglishRecognizer?, limitSeconds: Int,
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
        } else if let parakeet {
            turnSamples.append(contentsOf: tail)
            text = try await parakeet.transcribe(turnSamples)
        } else if let whisper {
            turnSamples.append(contentsOf: tail)
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
            text = try await whisper.transcribe(turnSamples)
        } else { throw SpeechError.busy }
        let finalizeSeconds = ProcessInfo.processInfo.systemUptime - started
        try Task.checkCancellation()
        return Recognition(text: text, seconds: Double(frames) / sampleRate, finalizeSeconds: finalizeSeconds)
    }

    private nonisolated static func convert(_ converter: AVAudioConverter, input: AVAudioPCMBuffer?,
        target: AVAudioFormat, capacity: AVAudioFrameCount) throws -> [Float] {
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw CaptureError.format }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if let input, !supplied { supplied = true; state.pointee = .haveData; return input }
            state.pointee = input == nil ? .endOfStream : .noDataNow
            return nil
        }
        if let error { throw error }
        guard status != .error, let data = output.floatChannelData else { throw CaptureError.format }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }

    /// One ordered task owns this actor. Stop drops ownership but never unloads a
    /// decoder during inference; the task retains it until cancellation completes.
    private actor WhisperRecognizer {
        private static let variant = "openai_whisper-large-v3-v20240930_626MB"
        private static let revision = "0f63a7800b00dd0226abd051b906c246e1907482"
        private var kit: WhisperKit?
        private let phoWhisper: Bool
        private var suppressedTokens: [Int] = []
        private var inferenceCount = 0
        #if canImport(CoreAI)
        private var stagedDirectory: URL?
        private var stagedEncoderURL: URL?
        private var stagedTokenizer: (any WhisperTokenizer)?
        private var usesStagedEncoder: Bool { phoWhisper && PhoWhisperStagedEncoder.enabled }
        #endif

        init(phoWhisper: Bool = false) { self.phoWhisper = phoWhisper }

        private struct LocalManifest: Decodable {
            struct File: Decodable { let bytes: Int; let sha256: String }
            let files: [String: File]
        }

        @concurrent static func localPhoWhisperDirectory() async throws -> URL {
            var folder = URL.applicationSupportDirectory.appending(path: "PhoWhisperCS/phowhisper-cs-fp16-v1", directoryHint: .isDirectory)
            let manifest = try Data(contentsOf: folder.appending(path: "manifest.json"))
            guard SHA256.hash(data: manifest).map({ String(format: "%02x", $0) }).joined() ==
                "7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52" else { throw CocoaError(.fileReadCorruptFile) }
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

        func prepare(directory: URL) async throws -> (prewarm: Double, load: Double) {
            #if canImport(CoreAI)
            if usesStagedEncoder {
                let started = ProcessInfo.processInfo.systemUptime
                let encoderURL = try await PhoWhisperStagedEncoder.verifiedURL()
                struct Generation: Decodable { let suppress_tokens: [Int] }
                suppressedTokens = try JSONDecoder().decode(Generation.self,
                    from: Data(contentsOf: directory.appending(path: "generation_config.json"))).suppress_tokens
                let tokenizer = try await PhoWhisperTokenizer.load(from: directory)
                try Task.checkCancellation()
                stagedDirectory = directory; stagedEncoderURL = encoderURL; stagedTokenizer = tokenizer
                inferenceCount = 0
                Logger(subsystem: "no.william.mural", category: "LocalAudio")
                    .notice("asr_staged_prepared backend=coreai-gpu models_deferred_until_send=true")
                return (0, ProcessInfo.processInfo.systemUptime - started)
            }
            #endif
            // Only Prepare can fetch missing tokenizer assets. Loaded inference uses
            // in-memory weights/tokenizer; no hosted endpoint or automatic fallback.
            let config = WhisperKitConfig(modelFolder: directory.path,
                tokenizerFolder: phoWhisper ? directory : URL.applicationSupportDirectory.appending(path: "WhisperKit"),
                computeOptions: phoWhisper ? ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine) : nil,
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
            try Task.checkCancellation()
            let started = ProcessInfo.processInfo.systemUptime
            try await loaded.prewarmModels()
            try Task.checkCancellation()
            let prewarm = ProcessInfo.processInfo.systemUptime - started
            Logger(subsystem: "no.william.mural", category: "LocalAudio").notice("asr_prewarmed model=\(self.phoWhisper ? "phowhisper-cs-fp16-v1" : "whisper", privacy: .public) seconds=\(prewarm, privacy: .public)")
            let loadStarted = ProcessInfo.processInfo.systemUptime
            try await loaded.loadModels()
            try Task.checkCancellation()
            if phoWhisper {
                guard loaded.textDecoder.logitsSize == 51865, loaded.audioEncoder.embedSize == 1280 else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                VietnameseEnglishRecognizer.logMemory(stage: "loaded", model: "phowhisper-cs-fp16-v1")
            }
            let loadSeconds = ProcessInfo.processInfo.systemUptime - loadStarted
            if phoWhisper {
                let timing = loaded.currentTimings
                // SDK specialization fields measure prewarm load calls, not proven
                // per-op compilation or placement. Core AI trace disambiguates them.
                logger.notice("asr_model_timing model=phowhisper-cs-fp16-v1 prewarm_seconds=\(prewarm, privacy: .public) load_seconds=\(loadSeconds, privacy: .public) encoder_specialization_seconds=\(timing.encoderSpecializationTime, privacy: .public) decoder_specialization_seconds=\(timing.decoderSpecializationTime, privacy: .public) encoder_load_seconds=\(timing.encoderLoadTime, privacy: .public) decoder_load_seconds=\(timing.decoderLoadTime, privacy: .public)")
            }
            kit = loaded
            inferenceCount = 0
            return (prewarm, loadSeconds + localTokenizerSeconds)
        }

        #if canImport(CoreAI)
        func prewarmStagedDecoder() async throws {
            guard usesStagedEncoder, let directory = stagedDirectory else { return }
            let logger = Logger(subsystem: "no.william.mural", category: "LocalAudio")
            let started = ProcessInfo.processInfo.systemUptime
            logger.notice("asr_staged_decoder_speculative_begin")
            let decoder = TextDecoder()
            defer { decoder.unloadModel() }
            do {
                try Task.checkCancellation()
                try await decoder.loadModel(at: directory.appending(path: "TextDecoder.mlmodelc"),
                                            computeUnits: .cpuAndNeuralEngine, prewarmMode: true)
                try Task.checkCancellation()
                logger.notice("asr_staged_decoder_speculative_complete seconds=\(ProcessInfo.processInfo.systemUptime - started, privacy: .public)")
            } catch is CancellationError {
                logger.notice("asr_staged_decoder_speculative_cancelled")
                throw CancellationError()
            } catch {
                logger.error("asr_staged_decoder_speculative_failed")
                throw error
            }
        }

        private func transcribeStaged(_ samples: [Float]) async throws -> String {
            guard let directory = stagedDirectory, let encoderURL = stagedEncoderURL,
                  let tokenizer = stagedTokenizer else { throw SpeechError.busy }
            guard samples.count <= 480_000, samples.allSatisfy(\.isFinite) else { throw CaptureError.tooLong }
            guard !samples.isEmpty else { return "" }
            let logger = Logger(subsystem: "no.william.mural", category: "LocalAudio")
            inferenceCount += 1
            let turn = inferenceCount, started = ProcessInfo.processInfo.systemUptime
            logger.notice("asr_staged_turn_begin turn=\(turn, privacy: .public)")
            // Always await the scope, even when Stop cancels its outer owner.
            let encoderTask = Task { try await PhoWhisperStagedEncoder.encode(samples, support: directory, encoderURL: encoderURL) }
            let encoded = try await encoderTask.value
            try Task.checkCancellation()
            logger.notice("asr_staged_encoder_released turn=\(turn, privacy: .public)")
            let loaded = try await WhisperKit(WhisperKitConfig(modelFolder: directory.path,
                tokenizerFolder: directory,
                computeOptions: ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine,
                                                    textDecoderCompute: .cpuAndNeuralEngine),
                audioEncoder: PhoWhisperStagedEncoder.Replay(encoded),
                verbose: false, prewarm: false, load: false, download: false))
            loaded.tokenizer = tokenizer
            loaded.textDecoder.isModelMultilingual = true
            do {
                try Task.checkCancellation()
                let prewarmStarted = ProcessInfo.processInfo.systemUptime
                try await loaded.prewarmModels()
                try Task.checkCancellation()
                logger.notice("asr_staged_decoder_send_prewarm_complete turn=\(turn, privacy: .public) seconds=\(ProcessInfo.processInfo.systemUptime - prewarmStarted, privacy: .public)")
                let loadStarted = ProcessInfo.processInfo.systemUptime
                try await loaded.loadModels()
                try Task.checkCancellation()
                logger.notice("asr_staged_decoder_send_load_complete turn=\(turn, privacy: .public) seconds=\(ProcessInfo.processInfo.systemUptime - loadStarted, privacy: .public)")
                guard loaded.textDecoder.logitsSize == 51865 else { throw CocoaError(.fileReadCorruptFile) }
                let decodeStarted = ProcessInfo.processInfo.systemUptime
                let results = try await loaded.transcribe(audioArray: samples, decodeOptions: decodingOptions())
                try Task.checkCancellation()
                logger.notice("asr_staged_decoder_decode_complete turn=\(turn, privacy: .public) seconds=\(ProcessInfo.processInfo.systemUptime - decodeStarted, privacy: .public)")
                let unloadStarted = ProcessInfo.processInfo.systemUptime
                await loaded.unloadModels()
                loaded.tokenizer = nil
                logger.notice("asr_staged_decoder_unload_complete turn=\(turn, privacy: .public) seconds=\(ProcessInfo.processInfo.systemUptime - unloadStarted, privacy: .public)")
                logger.notice("asr_staged_turn_complete turn=\(turn, privacy: .public) end_to_end_seconds=\(ProcessInfo.processInfo.systemUptime - started, privacy: .public)")
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
                // turn dropping. Silence hallucination is accepted for MVP and deferred, not fixed.
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
    static var enabled: Bool {
        #if MURAL_COREAI_TALK
        true
        #elseif DEBUG
        ProcessInfo.processInfo.arguments.contains("--coreai-talk-gpu")
        #else
        false
        #endif
    }

    @concurrent static func verifiedURL() async throws -> URL {
        guard AIModel.deviceArchitectureName == "h18p" else {
            throw Failure("The experimental speech encoder is not qualified for this device. Use the default build.")
        }
        let url = URL.applicationSupportDirectory.appending(path:
            "CoreAI/PhoWhisperGPU/phowhisper-cs-fp16-v1.encoder.h18p.aimodelc")
        guard try fingerprint(url) == "f783c9b539d90a589e1449e514599e240ce6036b3bab6c298858e49bba112829" else {
            throw Failure("The experimental speech encoder is missing or changed. Use the default build; no automatic repair was attempted.")
        }
        return url
    }

    struct Encoded: Sendable {
        let hidden: [Float16]
        let melHash: String
    }

    @concurrent static func encode(_ samples: [Float], support: URL, encoderURL: URL) async throws -> Encoded {
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
        guard let model = try AIModelCache.default.model(for: encoderURL, options: options) else {
            throw Failure("The experimental speech encoder cache is unavailable. Use the default build; no automatic specialization or fallback was attempted.")
        }
        guard let descriptor = model.functionDescriptor(for: "main"),
              case .ndArray(let inputDescriptor) = descriptor.inputDescriptor(of: "input_features"),
              inputDescriptor.scalarType == .float16, inputDescriptor.shape == [1, 80, 3000],
              let function = try model.loadFunction(named: "main") else {
            throw Failure("The experimental speech encoder could not load its frozen FP16 function.")
        }
        var input = NDArray(descriptor: inputDescriptor)
        do {
            var view = input.mutableView(as: Float16.self)
            view.copyElements(fromContentsOf: values.map(Float16.init))
        }
        var outputs = try await function.run(inputs: ["input_features": input])
        guard let hidden = outputs.remove("encoder_hidden_states")?.ndArray else {
            throw Failure("The speech encoder produced no embeddings.")
        }
        return Encoded(hidden: try copyEncoderOutput(hidden),
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

    static func fingerprint(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw Failure("Symlinks are not diagnostic assets.") }
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
}
#endif
