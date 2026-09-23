import Foundation
import Testing
@testable import MuralCore

struct SpeechPreparationStepTests {
    private enum Failure: Error { case expected }

    @Test func cancellationBeforeStepDoesNotLoad() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await SpeechPreparationStep.run(model: "fixture", component: "decoder", phase: "load") {
                Issue.record("Cancelled work entered the native loader")
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test(arguments: [0, 1, 2]) func cancelledNativeReturnNeverStartsFollowingComponent(cancelAt: Int) async {
        let task = Task {
            var entered: [Int] = []
            do {
                for index in 0..<3 {
                    try await SpeechPreparationStep.run(model: "fixture", component: "\(index)", phase: "prewarm") {
                        entered.append(index)
                        // A non-cooperative native operation can return successfully after Stop.
                        if index == cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
                    }
                }
                Issue.record("Cancellation was lost")
            } catch is CancellationError { }
            catch { Issue.record("Unexpected error: \(error)") }
            #expect(entered == Array(0...cancelAt))
        }
        await task.value
    }

    @Test func nativeBodyStaysOnItsCallingActor() async throws {
        actor Owner {
            func prepare() async throws {
                try await SpeechPreparationStep.run(model: "fixture", component: "decoder", phase: "load") {
                    self.assertIsolated()
                }
            }
        }
        try await Owner().prepare()
    }

    @Test func failureRemainsAnError() async {
        await #expect(throws: Failure.self) {
            try await SpeechPreparationStep.run(model: "fixture", component: "decoder", phase: "load") {
                throw Failure.expected
            }
        }
    }

    @MainActor @Test func cancellationDrainsBeforeReturningAndDoesNotWriteReceipt() async throws {
        let started = AsyncStream<Void>.makeStream()
        let released = AsyncStream<Void>.makeStream()
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let receipt = CoreMLPreparationReceipt(key: .init(model: "fixture", scope: .eager,
            manifestSHA256: "manifest", modelPathSHA256: "path", osBuild: "os", device: "device", computeUnits: ["decoder": 3]),
            file: folder.appending(path: "receipt.json"))
        var returned = false
        let task = Task { @MainActor in
            defer { returned = true }
            try await receipt.prepare(prewarm: {
                try await SpeechPreparationStep.run(model: "fixture", component: "decoder", phase: "prewarm") {
                    // Retain/await this deliberately non-cooperative native-work stand-in.
                    let native = Task { for await _ in released.stream { break } }
                    started.continuation.yield(())
                    await native.value
                }
            }, loadAndValidate: { Issue.record("Cancelled prewarm proceeded to normal loading") })
        }
        for await _ in started.stream { break }
        task.cancel()
        await Task.yield()
        #expect(!returned)
        released.continuation.yield(())
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(returned && receipt.lookup() == .missing)
        started.continuation.finish(); released.continuation.finish()
    }

    @MainActor @Test func stepEventsDescribeCompletedAndCancelledCalls() async throws {
        var events: [SpeechPreparationStep.Event] = []
        try await SpeechPreparationStep.$observe.withValue({ events.append($0) }) {
            try await SpeechPreparationStep.run(model: "fixture", component: "mel", phase: "load") {}
        }
        #expect(events.map(\.outcome) == ["begin", "completed"])
        #expect(events.first?.id == events.last?.id)
        #expect(events.last?.seconds ?? -1 >= 0)
        let task = Task { @MainActor in
            try await SpeechPreparationStep.$observe.withValue({ events.append($0) }) {
                try await SpeechPreparationStep.run(model: "fixture", component: "decoder", phase: "load") {
                    withUnsafeCurrentTask { $0?.cancel() }
                    throw Failure.expected // Cancellation takes precedence over a late SDK error.
                }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(events.map(\.outcome) == ["begin", "completed", "begin", "cancelled"])
    }
}
