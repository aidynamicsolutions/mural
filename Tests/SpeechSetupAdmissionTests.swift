import Foundation
import Testing
@testable import MuralCore

@MainActor struct SpeechSetupAdmissionTests {
    @Test func interruptionPreventsNextComponentWithoutCancellingOuterOwner() async {
        var entered = false
        await SpeechSetupReporting.$admission.withValue({ throw CancellationError() }) {
            await #expect(throws: CancellationError.self) {
                try await SpeechSetupReporting.checkAdmission()
                entered = true
            }
        }
        #expect(!entered && !Task.isCancelled)
    }
    @Test func unrelatedCallersRetainExistingAdmissionPolicy() async throws {
        try await SpeechSetupReporting.checkAdmission()
    }
    @Test func actualRevalidationRemovesPriorProcessLocalCheckmark() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("job.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let control = SpeechSetupControl(store: .init(file: file))
        _ = try control.start(identity: .init(pair: .vietnameseEnglish, preparationContract: "v1", voice: "v1", downloadContract: "v1"))
        try control.complete(.voice)
        try control.enter(.init(.preparingVoice))
        #expect(!control.completed.contains(.voice))
    }
    @Test func foregroundWakeupKeepsPauseUntilTheOwnerReportsDrain() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("job.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let control = SpeechSetupControl(store: .init(file: file))
        _ = try control.start(identity: .init(pair: .vietnameseEnglish, preparationContract: "v1", voice: "v1", downloadContract: "v1"))
        try control.pauseForForeground()
        control.foregroundReturned()
        #expect(control.isLive && control.pauseRequested && control.progress.stage == .draining)
        #expect(throws: SpeechSetupControl.ControlError.self) { try control.validatedInThisProcess() }
        try control.continueAfterDrain()
        #expect(!control.pauseRequested && control.progress.stage == .checking)
    }

}
