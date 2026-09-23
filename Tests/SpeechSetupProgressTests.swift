import Foundation
import Testing
@testable import MuralCore

struct SpeechSetupProgressTests {
    @Test func percentageBelongsOnlyToItsDownload() {
        for stage: SpeechSetupProgress.Stage in [.checking, .checkingDownload, .checkingVoice, .preparingVoice,
                                                 .checkingSpeech, .preparingSpeech, .cancelled] {
            let progress = SpeechSetupProgress(stage, fraction: 0.9, completedBytes: 90, totalBytes: 100)
            #expect(progress.fraction == nil)
            #expect(progress.completedBytes == nil)
            #expect(progress.totalBytes == nil)
            #expect(!progress.title.isEmpty && !progress.detail.isEmpty)
        }
    }
    @Test func byteProgressIsTruthfulAndBounded() {
        let progress = SpeechSetupProgress(.downloadingSpeech, fraction: 0.9, completedBytes: 25, totalBytes: 100)
        #expect(progress.fraction == 0.25) // Observed bytes take precedence over an estimate.
        #expect(progress.completedBytes == 25 && progress.totalBytes == 100)
        #expect(SpeechSetupProgress(.downloadingSpeech, completedBytes: 101, totalBytes: 100).fraction == 1)
        #expect(SpeechSetupProgress(.downloadingSpeech, completedBytes: 0, totalBytes: 100).fraction == 0)
        #expect(SpeechSetupProgress(.downloadingSpeech, completedBytes: 0, totalBytes: 0).fraction == nil)
        #expect(SpeechSetupProgress(.downloadingSpeech, completedBytes: -1, totalBytes: 100).fraction == nil)
    }
    @Test func voiceProgressDoesNotInventByteCounts() {
        for stage: SpeechSetupProgress.Stage in [.downloadingVoice, .downloadingVoiceStyle] {
            let progress = SpeechSetupProgress(stage, fraction: 0.5)
            #expect(progress.fraction == 0.5)
            #expect(progress.totalBytes == nil && progress.completedBytes == nil)
            #expect(SpeechSetupProgress(stage, fraction: .nan).fraction == nil)
            #expect(SpeechSetupProgress(stage, fraction: .infinity).fraction == nil)
            #expect(SpeechSetupProgress(stage, fraction: -1).fraction == 0)
            #expect(SpeechSetupProgress(stage, fraction: 2).fraction == 1)
        }
    }
    @MainActor @Test func awaitedCatalogFailureNeverLooksInstalled() async {
        let models = LocalSpeechProvisioning()
        models.check(.taiwanMandarinEnglish)
        do {
            try await models.waitForCompletion()
            Issue.record("The empty production catalog must fail closed")
        } catch SpeechPackageError.notPublished {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(!models.isBusy)
        #expect(models.phase == .failed && models.package == nil)
        models.download()
        #expect(!models.isBusy && models.phase == .failed)
    }
    @MainActor @Test func cancelledWaiterCannotContinueToNativePreparation() async {
        let models = LocalSpeechProvisioning()
        let task = Task { @MainActor in
            models.check(.vietnameseEnglish)
            try await models.waitForCompletion()
        }
        task.cancel()
        do {
            try await task.value
            Issue.record("Cancellation must be propagated to the setup owner")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(!models.isBusy && models.phase != .installed)
    }
}
