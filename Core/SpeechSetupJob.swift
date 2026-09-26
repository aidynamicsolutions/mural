import Foundation

/// An orchestration hint, never proof that a native model is loaded or safe to record.
public struct SpeechSetupJob: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public struct Identity: Codable, Equatable, Sendable {
        public let pair: LocalSpeechPair
        public let preparationContract: String
        public let voice: String
        public let downloadContract: String

        public init(pair: LocalSpeechPair, preparationContract: String, voice: String,
                    downloadContract: String) {
            self.pair = pair
            self.preparationContract = preparationContract
            self.voice = voice
            self.downloadContract = downloadContract
        }

        fileprivate var isValid: Bool {
            [preparationContract, voice, downloadContract].allSatisfy {
                !$0.isEmpty && $0.utf8.count <= 2048 && !$0.contains("\n")
            }
        }
    }

    public enum Status: String, Codable, Sendable {
        case running, waitingForForeground, needsResume, cancelled, complete
    }
    public enum Boundary: String, Codable, Sendable {
        case preflight, recognitionPublished, voicePrepared, recognitionPrepared, processValidated
    }
    public enum Interruption: String, Codable, Sendable {
        case foregroundRequired, processLost, systemInterrupted, userCancelled, failed
    }

    public let schema: Int
    public let id: UUID
    public let identity: Identity
    public let createdAt: Date
    public private(set) var updatedAt: Date
    public private(set) var status: Status
    public private(set) var currentStage: SpeechSetupProgress.Stage
    public private(set) var lastCompletedBoundary: Boundary?
    public private(set) var downloadsApproved: Bool
    public private(set) var interruption: Interruption?

    public init(identity: Identity, id: UUID = UUID(), now: Date = .now) {
        schema = Self.schemaVersion
        self.id = id; self.identity = identity
        createdAt = now; updatedAt = now
        status = .running; currentStage = .checking
        lastCompletedBoundary = nil; downloadsApproved = false; interruption = nil
    }

    public mutating func update(status: Status? = nil, stage: SpeechSetupProgress.Stage? = nil,
                                completed: Boundary? = nil, approveDownloads: Bool = false,
                                interruption: Interruption? = nil, now: Date = .now) {
        if let status { self.status = status }
        if let stage { currentStage = stage }
        if let completed { lastCompletedBoundary = completed }
        if approveDownloads { downloadsApproved = true }
        self.interruption = interruption
        updatedAt = max(createdAt, now)
    }

    /// Cold restoration never carries process residency, checkmarks, or automatic execution.
    public func restored(now: Date = .now) -> Self {
        guard status != .cancelled else { return self }
        var result = self
        result.update(status: .needsResume, stage: .needsResume,
                      interruption: .processLost, now: now)
        return result
    }

    fileprivate var isValid: Bool {
        schema == Self.schemaVersion && identity.isValid &&
        createdAt.timeIntervalSinceReferenceDate.isFinite &&
        updatedAt.timeIntervalSinceReferenceDate.isFinite && updatedAt >= createdAt
    }
}

/// Small atomic metadata only. It never reads, removes, repairs, or declares models ready.
/// Serialize access on the existing setup owner's actor. Filesystem failures are not swallowed.
public struct SpeechSetupJobStore: Sendable {
    public static let maximumBytes = 16_384
    public let file: URL
    public init(file: URL) { self.file = file }

    public enum Load: Equatable, Sendable {
        case missing, invalid, unsupportedVersion, incompatible
        case job(SpeechSetupJob)
    }
    public enum StoreError: Error { case invalidRecord, unsafeFile, oversized }
    private struct Envelope: Decodable { let schema: Int }

    /// A protection/permission/I/O failure throws, so a temporarily unreadable job cannot
    /// silently be replaced by a new one. Bad JSON and future versions fail closed separately.
    public func load(expected identity: SpeechSetupJob.Identity? = nil) throws -> Load {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: file) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return .missing }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError { return .missing }
        defer { try? handle.close() }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw StoreError.unsafeFile }
        var data = Data()
        while data.count <= Self.maximumBytes {
            guard let chunk = try handle.read(upToCount: Self.maximumBytes + 1 - data.count), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard data.count <= Self.maximumBytes else { return .invalid }
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { return .invalid }
        guard envelope.schema == SpeechSetupJob.schemaVersion else { return .unsupportedVersion }
        guard let job = try? decoder.decode(SpeechSetupJob.self, from: data), job.isValid else { return .invalid }
        if let identity, identity != job.identity { return .incompatible }
        return .job(job)
    }

    public func save(_ job: SpeechSetupJob) throws {
        guard job.isValid else { throw StoreError.invalidRecord }
        let data = try JSONEncoder().encode(job)
        guard data.count <= Self.maximumBytes else { throw StoreError.oversized }
        let parent = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        #if canImport(Darwin)
        var excluded = parent
        var resources = URLResourceValues(); resources.isExcludedFromBackup = true
        try excluded.setResourceValues(resources)
        #endif
        // Do not change model/file protection policy to obtain lock-screen execution.
        try data.write(to: file, options: .atomic)
    }

    /// Clear only the job that actually entered conversation; never delete a newer job.
    public func clear(id: UUID) throws {
        guard case .job(let current) = try load(), current.id == id else { return }
        try FileManager.default.removeItem(at: file)
    }
}
