#if canImport(CryptoKit) && canImport(Darwin)
import CryptoKit
import Darwin
import Foundation
import Observation

/// One foreground transfer owner. Background/cancel checkpoints remain on disk; a new
/// instance resumes from actual file lengths and rehashes every file before publication.
@MainActor @Observable public final class LocalSpeechProvisioning {
    public enum Phase: String, Sendable { case idle, checking, offered, downloading, verifying, installed, cancelling, paused, failed }
    public private(set) var phase: Phase = .idle { didSet { reportSetupProgress() } }
    public private(set) var package: SpeechPackage?
    public private(set) var completedBytes: Int64 = 0 { didSet { reportSetupProgress() } }
    /// Observation only; publication, range validation, pins and hashing remain unchanged.
    public var onSetupProgress: (@MainActor (SpeechSetupProgress) -> Void)?
    private func reportSetupProgress() {
        switch phase {
        case .checking: onSetupProgress?(.init(.checking))
        case .downloading: onSetupProgress?(.init(.downloadingSpeech, completedBytes: completedBytes, totalBytes: package?.downloadBytes))
        case .verifying: onSetupProgress?(.init(.checkingDownload))
        default: break
        }
    }
    public private(set) var availableBytes: Int64 = 0
    public private(set) var error: String?
    private var worker: Task<Void, Never>?
    private var failure: (any Error)?
    private var offered: (ReviewedSpeechPackage, Data)?
    public var isBusy: Bool { worker != nil }
    public init() {}

    public func check(_ pair: LocalSpeechPair) {
        guard worker == nil else { return }
        error = nil; failure = nil; package = nil; offered = nil; completedBytes = 0; phase = .checking
        worker = Task {
            defer { worker = nil }
            do {
                let entry = try SpeechPackageCatalog.entry(for: pair)
                let data = try await SpeechHTTP.fetch(entry.manifestURL, entry: entry,
                    maximumBytes: SpeechPackage.maximumManifestBytes)
                try Task.checkCancellation()
                guard Self.digest(data) == entry.manifestSHA256 else { throw SpeechPackageError.integrity }
                let manifest = try SpeechPackage.decode(data)
                guard manifest.id == entry.id, manifest.pair == pair else { throw SpeechPackageError.invalidManifest }
                guard manifest.supports(hardware: try Self.hardware(), osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion) else {
                    throw SpeechPackageError.incompatible
                }
                try Task.checkCancellation()
                availableBytes = try Self.freeBytes()
                package = manifest; offered = (entry, data); phase = .offered
            } catch { finish(error) }
        }
    }
    public func download() {
        guard worker == nil, let package, let (entry, data) = offered else { return }
        error = nil; failure = nil; phase = .downloading
        worker = Task {
            defer { worker = nil }
            do {
                try await Self.install(package, data: data, entry: entry) { phase, bytes in
                    self.phase = phase; self.completedBytes = bytes
                }
                try Task.checkCancellation()
                phase = .installed
            } catch { finish(error) }
        }
    }
    public func cancel() {
        guard let worker else { return }
        phase = .cancelling
        worker.cancel() // Admission remains closed until the task returns.
    }
    /// Await the same transfer owner from Talk. Cancellation reaches the worker, but
    /// neither caller nor UI can admit another operation until the worker has returned.
    public func waitForCompletion() async throws {
        if let worker {
            await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        }
        try Task.checkCancellation()
        if phase == .paused { throw CancellationError() }
        if let failure { throw failure }
    }
    private func finish(_ failure: Error) {
        self.failure = failure
        if failure is CancellationError || Task.isCancelled { phase = .paused; error = nil }
        else { phase = .failed; error = failure.localizedDescription }
    }

    public nonisolated static var root: URL {
        URL.applicationSupportDirectory.appending(path: "Mural/SpeechModels", directoryHint: .isDirectory)
    }
    private struct Active: Codable { let id: String; let manifestSHA256: String }
    private nonisolated static func activeFile(_ pair: LocalSpeechPair) -> URL {
        root.appending(path: "active-\(pair.rawValue).json")
    }
    private nonisolated static func version(_ entry: ReviewedSpeechPackage) -> String { "\(entry.id)-\(entry.manifestSHA256)" }

    /// Resolves only a pinned, atomically published managed package. The recognizer still
    /// performs its own manifest, per-file verification and native contract validation.
    public nonisolated static func installedDirectory(for pair: LocalSpeechPair, component: String) throws -> URL? {
        guard component == "support" || component == "encoder" else { throw SpeechPackageError.unsafePath }
        let pointer = activeFile(pair)
        guard FileManager.default.fileExists(atPath: pointer.path) else { return nil }
        try noSymlinks(pointer)
        let active = try JSONDecoder().decode(Active.self, from: boundedFile(pointer, maximum: 4096))
        guard let entry = SpeechPackageCatalog.entries.first(where: {
            $0.id == active.id && $0.pair == pair && $0.manifestSHA256 == active.manifestSHA256
        }) else { throw SpeechPackageError.notPublished }
        try entry.validate()
        let directory = root.appending(path: "packages/\(version(entry))", directoryHint: .isDirectory)
        let manifestURL = directory.appending(path: "package.json")
        try noSymlinks(manifestURL)
        let data = try boundedFile(manifestURL, maximum: SpeechPackage.maximumManifestBytes)
        guard digest(data) == entry.manifestSHA256 else { throw SpeechPackageError.integrity }
        let package = try SpeechPackage.decode(data)
        guard package.id == entry.id, package.pair == pair,
              package.supports(hardware: try hardware(), osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion) else {
            throw SpeechPackageError.incompatible
        }
        let result = directory.appending(path: component, directoryHint: .isDirectory)
        try noSymlinks(result)
        return result
    }

    /// Explicit managed-storage action only. Caller must first stop/drain all model owners.
    /// Legacy/developer paths, receipts, settings and learning records are outside this root.
    public func removeManagedDownloads(for pair: LocalSpeechPair) throws {
        guard worker == nil else { throw SpeechPackageError.download("Finish cancelling the download first.") }
        let manager = FileManager.default
        let pointer = Self.activeFile(pair)
        if manager.fileExists(atPath: pointer.path) { try Self.noSymlinks(pointer); try manager.removeItem(at: pointer) }
        for entry in SpeechPackageCatalog.entries where entry.pair == pair {
            try entry.validate()
            for name in ["packages", ".downloads"] {
                let directory = Self.root.appending(path: "\(name)/\(Self.version(entry))")
                if manager.fileExists(atPath: directory.path) {
                    try Self.noSymlinks(directory); try manager.removeItem(at: directory)
                }
            }
        }
        phase = .idle; error = nil; failure = nil; package = nil; offered = nil
    }

    @concurrent private static func install(_ manifest: SpeechPackage, data: Data, entry: ReviewedSpeechPackage,
        progress: @escaping @MainActor @Sendable (Phase, Int64) -> Void) async throws {
        try entry.validate(); try manifest.validate()
        guard digest(data) == entry.manifestSHA256, try SpeechPackage.decode(data) == manifest else {
            throw SpeechPackageError.integrity
        }
        try await installValidatedPackage(files: manifest.files, data: data, entry: entry, pair: manifest.pair,
            specializationReserveBytes: manifest.specializationReserveBytes, root: root, base: .applicationSupportDirectory,
            availableBytes: { try Self.freeBytes() }, progress: progress)
    }

    /// Transaction core shared by the validated production path and disposable filesystem tests.
    /// Callers must validate the package metadata before supplying its file plan.
    @concurrent static func installValidatedPackage(files: [SpeechPackage.File], data: Data,
        entry: ReviewedSpeechPackage, pair: LocalSpeechPair, specializationReserveBytes: Int64,
        root: URL, base: URL, sessionConfiguration: URLSessionConfiguration = .ephemeral,
        availableBytes: @escaping @Sendable () throws -> Int64 = { try LocalSpeechProvisioning.freeBytes() },
        beforePointerPublication: @escaping @Sendable () throws -> Void = {},
        progress: @escaping @MainActor @Sendable (Phase, Int64) -> Void = { _, _ in }) async throws {
        try entry.validate()
        guard pair == entry.pair, digest(data) == entry.manifestSHA256 else { throw SpeechPackageError.integrity }
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try noSymlinks(root, base: base)
        var excluded = root; var resources = URLResourceValues(); resources.isExcludedFromBackup = true
        try excluded.setResourceValues(resources)
        let staging = root.appending(path: ".downloads/\(version(entry))", directoryHint: .isDirectory)
        let final = root.appending(path: "packages/\(version(entry))", directoryHint: .isDirectory)
        try noSymlinks(staging, base: base); try noSymlinks(final, base: base)
        // A prior force-quit may have published the immutable package but not its active pointer.
        if manager.fileExists(atPath: final.path) {
            try verifyFiles(files, at: final, base: base)
            // Repair only our metadata after every package file passed verification.
            // A force-quit must not leave an active pointer to a missing/corrupt marker.
            try Task.checkCancellation()
            try data.write(to: final.appending(path: "package.json"), options: .atomic)
        } else {
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
            var complete: Int64 = 0
            var missing = try missingBytes(files, at: staging, base: base)
            for file in files {
                try Task.checkCancellation()
                let target = staging.appending(path: file.path)
                try noSymlinks(target, base: base)
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !manager.fileExists(atPath: target.path) {
                    guard manager.createFile(atPath: target.path, contents: nil) else {
                        throw SpeechPackageError.download("Unable to create the download file. Check available storage, then Retry.")
                    }
                }
                let values = try target.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, let size = values.fileSize else { throw SpeechPackageError.unsafePath }
                var offset = Int64(size)
                guard offset <= file.bytes else { throw SpeechPackageError.integrity }
                // Count all partial files, including later ones retained across a process restart.
                let required = missing + Int64(data.count) + SpeechPackage.chunkBytes + specializationReserveBytes
                let available = try availableBytes()
                guard available >= required else { throw SpeechPackageError.storage(required: required, available: available) }
                let handle = try FileHandle(forWritingTo: target)
                do {
                    try handle.seek(toOffset: UInt64(offset))
                    while offset < file.bytes {
                        try Task.checkCancellation()
                        let remainingRequired = missing + Int64(data.count) + SpeechPackage.chunkBytes + specializationReserveBytes
                        let nowAvailable = try availableBytes()
                        guard nowAvailable >= remainingRequired else {
                            throw SpeechPackageError.storage(required: remainingRequired, available: nowAvailable)
                        }
                        let count = min(SpeechPackage.chunkBytes, file.bytes - offset)
                        let url = entry.filesURL.appending(path: file.path)
                        let block = try await SpeechHTTP.fetch(url, entry: entry, maximumBytes: Int(count),
                            range: (offset, count, file.bytes), configuration: sessionConfiguration)
                        try Task.checkCancellation()
                        // Only append a complete, exact HTTP range. On a kill during write, the
                        // actual surviving file length is the next offset; full SHA-256 is authoritative.
                        try handle.write(contentsOf: block)
                        try handle.synchronize()
                        offset += Int64(block.count)
                        missing -= Int64(block.count)
                        await progress(.downloading, complete + offset)
                    }
                    try handle.close()
                } catch { try? handle.close(); throw error }
                do { try verify(file, at: staging, base: base) }
                catch {
                    // Only this unpublished corrupt download is discarded. Valid installed packages stay.
                    if !(error is CancellationError) { try? manager.removeItem(at: target) }
                    throw error
                }
                complete += file.bytes
            }
            await progress(.verifying, files.reduce(0) { $0 + $1.bytes })
            try verifyFiles(files, at: staging, base: base) // All files checked together immediately before publication.
            try data.write(to: staging.appending(path: "package.json"), options: .atomic)
            try manager.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Task.checkCancellation()
            try manager.moveItem(at: staging, to: final) // Same-volume rename; no partial final directory.
        }
        let pointer = try JSONEncoder().encode(Active(id: entry.id, manifestSHA256: entry.manifestSHA256))
        try Task.checkCancellation()
        let activePointer = root.appending(path: "active-\(pair.rawValue).json")
        try beforePointerPublication()
        // Old package/pointer survives any earlier failure. No suspension during atomic publication.
        try publishPointer(pointer, to: activePointer, publishedDirectory: final, base: base)
    }

    private nonisolated static func missingBytes(_ files: [SpeechPackage.File], at directory: URL, base: URL) throws -> Int64 {
        var missing: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            let url = directory.appending(path: file.path)
            try noSymlinks(url, base: base)
            guard FileManager.default.fileExists(atPath: url.path) else { missing += file.bytes; continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize else { throw SpeechPackageError.unsafePath }
            guard Int64(size) <= file.bytes else {
                // Remove only an invalid unpublished file so the next explicit Retry can recover.
                try FileManager.default.removeItem(at: url)
                throw SpeechPackageError.integrity
            }
            missing += file.bytes - Int64(size)
        }
        return missing
    }

    /// Test seam for real disposable-filesystem hashing and path checks. Shipping callers pass
    /// only an already validated package and use the application-support base by default.
    nonisolated static func verifyFiles(_ files: [SpeechPackage.File], at directory: URL, base: URL = .applicationSupportDirectory) throws {
        try noSymlinks(directory, base: base)
        let expected = Set(files.map { directory.appending(path: $0.path).standardizedFileURL.path })
        let packageManifest = directory.appending(path: "package.json").standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            throw SpeechPackageError.integrity
        }
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw SpeechPackageError.unsafePath }
            if values.isRegularFile == true {
                let path = url.standardizedFileURL.path
                guard path == packageManifest || expected.contains(path) else { throw SpeechPackageError.integrity }
            }
        }
        for file in files { try verify(file, at: directory, base: base) }
    }
    private nonisolated static func verify(_ file: SpeechPackage.File, at directory: URL, base: URL = .applicationSupportDirectory) throws {
        let url = directory.appending(path: file.path)
        try noSymlinks(url, base: base)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, Int64(values.fileSize ?? -1) == file.bytes else { throw SpeechPackageError.integrity }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while try autoreleasepool(invoking: { () throws -> Bool in
            try Task.checkCancellation()
            guard let block = try handle.read(upToCount: 1_048_576), !block.isEmpty else { return false }
            hash.update(data: block); return true
        }) {}
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256 else { throw SpeechPackageError.integrity }
    }
    private nonisolated static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private nonisolated static func boundedFile(_ url: URL, maximum: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        guard data.count <= maximum else { throw SpeechPackageError.invalidManifest }
        return data
    }
    /// Publishes only the active pointer after an immutable directory is fully present.
    /// Kept as an internal seam so tests can exercise real atomic filesystem behavior.
    nonisolated static func publishPointer(_ data: Data, to pointer: URL, publishedDirectory: URL,
                                           base: URL = .applicationSupportDirectory) throws {
        guard FileManager.default.fileExists(atPath: publishedDirectory.path) else { throw SpeechPackageError.integrity }
        try noSymlinks(publishedDirectory, base: base)
        try noSymlinks(pointer, base: base)
        try data.write(to: pointer, options: .atomic)
    }
    private nonisolated static func noSymlinks(_ url: URL, base: URL = .applicationSupportDirectory) throws {
        // Walk the selected container subtree, not /var's system-managed aliases.
        let base = base.standardizedFileURL
        let path = url.standardizedFileURL.path
        guard path == base.path || path.hasPrefix(base.path + "/") else { throw SpeechPackageError.unsafePath }
        var current = base
        for component in path.dropFirst(base.path.count).split(separator: "/") {
            current.appendPathComponent(String(component))
            // lstat also catches a dangling symlink (fileExists would miss it).
            var info = stat()
            if lstat(current.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK { throw SpeechPackageError.unsafePath }
        }
    }
    public nonisolated static func freeBytes() throws -> Int64 {
        let values = try URL.applicationSupportDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        guard let bytes = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init) else {
            throw SpeechPackageError.download("Available storage could not be checked. Retry before downloading.")
        }
        return bytes
    }
    public nonisolated static func hardware() throws -> String {
        var count = 0
        guard sysctlbyname("hw.machine", nil, &count, nil, 0) == 0, count > 0 else { throw SpeechPackageError.incompatible }
        var bytes = [CChar](repeating: 0, count: count)
        guard sysctlbyname("hw.machine", &bytes, &count, nil, 0) == 0 else { throw SpeechPackageError.incompatible }
        return String(decoding: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// Single-use, bounded response reader. Delegate-owned buffer is confined to one serial
/// delegate queue. The lock protects task/continuation installation and cancellation.
/// Headers are checked BEFORE accepting the body, preventing a server that ignores Range
/// from buffering a multi-gigabyte response. No cookies, credentials or shared cache.
final class SpeechHTTP: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let entry: ReviewedSpeechPackage
    private let maximum: Int
    private let range: (Int64, Int64, Int64)?
    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    private var pending: CheckedContinuation<Data, Error>?
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var cancelled = false
    private var buffer = Data() // delegate queue only
    private var failure: Error? // delegate queue only
    private init(entry: ReviewedSpeechPackage, maximum: Int, range: (Int64, Int64, Int64)?, configuration: URLSessionConfiguration) {
        self.entry = entry; self.maximum = maximum; self.range = range
        self.configuration = configuration.copy() as! URLSessionConfiguration
    }
    static func fetch(_ url: URL, entry: ReviewedSpeechPackage, maximumBytes: Int,
                      range: (Int64, Int64, Int64)? = nil,
                      configuration: URLSessionConfiguration = .ephemeral) async throws -> Data {
        try Task.checkCancellation()
        guard entry.permits(url), maximumBytes > 0, maximumBytes <= Int(SpeechPackage.chunkBytes) else {
            throw SpeechPackageError.invalidManifest
        }
        let transfer = SpeechHTTP(entry: entry, maximum: maximumBytes, range: range, configuration: configuration)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in transfer.start(url, continuation: continuation) }
        } onCancel: { transfer.cancel() }
    }
    private func start(_ url: URL, continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        pending = continuation
        let configuration = self.configuration
        configuration.httpShouldSetCookies = false; configuration.urlCache = nil; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        var request = URLRequest(url: url); request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let (offset, count, _) = range { request.setValue("bytes=\(offset)-\(offset + count - 1)", forHTTPHeaderField: "Range") }
        let task = session.dataTask(with: request); self.task = task
        lock.unlock(); task.resume()
    }
    private func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock(); task?.cancel()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, entry.permits(url) else {
            failure = SpeechPackageError.invalidManifest; completionHandler(nil); task.cancel(); return
        }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        do {
            guard let http = response as? HTTPURLResponse, let url = http.url, entry.permits(url),
                  http.value(forHTTPHeaderField: "Content-Encoding").map({ $0.lowercased() == "identity" }) ?? true else {
                throw SpeechPackageError.invalidManifest
            }
            if let (offset, count, total) = range {
                try SpeechPackage.validateResponse(status: http.statusCode, contentRange: http.value(forHTTPHeaderField: "Content-Range"),
                    offset: offset, count: count, total: total)
            } else if http.statusCode != 200 { throw SpeechPackageError.download("The speech download is unavailable. Check the connection and Retry.") }
            guard response.expectedContentLength <= Int64(maximum) else { throw SpeechPackageError.invalidManifest }
            completionHandler(.allow)
        } catch { failure = error; completionHandler(.cancel) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard data.count <= maximum - buffer.count else { failure = SpeechPackageError.invalidManifest; dataTask.cancel(); return }
        buffer.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let continuation = pending; pending = nil; let cancelled = cancelled
        self.task = nil; self.session = nil; lock.unlock()
        defer { session.finishTasksAndInvalidate() }
        if cancelled { continuation?.resume(throwing: CancellationError()) }
        else if let failure = failure ?? error { continuation?.resume(throwing: failure) }
        else if let (_, count, _) = range, Int64(buffer.count) != count { continuation?.resume(throwing: SpeechPackageError.integrity) }
        else { continuation?.resume(returning: buffer) }
    }
}
#endif
