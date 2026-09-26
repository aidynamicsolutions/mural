import Foundation

/// A cancellation-safe wakeup for the existing orchestration task, not a task/model owner.
/// A revision closes the signal-before-wait race; tokens isolate late cancellation handlers.
@MainActor public final class SpeechSetupForegroundGate {
    public private(set) var revision: UInt64 = 0
    private var waiter: (id: UUID, continuation: CheckedContinuation<Void, any Error>)?
    public enum GateError: Error { case alreadyWaiting }
    public init() {}

    public func signal() {
        revision &+= 1
        let pending = waiter; waiter = nil
        pending?.continuation.resume()
    }

    public func wait(after observedRevision: UInt64) async throws {
        try Task.checkCancellation()
        guard revision == observedRevision else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else if revision != observedRevision { continuation.resume() }
                else if waiter != nil { continuation.resume(throwing: GateError.alreadyWaiting) }
                else { waiter = (id, continuation) }
            }
            try Task.checkCancellation()
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(id: id) }
        }
    }

    private func cancel(id: UUID) {
        guard waiter?.id == id else { return }
        let pending = waiter; waiter = nil
        pending?.continuation.resume(throwing: CancellationError())
    }
}
