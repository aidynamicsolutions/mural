import BackgroundTasks
import Foundation
import MuralCore
import Observation
import OSLog
import UIKit

/// Execution-time lease only. The coordinator's existing localTask owns every operation.
/// No native stage is qualified for background execution by this implementation.
@MainActor @Observable final class SpeechSetupContinuation {
    @MainActor private final class Lease {
        let id = UUID()
        let identifier: String
        var task: BGContinuedProcessingTask?
        var ended = false
        var completionIssued = false
        init(prefix: String) { identifier = prefix + "." + UUID().uuidString }
    }
    private var lease: Lease?
    private(set) var isGranted = false
    var onSystemInterruption: (() -> Void)?
    private let logger = Logger(subsystem: "no.william.mural", category: "SpeechSetup")
    private var latest = SpeechSetupProgress(.downloadingSpeech)

    func logCapabilities() {
        let gpu = BGTaskScheduler.supportedResources.contains(.gpu)
        logger.notice("speech_setup event=capability_snapshot gpu_supported=\(gpu, privacy: .public) native_background_enabled=false")
    }

    /// Called only from a foreground, explicitly approved managed-install segment.
    func start() async {
        guard lease == nil, UIApplication.shared.applicationState == .active,
              let bundle = Bundle.main.bundleIdentifier else { return }
        let candidate = Lease(prefix: bundle + ".speech-setup")
        lease = candidate
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: candidate.identifier, using: .main) { [weak self, candidate] task in
            MainActor.assumeIsolated {
                guard let continued = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                // A late delivery cannot attach to a newer job or start any model work.
                guard candidate.task == nil else { return }
                candidate.task = continued
                guard let self, self.lease === candidate, !candidate.ended else {
                    Logger(subsystem: "no.william.mural", category: "SpeechSetup")
                        .notice("speech_setup event=continuation_stale_delivery lease=\(candidate.id.uuidString, privacy: .public)")
                    Self.complete(candidate, success: false)
                    return
                }
                self.isGranted = true
                let token = candidate.id
                continued.expirationHandler = { [weak self] in
                    Task { @MainActor in self?.interrupted(token: token) }
                }
                self.log("continuation_started", id: token)
                self.logger.notice("speech_setup event=background_policy policy=managed_granted")
                self.update(self.latest)
            }
        }
        guard registered else {
            log("continuation_registration_failed", id: candidate.id)
            finish(success: false)
            return
        }
        let request = BGContinuedProcessingTaskRequest(identifier: candidate.identifier,
            title: "Preparing speech for Mural", subtitle: "Downloading speech")
        request.strategy = .fail
        request.requiredResources = [] // CPU/network/file I/O only; no inferred GPU/ANE permission.
        do {
            try await BGTaskScheduler.shared.submitTaskRequest(request)
            guard lease === candidate, !candidate.ended else {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: candidate.identifier)
                return
            }
            log("continuation_submitted", id: candidate.id)
        } catch {
            log("continuation_submission_failed", id: candidate.id)
            if lease === candidate { finish(success: false) } // Foreground setup remains usable.
        }
    }

    func update(_ progress: SpeechSetupProgress) {
        latest = progress
        guard progress.stage.permitsManagedContinuation, let task = lease?.task, isGranted else { return }
        var subtitle = progress.title
        if let bytes = progress.completedBytes, let total = progress.totalBytes {
            subtitle += " - " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                + " of " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            // Download bytes plus the publication boundary. This is work, never remaining time.
            if total < Int64.max {
                task.progress.totalUnitCount = total + 1
                task.progress.completedUnitCount = bytes
            }
        }
        task.updateTitle("Preparing speech for Mural", subtitle: subtitle)
    }

    func finish(success: Bool, needsForeground: Bool = false) {
        guard let current = lease else { return }
        lease = nil; isGranted = false; current.ended = true
        if needsForeground { current.task?.updateTitle("Preparing speech for Mural", subtitle: "Open Mural to finish setup") }
        if current.task == nil {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: current.identifier)
        } else { Self.complete(current, success: success) }
        log("continuation_completed", id: current.id)
    }

    private func interrupted(token: UUID) {
        guard let current = lease, current.id == token else { return }
        log("continuation_system_interrupted", id: token)
        // Revoke the lease first, but persist/cancel the owner BEFORE surrendering execution time.
        lease = nil; isGranted = false; current.ended = true
        onSystemInterruption?() // Apple supplies no reliable cancel-versus-expiration reason.
        Self.complete(current, success: false)
    }

    private static func complete(_ lease: Lease, success: Bool) {
        guard !lease.completionIssued, let task = lease.task else { return }
        lease.completionIssued = true
        task.expirationHandler = nil
        if success { task.progress.completedUnitCount = task.progress.totalUnitCount }
        task.setTaskCompleted(success: success)
    }

    private func log(_ event: String, id: UUID) {
        logger.notice("speech_setup event=\(event, privacy: .public) lease=\(id.uuidString, privacy: .public)")
    }
}
