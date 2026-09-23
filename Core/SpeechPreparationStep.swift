import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// A cancellation boundary around one native step, not a way to interrupt that step.
/// The caller retains its resource owner until this function actually returns.
public enum SpeechPreparationStep {
    public struct Event: Codable, Sendable {
        public let id: UUID
        public let model: String
        public let component: String
        public let phase: String
        public let outcome: String
        public let uptime: Double
        public let seconds: Double
    }

    /// Scoped instrumentation for native QA. No global mutable observer or model override.
    @TaskLocal public static var observe: (@MainActor @Sendable (Event) -> Void)?

    public static func run(model: String, component: String, phase: String,
                           isolation: isolated (any Actor)? = #isolation,
                           operation: () async throws -> Void) async throws {
        try Task.checkCancellation()
        let id = UUID(), started = ProcessInfo.processInfo.systemUptime
        func event(_ outcome: String) async {
            let now = ProcessInfo.processInfo.systemUptime
            #if canImport(OSLog)
            Logger(subsystem: "no.william.mural", category: "LocalAudio").notice(
                "speech_preparation_step id=\(id.uuidString, privacy: .public) model=\(model, privacy: .public) component=\(component, privacy: .public) phase=\(phase, privacy: .public) outcome=\(outcome, privacy: .public) seconds=\(now - started, privacy: .public)")
            #endif
            await observe?(Event(id: id, model: model, component: component, phase: phase,
                                 outcome: outcome, uptime: now, seconds: now - started))
        }
        await event("begin")
        do {
            try Task.checkCancellation()
            try await operation()
            try Task.checkCancellation()
        } catch {
            let cancelled = Task.isCancelled || error is CancellationError
            await event(cancelled ? "cancelled" : "failed")
            if cancelled { throw CancellationError() }
            throw error
        }
        await event("completed")
        try Task.checkCancellation()
    }
}
