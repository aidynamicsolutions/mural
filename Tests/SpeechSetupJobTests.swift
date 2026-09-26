import Foundation
import Testing
@testable import MuralCore

struct SpeechSetupJobTests {
    private func identity(_ contract: String = "qualified-v1") -> SpeechSetupJob.Identity {
        .init(pair: .vietnameseEnglish, preparationContract: contract,
              voice: "voice-a", downloadContract: "reviewed-package-a")
    }
    private func fixture() throws -> SpeechSetupJobStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return SpeechSetupJobStore(file: folder.appendingPathComponent("job.json"))
    }
    private func clean(_ store: SpeechSetupJobStore) {
        // Only a unique test-owned temporary directory; never app data or model caches.
        try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent())
    }

    @Test func atomicRoundTripRetainsIdentityAndApprovalButNotReadiness() throws {
        let store = try fixture(); defer { clean(store) }
        #expect(try store.load() == .missing)
        var job = SpeechSetupJob(identity: identity())
        job.update(stage: .preparingDecoder, completed: .recognitionPublished, approveDownloads: true)
        try store.save(job)
        #expect(try store.load(expected: identity()) == .job(job))
        let data = try Data(contentsOf: store.file)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["modelResident"] == nil && json["nativePrepared"] == nil)
        let restored = job.restored()
        #expect(restored.status == .needsResume && restored.currentStage == .needsResume)
        #expect(restored.downloadsApproved && restored.lastCompletedBoundary == .recognitionPublished)
        #expect(restored.id == job.id && restored.interruption == .processLost)
    }

    @Test func everyColdNonCancelledStateRequiresExplicitResume() {
        for status: SpeechSetupJob.Status in [.running, .waitingForForeground, .needsResume, .complete] {
            var job = SpeechSetupJob(identity: identity())
            job.update(status: status, completed: .processValidated)
            #expect(job.restored().status == .needsResume)
            #expect(job.restored().currentStage != .ready)
        }
    }

    @Test func explicitCancelSurvivesRelaunchWithoutAutomaticResume() throws {
        let store = try fixture(); defer { clean(store) }
        var job = SpeechSetupJob(identity: identity())
        job.update(status: .cancelled, interruption: .userCancelled)
        try store.save(job)
        guard case .job(let loaded) = try store.load() else { Issue.record("Missing cancelled job"); return }
        #expect(loaded.restored() == job)
    }

    @Test func pairVoiceModelAndDownloadContractInvalidateApproval() throws {
        let store = try fixture(); defer { clean(store) }
        var job = SpeechSetupJob(identity: identity())
        job.update(approveDownloads: true)
        try store.save(job)
        let candidates: [SpeechSetupJob.Identity] = [
            identity("qualified-v2"),
            .init(pair: .taiwanMandarinEnglish, preparationContract: "qualified-v1", voice: "voice-a", downloadContract: "reviewed-package-a"),
            .init(pair: .vietnameseEnglish, preparationContract: "qualified-v1", voice: "voice-b", downloadContract: "reviewed-package-a"),
            .init(pair: .vietnameseEnglish, preparationContract: "qualified-v1", voice: "voice-a", downloadContract: "reviewed-package-b")
        ]
        for candidate in candidates { #expect(try store.load(expected: candidate) == .incompatible) }
        #expect(try store.load(expected: identity()) == .job(job)) // Invalidation never deletes assets or the hint.
    }

    @Test func oldCompatibleJobDoesNotExpireByAge() throws {
        let store = try fixture(); defer { clean(store) }
        let job = SpeechSetupJob(identity: identity(), now: Date(timeIntervalSince1970: 1))
        try store.save(job)
        #expect(try store.load(expected: identity()) == .job(job))
    }

    @Test func futureSchemaIsRejectedBeforeCurrentPayloadDecode() throws {
        let store = try fixture(); defer { clean(store) }
        try Data(#"{"schema":999,"identity":"future-shape"}"#.utf8).write(to: store.file)
        #expect(try store.load() == .unsupportedVersion)
    }

    @Test func corruptTruncatedAndOversizedRecordsFailClosed() throws {
        let store = try fixture(); defer { clean(store) }
        for data in [Data(), Data("{\"schema\":1,".utf8), Data(repeating: 32, count: SpeechSetupJobStore.maximumBytes + 1)] {
            try data.write(to: store.file)
            #expect(try store.load() == .invalid)
        }
    }

    @Test func impossibleTimestampFailsClosed() throws {
        let store = try fixture(); defer { clean(store) }
        try store.save(SpeechSetupJob(identity: identity()))
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.file)) as? [String: Any])
        json["createdAt"] = 1000; json["updatedAt"] = 999
        try JSONSerialization.data(withJSONObject: json).write(to: store.file)
        #expect(try store.load() == .invalid)
    }

    @Test func failedWriteCannotEraseEarlierCheckpoint() throws {
        let store = try fixture(); defer { clean(store) }
        let old = SpeechSetupJob(identity: identity())
        try store.save(old)
        let data = try Data(contentsOf: store.file)
        let invalid = SpeechSetupJob(identity: identity(""))
        #expect(throws: SpeechSetupJobStore.StoreError.self) { try store.save(invalid) }
        #expect(try Data(contentsOf: store.file) == data)
        #expect(try store.load() == .job(old))
    }

    @Test func filesystemErrorsAreNotSwallowed() throws {
        let store = try fixture(); defer { clean(store) }
        let blocker = store.file.deletingLastPathComponent().appendingPathComponent("not-a-directory")
        try Data().write(to: blocker)
        let blocked = SpeechSetupJobStore(file: blocker.appendingPathComponent("job.json"))
        #expect(throws: (any Error).self) { try blocked.save(SpeechSetupJob(identity: identity())) }
    }

    @Test func lateClearCannotEraseNewerJob() throws {
        let store = try fixture(); defer { clean(store) }
        let old = SpeechSetupJob(identity: identity())
        let new = SpeechSetupJob(identity: identity())
        try store.save(new)
        try store.clear(id: old.id)
        #expect(try store.load() == .job(new))
        try store.clear(id: new.id)
        #expect(try store.load() == .missing)
    }

    @Test func recordDoesNotInventoryOrDeleteRetainedResources() throws {
        let store = try fixture(); defer { clean(store) }
        let asset = store.file.deletingLastPathComponent().appendingPathComponent("retained-package")
        let bytes = Data([1, 2, 3]); try bytes.write(to: asset)
        var job = SpeechSetupJob(identity: identity())
        job.update(status: .complete, completed: .processValidated)
        try store.save(job)
        _ = try store.load(expected: identity("different"))
        try store.clear(id: job.id)
        #expect(try Data(contentsOf: asset) == bytes)
    }
}

struct ResumableSpeechProgressTests {
    @Test func everyNonDownloadStageRejectsFractionsAndBytes() {
        for stage in SpeechSetupProgress.Stage.allCases where !stage.isDownload {
            let progress = SpeechSetupProgress(stage, fraction: 0.7, completedBytes: 70, totalBytes: 100)
            #expect(progress.fraction == nil && progress.completedBytes == nil && progress.totalBytes == nil)
            #expect(!progress.title.isEmpty && !progress.detail.isEmpty)
        }
    }
    @Test func backgroundClaimRequiresBothAnEligibleStageAndAGrant() {
        for stage in SpeechSetupProgress.Stage.allCases {
            let supplied = SpeechSetupProgress(stage, awayPolicy: .backgroundGranted)
            #expect((supplied.awayPolicy == .backgroundGranted) == stage.permitsManagedContinuation)
            #expect(SpeechSetupProgress(stage).awayPolicy == .foregroundRequired)
        }
    }
    @Test func bytesOverrideSDKFractionAndInvalidFractionsDisappear() {
        #expect(SpeechSetupProgress(.downloadingSpeech, fraction: 0.9, completedBytes: 25, totalBytes: 100).fraction == 0.25)
        #expect(SpeechSetupProgress(.downloadingVoice, fraction: .nan).fraction == nil)
        #expect(SpeechSetupProgress(.downloadingVoice, fraction: .infinity).fraction == nil)
        #expect(SpeechSetupProgress(.downloadingVoice, fraction: 2).fraction == 1)
        #expect(SpeechSetupProgress(.downloadingSpeech, completedBytes: -1, totalBytes: 100).fraction == nil)
    }
    @Test func checklistDoesNotInferCompletionFromCurrentStage() {
        let progress = SpeechSetupProgress(.preparingDecoder)
        #expect(progress.completedStages.isEmpty)
        #expect(!progress.plannedStages.contains(.download))
        let rendered = progress.presenting(planned: [.checking, .voice, .recognition, .finalChecks],
                                          completed: [.voice, .download], away: .backgroundGranted)
        #expect(rendered.completedStages == [.voice])
        #expect(rendered.awayPolicy == .foregroundRequired)
    }
}

@MainActor struct SpeechSetupForegroundGateTests {
    @Test func signalBeforeWaitIsNotLost() async throws {
        let gate = SpeechSetupForegroundGate(); let old = gate.revision
        gate.signal()
        try await gate.wait(after: old)
    }
    @Test func cancellationBeforeWaitThrows() async {
        let gate = SpeechSetupForegroundGate()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await gate.wait(after: gate.revision)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
    @Test func cancellationDuringWaitDoesNotRequireForegroundReturn() async throws {
        let gate = SpeechSetupForegroundGate(), entered = SpeechSetupForegroundGate()
        let revision = gate.revision, enteredRevision = entered.revision
        let task = Task { entered.signal(); try await gate.wait(after: revision) }
        try await entered.wait(after: enteredRevision)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let nextRevision = gate.revision
        let next = Task { try await gate.wait(after: nextRevision) }
        gate.signal(); gate.signal()
        try await next.value
    }
    @Test func aSecondWaiterIsRejectedRatherThanReplacingTheOwner() async throws {
        let gate = SpeechSetupForegroundGate(), entered = SpeechSetupForegroundGate()
        let revision = gate.revision, enteredRevision = entered.revision
        let owner = Task { entered.signal(); try await gate.wait(after: revision) }
        try await entered.wait(after: enteredRevision)
        await #expect(throws: SpeechSetupForegroundGate.GateError.self) { try await gate.wait(after: revision) }
        gate.signal(); try await owner.value
    }
    @Test func repeatedForegroundSignalsDoNotCompleteTwice() async throws {
        let gate = SpeechSetupForegroundGate(); let revision = gate.revision
        let task = Task { try await gate.wait(after: revision) }
        gate.signal(); gate.signal(); gate.signal()
        try await task.value
        #expect(gate.revision == 3)
    }
}

@MainActor struct SpeechSetupControlTests {
    private var identity: SpeechSetupJob.Identity {
        .init(pair: .vietnameseEnglish, preparationContract: "qualified", voice: "voice", downloadContract: "reviewed")
    }
    private func store() -> SpeechSetupJobStore {
        .init(file: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("job.json"))
    }
    @Test func foregroundReturnKeepsJobAndApprovalButCannotStartASecondOwner() throws {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()) }
        let state = SpeechSetupControl(store: store)
        let id = try state.start(identity: identity)
        try state.approveDownloads()
        try state.complete(.download)
        try state.complete(.verification, boundary: .recognitionPublished)
        try state.pauseForForeground()
        state.wakeup.signal() // Returning does not create or finish native work.
        #expect(state.isLive && state.pauseRequested)
        #expect(throws: SpeechSetupControl.ControlError.self) { _ = try state.start(identity: identity) }
        try state.continueAfterDrain()
        #expect(state.job?.id == id && state.job?.downloadsApproved == true)
        #expect(state.completed.contains(.verification))
        #expect(state.job?.status == .running && state.progress.stage == .checking)
    }
    @Test func coldRestoreDoesNotCopyLiveStateOrCompletedChecklist() throws {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()) }
        let old = SpeechSetupControl(store: store)
        _ = try old.start(identity: identity)
        try old.complete(.recognition, boundary: .recognitionPrepared)
        let fresh = SpeechSetupControl(store: store)
        try fresh.restore()
        #expect(!fresh.isLive && fresh.completed.isEmpty && fresh.offersResume(for: identity))
        #expect(throws: SpeechSetupControl.ControlError.self) { try fresh.continueAfterDrain() }
    }
    @Test func systemInterruptionNeedsExplicitResumeEvenInSameProcess() throws {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()) }
        let state = SpeechSetupControl(store: store)
        _ = try state.start(identity: identity)
        try state.interrupt(.systemInterrupted)
        state.wakeup.signal()
        #expect(!state.isLive && state.offersResume(for: identity))
        #expect(throws: SpeechSetupControl.ControlError.self) { try state.continueAfterDrain() }
    }
    @Test func cancelRevokesLiveIntentBeforeAnUnwritableCheckpoint() throws {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()) }
        let state = SpeechSetupControl(store: store)
        _ = try state.start(identity: identity)
        // A directory at the record path is a deterministic write failure in this test-owned folder.
        try FileManager.default.removeItem(at: store.file)
        try FileManager.default.createDirectory(at: store.file, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try state.interrupt(.userCancelled) }
        #expect(!state.isLive && state.job?.status == .cancelled)
        #expect(!state.offersResume(for: identity))
    }
    @Test func inventoryPlanIsRecomputedEvenAfterApprovalAndBoundaryHints() throws {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()) }
        let state = SpeechSetupControl(store: store)
        _ = try state.start(identity: identity)
        try state.approveDownloads()
        try state.pauseForForeground(); try state.continueAfterDrain()
        state.setPlan(needsRecognitionDownload: true) // Actual missing inventory remains authoritative.
        #expect(state.planned.contains(.download) && state.completed.isEmpty)
        state.setPlan(needsRecognitionDownload: false)
        #expect(!state.planned.contains(.download))
    }
    @Test func staleProgressAfterPauseOrCancellationCannotClaimCompletion() throws {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()) }
        let state = SpeechSetupControl(store: store)
        _ = try state.start(identity: identity)
        try state.pauseForForeground()
        try state.enter(.init(.preparingDecoder)); try state.complete(.recognition)
        #expect(state.progress.stage == .waitingForForeground && state.completed.isEmpty)
        #expect(throws: SpeechSetupControl.ControlError.self) { try state.validatedInThisProcess() }
        try state.interrupt(.userCancelled)
        try state.enter(.init(.ready)); try state.complete(.finalChecks)
        #expect(state.progress.stage == .cancelled && state.completed.isEmpty)
    }
    @Test func duplicateAndBackwardProgressCannotUndoCompletedStages() throws {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()) }
        let state = SpeechSetupControl(store: store)
        _ = try state.start(identity: identity)
        try state.complete(.checking, boundary: .preflight)
        try state.enter(.init(.checking))
        #expect(state.completed.contains(.checking))

        try state.enter(.init(.preparingVoice))
        try state.complete(.voice)
        try state.enter(.init(.preparingEncoder))
        try state.enter(.init(.preparingDecoder)) // Native component order is allowed to vary.
        try state.enter(.init(.preparingSpeech)) // Broad parent update must not roll back detail.
        try state.enter(.init(.preparingVoice)) // Nor may a late earlier-stage event.

        #expect(state.progress.stage == .preparingDecoder)
        #expect(state.completed.contains(.checking) && state.completed.contains(.voice))
    }
    @Test func drainResumeReopensOnlyStagesThatAreActuallyRevalidated() throws {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()) }
        let state = SpeechSetupControl(store: store)
        _ = try state.start(identity: identity)
        try state.complete(.checking, boundary: .preflight)
        try state.complete(.voice, boundary: .voicePrepared)
        try state.pauseForForeground()
        try state.continueAfterDrain()

        #expect(!state.completed.contains(.checking))
        #expect(state.completed.contains(.voice))
        try state.enter(.init(.preparingVoice))
        #expect(!state.completed.contains(.voice))
    }
}
