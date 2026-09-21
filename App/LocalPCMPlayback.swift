import AVFoundation
import Foundation
import MuralCore

/// Owns no AVAudioSession. LocalConversationEngine remains the half-duplex session owner.
@MainActor final class LocalPCMPlayback {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var requestID: UUID?
    private var completion: CheckedContinuation<Void, Error>?
    private var startMonitor: Task<Void, Never>?

    func play(_ audio: LocalTTSAudio, onStart: @escaping @MainActor (Double) -> Void) async throws {
        try Task.checkCancellation()
        guard requestID == nil else { throw LocalTTSError.busy }
        let id = UUID()
        requestID = id
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion = continuation
                do {
                    try Task.checkCancellation()
                    guard let format = AVAudioFormat(standardFormatWithSampleRate: audio.sampleRate, channels: 1),
                          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.samples.count)),
                          let channel = buffer.floatChannelData?[0] else { throw LocalTTSError.invalidAudio }
                    buffer.frameLength = buffer.frameCapacity
                    audio.samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
                    let engine = AVAudioEngine()
                    let player = AVAudioPlayerNode()
                    self.engine = engine; self.player = player
                    engine.attach(player)
                    // The mixer converts the model rate to the hardware route's rate.
                    try engine.connectNode(player, to: engine.mainMixerNode, format: format)
                    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                        Task { @MainActor [weak self] in self?.finish(id, error: nil) }
                    }
                    engine.prepare()
                    try engine.start()
                    try player.playAudio()
                    startMonitor = Task { [weak self] in
                        let deadline = ProcessInfo.processInfo.systemUptime + 2
                        while !Task.isCancelled, let self, self.requestID == id {
                            if let nodeTime = player.lastRenderTime,
                               let time = player.playerTime(forNodeTime: nodeTime), time.sampleTime > 0 {
                                // Render-clock observation, not proof of acoustic arrival at the ear.
                                onStart(ProcessInfo.processInfo.systemUptime - Double(time.sampleTime) / time.sampleRate)
                                return
                            }
                            if ProcessInfo.processInfo.systemUptime > deadline {
                                self.finish(id, error: PlaybackError.noRender)
                                return
                            }
                            do { try await Task.sleep(for: .milliseconds(5)) } catch { return }
                        }
                    }
                } catch { finish(id, error: error) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, error: CancellationError()) }
        }
    }

    func stop() {
        guard let id = requestID else { return }
        finish(id, error: CancellationError())
    }

    private func finish(_ id: UUID, error: Error?) {
        guard requestID == id else { return }
        requestID = nil // Retire before stop(), which can itself deliver a completion callback.
        startMonitor?.cancel(); startMonitor = nil
        player?.stop(); engine?.stop()
        player = nil; engine = nil
        let pending = completion; completion = nil
        if let error { pending?.resume(throwing: error) } else { pending?.resume() }
    }

    private enum PlaybackError: LocalizedError {
        case noRender
        var errorDescription: String? { "The audio route did not begin rendering. Stop and check your output device." }
    }
}
