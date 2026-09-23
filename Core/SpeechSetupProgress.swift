import Foundation

/// User-facing progress is separate from native diagnostic text. A download percentage
/// describes only that download, never the unmeasurable native preparation that follows.
public struct SpeechSetupProgress: Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        case checking, downloadingSpeech, checkingDownload, checkingVoice, downloadingVoice
        case downloadingVoiceStyle, preparingVoice, checkingSpeech, preparingSpeech, cancelled
    }
    public let stage: Stage
    public let fraction: Double?
    public let completedBytes: Int64?
    public let totalBytes: Int64?

    public init(_ stage: Stage, fraction: Double? = nil, completedBytes: Int64? = nil, totalBytes: Int64? = nil) {
        self.stage = stage
        let downloading = stage == .downloadingSpeech || stage == .downloadingVoice || stage == .downloadingVoiceStyle
        if downloading, let completedBytes, let totalBytes, completedBytes >= 0, totalBytes > 0 {
            self.completedBytes = min(completedBytes, totalBytes); self.totalBytes = totalBytes
            self.fraction = Double(min(completedBytes, totalBytes)) / Double(totalBytes)
        } else {
            self.completedBytes = nil; self.totalBytes = nil
            self.fraction = downloading ? fraction.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil } : nil
        }
    }

    public var title: String {
        switch stage {
        case .checking: "Checking what you need…"
        case .downloadingSpeech: "Downloading speech…"
        case .checkingDownload: "Checking your download…"
        case .checkingVoice: "Checking your voice…"
        case .downloadingVoice: "Downloading Mural’s voice…"
        case .downloadingVoiceStyle: "Downloading your chosen voice…"
        case .preparingVoice: "Getting your voice ready…"
        case .checkingSpeech: "Checking speech files…"
        case .preparingSpeech: "Getting speech ready…"
        case .cancelled: "Setup cancelled"
        }
    }
    public var detail: String {
        switch stage {
        case .downloadingSpeech, .downloadingVoice, .downloadingVoiceStyle:
            "Keep Mural open. Downloaded files are kept for later."
        case .preparingSpeech, .preparingVoice:
            "First setup can take a few minutes. Later starts are usually quicker."
        case .cancelled:
            "Speech is finishing its current step. You can browse Words or choose your next language. Start again when it’s ready."
        default:
            "Getting ready for your conversation."
        }
    }
}
