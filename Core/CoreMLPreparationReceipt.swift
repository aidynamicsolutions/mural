import Foundation
#if canImport(CryptoKit) && canImport(Darwin)
import CryptoKit
import Darwin
#endif
#if canImport(OSLog)
import OSLog
#endif

/// A record of successful preparation, NOT ownership of Core ML's private cache.
/// Call only after the existing manifest and full asset verification have passed.
public struct CoreMLPreparationReceipt: Sendable {
    public enum Scope: String, Codable, Sendable { case eager, stagedDecoder }
    public enum Mode: Sendable { case automatic, sessionOnly, always }
    public enum Lookup: String, Sendable { case hit, missing, incompatible, unreadable, bypassed }

    public struct Key: Codable, Equatable, Sendable {
        public let model: String
        public let scope: Scope
        public let manifestSHA256: String
        public let modelPathSHA256: String
        public let osBuild: String
        public let device: String
        public let computeUnits: [String: Int]
        // Bump when the pinned runtime or this preparation contract changes.
        public let policyVersion: Int

        public init(model: String, scope: Scope, manifestSHA256: String,
                    modelPathSHA256: String, osBuild: String, device: String,
                    computeUnits: [String: Int], policyVersion: Int = 1) {
            self.model = model; self.scope = scope; self.manifestSHA256 = manifestSHA256
            self.modelPathSHA256 = modelPathSHA256; self.osBuild = osBuild
            self.device = device; self.computeUnits = computeUnits; self.policyVersion = policyVersion
        }
    }

    public struct Timing: Sendable {
        public let prewarm: Double
        public let load: Double
        public let didPrewarm: Bool
        public let receiptWritten: Bool
    }

    private struct Record: Codable {
        let schema: Int
        let key: Key
        let completedAt: Date
    }
    private let key: Key
    private let file: URL

    public init(key: Key, file: URL) { self.key = key; self.file = file }

    public func lookup() -> Lookup {
        guard FileManager.default.fileExists(atPath: file.path) else { return .missing }
        do {
            let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: file))
            return record.schema == 1 && record.key == key ? .hit : .incompatible
        } catch { return .unreadable }
    }

    /// Explicit qualification trials do not read or write production receipts.
    public func needsPrewarm(mode: Mode = .automatic, alreadyPrewarmed: Bool = false) -> Bool {
        let status = mode == .automatic ? lookup() : .bypassed
        event("prewarm_lookup", status: status.rawValue)
        return mode == .always || (!alreadyPrewarmed && status != .hit)
    }

    /// Native work stays on the caller's actor and under the existing task owner.
    /// `loadAndValidate` must perform the normal load AND all model contract checks.
    public func prepare(mode: Mode = .automatic, alreadyPrewarmed: Bool = false,
                        isolation: isolated (any Actor)? = #isolation,
                        prewarm: () async throws -> Void,
                        loadAndValidate: () async throws -> Void) async throws -> Timing {
        try Task.checkCancellation()
        let status = mode == .automatic ? lookup() : .bypassed
        event("receipt", status: status.rawValue)
        let shouldPrewarm = mode == .always || (!alreadyPrewarmed && status != .hit)
        var prewarmSeconds = 0.0
        if shouldPrewarm {
            let started = ProcessInfo.processInfo.systemUptime
            event("prewarm_begin")
            do {
                try await prewarm()
                try Task.checkCancellation()
            } catch {
                event("prewarm_failed", status: error is CancellationError ? "cancelled" : "error", seconds: ProcessInfo.processInfo.systemUptime - started)
                throw error
            }
            prewarmSeconds = ProcessInfo.processInfo.systemUptime - started
            event("prewarm_end", seconds: prewarmSeconds)
        } else { event("prewarm_skipped", status: alreadyPrewarmed ? "session" : "receipt") }
        try Task.checkCancellation()
        let started = ProcessInfo.processInfo.systemUptime
        event("load_begin")
        do {
            try await loadAndValidate()
            try Task.checkCancellation()
        } catch {
            event("load_failed", status: error is CancellationError ? "cancelled" : "error", seconds: ProcessInfo.processInfo.systemUptime - started)
            throw error
        }
        let loadSeconds = ProcessInfo.processInfo.systemUptime - started
        event("load_end", seconds: loadSeconds)
        var written = false
        if mode == .automatic && status != .hit {
            do {
                let parent = file.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                #if canImport(Darwin)
                var excluded = parent
                var resources = URLResourceValues(); resources.isExcludedFromBackup = true
                try excluded.setResourceValues(resources)
                #endif
                let data = try JSONEncoder().encode(Record(schema: 1, key: key, completedAt: Date()))
                try Task.checkCancellation()
                // No suspension between the final cancellation check and atomic commit.
                try data.write(to: file, options: .atomic)
                written = true
                event("receipt_written")
            } catch is CancellationError { throw CancellationError() }
            catch {
                // Disk-full/permission errors must not make a successfully loaded model unusable.
                // Leave a miss; never delete models or retry preparation automatically.
                event("receipt_write_failed")
            }
        }
        return Timing(prewarm: prewarmSeconds, load: loadSeconds,
                      didPrewarm: shouldPrewarm, receiptWritten: written)
    }

    private func event(_ phase: String, status: String = "none", seconds: Double = 0) {
        #if canImport(OSLog)
        Logger(subsystem: "no.william.mural", category: "LocalAudio").notice(
            "coreml_preparation model=\(key.model, privacy: .public) scope=\(key.scope.rawValue, privacy: .public) phase=\(phase, privacy: .public) status=\(status, privacy: .public) seconds=\(seconds, privacy: .public)")
        #endif
    }

    #if canImport(CryptoKit) && canImport(Darwin)
    /// The manifest has already been checked against its independent pin and all files hashed.
    /// Reading that small manifest here does not replace or weaken those checks.
    public init(verifiedDirectory directory: URL, scope: Scope, computeUnits: [String: Int]) throws {
        let started = ProcessInfo.processInfo.systemUptime
        func digest(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        let manifest = try Data(contentsOf: directory.appending(path: "manifest.json"))
        let key = Key(model: directory.lastPathComponent, scope: scope,
                      manifestSHA256: digest(manifest),
                      modelPathSHA256: digest(Data(directory.standardizedFileURL.path.utf8)),
                      osBuild: try Self.systemValue("kern.osversion"),
                      device: try Self.systemValue("hw.machine"), computeUnits: computeUnits)
        let file = URL.applicationSupportDirectory
            .appending(path: "Mural/CoreMLPreparation", directoryHint: .isDirectory)
            .appending(path: "\(key.model)-\(scope.rawValue).json")
        self.init(key: key, file: file)
        event("key", seconds: ProcessInfo.processInfo.systemUptime - started)
    }

    private static func systemValue(_ name: String) throws -> String {
        var count = 0
        guard sysctlbyname(name, nil, &count, nil, 0) == 0, count > 0 else {
            throw CocoaError(.featureUnsupported)
        }
        var bytes = [CChar](repeating: 0, count: count)
        guard sysctlbyname(name, &bytes, &count, nil, 0) == 0 else {
            throw CocoaError(.featureUnsupported)
        }
        return String(decoding: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    #endif
}
