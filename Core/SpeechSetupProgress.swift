import Foundation

/// Fractions belong to real downloads, never to native preparation or elapsed time.
public struct SpeechSetupProgress: Equatable, Sendable {
    public enum Stage: String, Codable, CaseIterable, Sendable {
        case checking, downloadingSpeech, checkingDownload, checkingVoice, downloadingVoice
        case downloadingVoiceStyle, preparingVoice, checkingSpeech, preparingSpeech
        case checkingDetection, preparingDetection, preparingEncoder, preparingDecoder
        case loadingSpeechModels, validatingSpeech, finalChecks, waitingForForeground, draining, needsResume, ready, cancelled

        public var major: MajorStage? {
            switch self {
            case .checking: .checking
            case .downloadingSpeech: .download
            case .checkingDownload: .verification
            case .checkingVoice, .downloadingVoice, .downloadingVoiceStyle, .preparingVoice: .voice
            case .checkingSpeech, .preparingSpeech, .checkingDetection, .preparingDetection,
                 .preparingEncoder, .preparingDecoder, .loadingSpeechModels, .validatingSpeech: .recognition
            case .finalChecks, .ready: .finalChecks
            case .waitingForForeground, .draining, .needsResume, .cancelled: nil
            }
        }
        public var isDownload: Bool {
            self == .downloadingSpeech || self == .downloadingVoice || self == .downloadingVoiceStyle
        }
        public var permitsManagedContinuation: Bool {
            self == .downloadingSpeech || self == .checkingDownload
        }
    }

    public enum MajorStage: String, Codable, CaseIterable, Sendable {
        case checking, download, verification, voice, recognition, finalChecks
        public var title: String {
            switch self {
            case .checking: "Checking setup"
            case .download: "Downloading speech"
            case .verification: "Checking downloads"
            case .voice: "Preparing voice"
            case .recognition: "Preparing speech recognition"
            case .finalChecks: "Final checks"
            }
        }
        public var completedTitle: String {
            switch self {
            case .checking: "Setup checked"
            case .download: "Speech files downloaded"
            case .verification: "Downloads verified"
            case .voice: "Voice ready"
            case .recognition: "Speech recognition prepared"
            case .finalChecks: "Final checks complete"
            }
        }
    }
    public enum AwayPolicy: String, Sendable { case foregroundRequired, backgroundGranted }

    public let stage: Stage
    public let fraction: Double?
    public let completedBytes: Int64?
    public let totalBytes: Int64?
    public let plannedStages: [MajorStage]
    public let completedStages: [MajorStage]
    public let awayPolicy: AwayPolicy

    public init(_ stage: Stage, fraction: Double? = nil, completedBytes: Int64? = nil, totalBytes: Int64? = nil,
                plannedStages: [MajorStage] = [.checking, .voice, .recognition, .finalChecks],
                completedStages: [MajorStage] = [], awayPolicy: AwayPolicy = .foregroundRequired) {
        self.stage = stage
        self.plannedStages = MajorStage.allCases.filter { plannedStages.contains($0) }
        self.completedStages = self.plannedStages.filter { completedStages.contains($0) }
        // A caller cannot accidentally advertise background native work in this MVP.
        self.awayPolicy = stage.permitsManagedContinuation ? awayPolicy : .foregroundRequired
        if stage.isDownload, let completedBytes, let totalBytes, completedBytes >= 0, totalBytes > 0 {
            self.completedBytes = min(completedBytes, totalBytes); self.totalBytes = totalBytes
            self.fraction = Double(min(completedBytes, totalBytes)) / Double(totalBytes)
        } else {
            self.completedBytes = nil; self.totalBytes = nil
            self.fraction = stage.isDownload ? fraction.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil } : nil
        }
    }

    public var title: String {
        switch stage {
        case .checking: "Checking setup"
        case .downloadingSpeech: "Downloading speech"
        case .checkingDownload: "Checking downloads"
        case .checkingVoice: "Checking your voice"
        case .downloadingVoice: "Downloading Mural’s voice"
        case .downloadingVoiceStyle: "Downloading your chosen voice"
        case .preparingVoice: "Preparing voice"
        case .checkingSpeech: "Checking speech files"
        case .preparingSpeech: "Preparing speech recognition"
        case .checkingDetection: "Checking speech detection"
        case .preparingDetection: "Preparing speech detection"
        case .preparingEncoder: "Preparing encoder"
        case .preparingDecoder: "Preparing decoder"
        case .loadingSpeechModels: "Loading speech models"
        case .validatingSpeech: "Validating speech"
        case .finalChecks: "Final checks"
        case .waitingForForeground: "Open Mural to finish setup"
        case .draining: "Finishing the current step"
        case .needsResume: "Resume setup"
        case .ready: "Ready"
        case .cancelled: "Setup cancelled"
        }
    }

    public var detail: String {
        switch stage {
        case .waitingForForeground:
            return "Speech setup is partly complete. Open Mural to finish preparing speech."
        case .draining:
            return "Finishing the interrupted step safely. Completed work is saved."
        case .needsResume:
            return "Mural will check your retained speech files and completed setup work before continuing."
        case .cancelled:
            return "Speech is finishing its current step. Completed work is kept. Start again when it’s ready."
        case .ready:
            return "Speech has passed this process’s final checks."
        default:
            return awayPolicy == .backgroundGranted
                ? "You can lock your iPhone or switch apps. Mural will keep working when iOS allows. Completed work is saved."
                : "Keep Mural open for this step. Everything already completed is saved if you leave."
        }
    }

    public func presenting(planned: [MajorStage], completed: [MajorStage], away: AwayPolicy) -> Self {
        .init(stage, fraction: fraction, completedBytes: completedBytes, totalBytes: totalBytes,
              plannedStages: planned, completedStages: completed, awayPolicy: away)
    }
}

/// Typed orchestration boundaries supplement the existing diagnostic native-step observer.
/// Emission does not create a task, grant execution time, or assert native readiness.
public enum SpeechSetupReporting {
    public enum Event: Sendable {
        case stage(SpeechSetupProgress.Stage)
        case completed(SpeechSetupProgress.MajorStage)
    }
    @TaskLocal public static var observe: (@MainActor @Sendable (Event) -> Void)?
    @TaskLocal public static var admission: (@MainActor @Sendable () throws -> Void)?
    public static func checkAdmission() async throws {
        try Task.checkCancellation()
        try await admission?()
        try Task.checkCancellation()
    }
    public static func emit(_ event: Event) async {
        guard !Task.isCancelled else { return }
        await observe?(event)
    }
}
