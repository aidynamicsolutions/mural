import Foundation
#if canImport(Darwin)
import Observation
#endif
#if canImport(OSLog)
import OSLog
#endif

/// Durable intent and presentation for the existing setup task. Never owns native work.
/// The app must retain its current task/admission gates until every child has drained.
#if canImport(Darwin)
@Observable
#endif
@MainActor public final class SpeechSetupControl {
    public private(set) var job: SpeechSetupJob?
    public private(set) var isLive = false
    public private(set) var pauseRequested = false
    public private(set) var progress = SpeechSetupProgress(.checking)
    public private(set) var planned: [SpeechSetupProgress.MajorStage] = [.checking, .voice, .recognition, .finalChecks]
    public private(set) var completed: [SpeechSetupProgress.MajorStage] = []
    public let wakeup = SpeechSetupForegroundGate()
    private let store: SpeechSetupJobStore
    private var didRestore = false
    public enum ControlError: Error { case alreadyRunning, noLiveJob }

    public init(store: SpeechSetupJobStore) { self.store = store }

    public func restore() throws {
        guard !didRestore, !isLive else { return }
        switch try store.load() {
        case .job(let retained):
            job = retained.restored()
            if retained.status != .cancelled { progress = .init(.needsResume) }
            log("job_restored")
        case .missing: break
        case .invalid, .unsupportedVersion, .incompatible: log("job_invalidated")
        }
        // Do not cache a protection/I/O failure; foreground or an explicit retry may read it.
        didRestore = true
    }

    public func offersResume(for identity: SpeechSetupJob.Identity) -> Bool {
        !isLive && job?.identity == identity && job?.status == .needsResume
    }

    @discardableResult public func start(identity: SpeechSetupJob.Identity) throws -> UUID {
        guard !isLive else { throw ControlError.alreadyRunning }
        try restore()
        var next: SpeechSetupJob
        if let retained = job, retained.identity == identity, retained.status != .cancelled {
            next = retained
            next.update(status: .running, stage: .checking)
        } else { next = SpeechSetupJob(identity: identity) }
        try store.save(next) // Intent is durable before the caller admits expensive work.
        job = next; isLive = true; pauseRequested = false
        planned = [.checking, .voice, .recognition, .finalChecks]; completed = []
        progress = .init(.checking)
        log("job_started")
        return next.id
    }

    public func setPlan(needsRecognitionDownload: Bool) {
        let showDownload = needsRecognitionDownload || completed.contains(.download) || completed.contains(.verification)
        planned = SpeechSetupProgress.MajorStage.allCases.filter {
            showDownload || ($0 != .download && $0 != .verification)
        }
    }

    public func approveDownloads() throws {
        try change(approveDownloads: true)
        log("downloads_approved")
    }

    @discardableResult public func enter(_ observed: SpeechSetupProgress) throws -> Bool {
        guard isLive, !pauseRequested else { return false }
        if let next = observed.stage.major {
            if let current = progress.stage.major {
                let stages = SpeechSetupProgress.MajorStage.allCases
                guard let currentOrder = stages.firstIndex(of: current),
                      let nextOrder = stages.firstIndex(of: next) else { return false }
                guard nextOrder >= currentOrder else { return false }
                if nextOrder == currentOrder {
                    guard !completed.contains(next),
                          detailOrder(observed.stage) >= detailOrder(progress.stage) else { return false }
                } else {
                    completed.removeAll { $0 == next }
                }
            } else {
                completed.removeAll { $0 == next }
            }
        }
        if progress.stage != observed.stage {
            try change(stage: observed.stage)
            log("stage_enter", stage: observed.stage)
        }
        progress = observed
        return true
    }

    private func detailOrder(_ stage: SpeechSetupProgress.Stage) -> Int {
        switch stage.major {
        case .voice:
            switch stage {
            case .checkingVoice: 0
            case .downloadingVoice: 1
            case .downloadingVoiceStyle: 2
            case .preparingVoice: 3
            default: 0
            }
        case .recognition:
            switch stage {
            case .checkingSpeech: 0
            case .preparingSpeech: 1
            case .checkingDetection: 2
            case .preparingDetection: 3
            case .preparingEncoder, .preparingDecoder, .loadingSpeechModels: 4
            case .validatingSpeech: 5
            default: 0
            }
        default: 0
        }
    }

    public func complete(_ stage: SpeechSetupProgress.MajorStage,
                         boundary: SpeechSetupJob.Boundary? = nil) throws {
        guard isLive, !pauseRequested else { return }
        if let boundary { try change(completed: boundary) }
        if !completed.contains(stage) { completed.append(stage) }
        log("stage_complete", stage: progress.stage)
    }

    /// Call before requesting child cancellation. Foreground only wakes the SAME owner.
    public func pauseForForeground() throws {
        guard isLive else { return }
        try change(status: .waitingForForeground, stage: .waitingForForeground,
                   interruption: .foregroundRequired)
        pauseRequested = true; progress = .init(.waitingForForeground)
        log("waiting_for_foreground")
    }

    public func foregroundReturned() {
        if isLive, pauseRequested { progress = .init(.draining) }
        wakeup.signal() // Not authority to clear pause or admit another owner.
    }

    /// The caller must first await native drain and verify actual foreground state.
    /// This cannot start or replace a task, restore native residency, or reopen admission.
    public func continueAfterDrain() throws {
        guard isLive else { throw ControlError.noLiveJob }
        try change(status: .running, stage: .checking)
        pauseRequested = false
        completed.removeAll { $0 == .checking }
        progress = .init(.checking)
        // Prior process-local observations remain visible; actual inventory/preparation reruns.
        log("same_owner_continued")
    }

    /// Revoke live intent even when a checkpoint write fails. Never auto-resume a Cancel.
    public func interrupt(_ reason: SpeechSetupJob.Interruption) throws {
        isLive = false; pauseRequested = false; wakeup.signal()
        guard var next = job else { return }
        let cancelled = reason == .userCancelled
        next.update(status: cancelled ? .cancelled : .needsResume,
                    stage: cancelled ? .cancelled : .needsResume, interruption: reason)
        job = next; progress = .init(next.currentStage)
        try store.save(next)
        log(cancelled ? "job_cancelled" : "job_interrupted")
    }

    public func validatedInThisProcess() throws {
        guard isLive, !pauseRequested else { throw ControlError.noLiveJob }
        try change(status: .complete, stage: .ready, completed: .processValidated)
        log("process_validated")
    }

    public func enteredConversation() throws {
        guard let job else { return }
        try store.clear(id: job.id)
        log("job_cleared")
        self.job = nil; isLive = false; pauseRequested = false
    }

    private func change(status: SpeechSetupJob.Status? = nil, stage: SpeechSetupProgress.Stage? = nil,
                        completed: SpeechSetupJob.Boundary? = nil, approveDownloads: Bool = false,
                        interruption: SpeechSetupJob.Interruption? = nil) throws {
        guard var next = job else { throw ControlError.noLiveJob }
        next.update(status: status, stage: stage, completed: completed,
                    approveDownloads: approveDownloads, interruption: interruption)
        do { try store.save(next) }
        catch { log("checkpoint_failed"); throw error }
        job = next
        log("checkpoint_saved")
    }

    private func log(_ event: String, stage: SpeechSetupProgress.Stage? = nil) {
        #if canImport(OSLog)
        let id = job?.id.uuidString ?? "none", value = (stage ?? job?.currentStage)?.rawValue ?? "none"
        Logger(subsystem: "no.william.mural", category: "SpeechSetup")
            .notice("speech_setup event=\(event, privacy: .public) job=\(id, privacy: .public) stage=\(value, privacy: .public)")
        #endif
    }
}
