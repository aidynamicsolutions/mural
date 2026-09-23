#if canImport(Darwin)
import CryptoKit
import Foundation
import Testing
@testable import MuralCore

private enum InstallerResponse: Sendable {
    case data(status: Int, headers: [String: String], body: Data)
    case networkLost
    case hold
}

private final class InstallerURLProtocol: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: @Sendable (URLRequest, Int) -> InstallerResponse = { _, _ in .networkLost }
        private var requests: [String] = []
        private var waiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

        func reset(_ handler: @escaping @Sendable (URLRequest, Int) -> InstallerResponse) {
            lock.lock(); defer { lock.unlock() }
            self.handler = handler
            requests = []
        }
        func response(for request: URLRequest) -> InstallerResponse {
            lock.lock()
            requests.append(request.value(forHTTPHeaderField: "Range") ?? "")
            let ordinal = requests.count
            let handler = self.handler
            let ready = waiters.filter { $0.key <= ordinal }.values.flatMap { $0 }
            waiters = waiters.filter { $0.key > ordinal }
            lock.unlock()
            ready.forEach { $0.resume() }
            return handler(request, ordinal)
        }
        func waitForRequest(_ count: Int) async {
            await withCheckedContinuation { continuation in
                lock.lock()
                if requests.count >= count {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiters[count, default: []].append(continuation)
                    lock.unlock()
                }
            }
        }
        func snapshot() -> [String] {
            lock.lock(); defer { lock.unlock() }
            return requests
        }
    }

    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        switch Self.state.response(for: request) {
        case .data(let status, let headers, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
            client?.urlProtocolDidFinishLoading(self)
        case .networkLost:
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
        case .hold:
            break
        }
    }
    override func stopLoading() {}
}

private func installerDigest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@Suite(.serialized, .timeLimit(.minutes(1))) struct SpeechInstallerTests {
    private struct Fixture {
        let base: URL
        let root: URL
        let entry: ReviewedSpeechPackage
        let data: Data
        let file: SpeechPackage.File
        let body: Data
        var staging: URL { root.appending(path: ".downloads/\(entry.id)-\(entry.manifestSHA256)", directoryHint: .isDirectory) }
        var final: URL { root.appending(path: "packages/\(entry.id)-\(entry.manifestSHA256)", directoryHint: .isDirectory) }
        var target: URL { staging.appending(path: file.path) }
        var pointer: URL { root.appending(path: "active-\(entry.pair.rawValue).json") }

        init(base: URL, id: String, body: Data, expectedHash: String? = nil) {
            self.base = base
            root = base.appending(path: "SpeechModels", directoryHint: .isDirectory)
            self.body = body
            data = Data("{\"fixture\":true}".utf8)
            file = .init(path: "support/model.bin", bytes: Int64(body.count), sha256: expectedHash ?? installerDigest(body))
            entry = .init(id: id, pair: .taiwanMandarinEnglish,
                manifestURL: URL(string: "https://models.example.test/package.json")!,
                filesURL: URL(string: "https://models.example.test/")!, manifestSHA256: installerDigest(data),
                allowedHosts: ["models.example.test"])
        }
    }

    private struct ActivePointer: Decodable { let id: String; let manifestSHA256: String }
    private struct SimulatedInterruption: Error {}
    private final class SpaceBudget: @unchecked Sendable {
        private let lock = NSLock()
        private var readings: [Int64]
        init(_ readings: [Int64]) { self.readings = readings }
        func next() -> Int64 {
            lock.lock(); defer { lock.unlock() }
            return readings.isEmpty ? 0 : readings.removeFirst()
        }
    }

    private func temporaryBase() throws -> URL {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "speech-installer-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    private func configuration() -> URLSessionConfiguration {
        let value = URLSessionConfiguration.ephemeral
        value.protocolClasses = [InstallerURLProtocol.self]
        return value
    }
    private func install(_ fixture: Fixture, availableBytes: @escaping @Sendable () throws -> Int64 = { Int64.max },
                         beforePointerPublication: @escaping @Sendable () throws -> Void = {}) async throws {
        try await LocalSpeechProvisioning.installValidatedPackage(files: [fixture.file], data: fixture.data,
            entry: fixture.entry, pair: fixture.entry.pair, specializationReserveBytes: 64,
            root: fixture.root, base: fixture.base, sessionConfiguration: configuration(),
            availableBytes: availableBytes, beforePointerPublication: beforePointerPublication)
    }
    private static func response(for request: URLRequest, body: Data) -> InstallerResponse {
        guard let value = request.value(forHTTPHeaderField: "Range"), value.hasPrefix("bytes=") else { return .networkLost }
        let parts = value.dropFirst(6).split(separator: "-")
        guard parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]), start >= 0, end < body.count, start <= end else {
            return .networkLost
        }
        let block = Data(body[start...end])
        return .data(status: 206, headers: ["Content-Range": "bytes \(start)-\(end)/\(body.count)", "Content-Length": "\(block.count)"], body: block)
    }
    private func pointerData(_ fixture: Fixture) throws -> Data { try Data(contentsOf: fixture.pointer) }
    private func active(_ fixture: Fixture) throws -> ActivePointer { try JSONDecoder().decode(ActivePointer.self, from: pointerData(fixture)) }
    @Test func resumesExactRangesAfterNetworkLossCancellationAndWorkerRestart() async throws {
        let base = try temporaryBase(); defer { try? FileManager.default.removeItem(at: base) }
        let body = Data(repeating: 0x5a, count: Int(SpeechPackage.chunkBytes) + 17)
        let fixture = Fixture(base: base, id: "resume-v1", body: body)
        InstallerURLProtocol.state.reset { request, ordinal in
            switch ordinal {
            case 1: Self.response(for: request, body: body)
            case 2: .networkLost
            case 3: .hold
            default: Self.response(for: request, body: body)
            }
        }

        do { try await install(fixture); Issue.record("Expected the interrupted range to fail") }
        catch let error as URLError { #expect(error.code == .networkConnectionLost) }
        catch { Issue.record("Unexpected installer error: \(error)") }
        #expect((try fixture.target.resourceValues(forKeys: [.fileSizeKey])).fileSize == Int(SpeechPackage.chunkBytes))

        let cancelledWorker = Task { try await install(fixture) }
        await InstallerURLProtocol.state.waitForRequest(3)
        cancelledWorker.cancel()
        await #expect(throws: CancellationError.self) { try await cancelledWorker.value }
        #expect((try fixture.target.resourceValues(forKeys: [.fileSizeKey])).fileSize == Int(SpeechPackage.chunkBytes))

        try await install(fixture)
        #expect(InstallerURLProtocol.state.snapshot() == [
            "bytes=0-4194303", "bytes=4194304-4194320", "bytes=4194304-4194320", "bytes=4194304-4194320"
        ])
        #expect(try Data(contentsOf: fixture.final.appending(path: fixture.file.path)) == body)
        #expect(try active(fixture).id == fixture.entry.id)
        #expect(FileManager.default.fileExists(atPath: fixture.final.appending(path: "package.json").path))
    }

    @Test func acceptsCompleteObjectWhenServerIgnoresInitialRange() async throws {
        let base = try temporaryBase(); defer { try? FileManager.default.removeItem(at: base) }
        let body = Data("small model".utf8)
        let fixture = Fixture(base: base, id: "full-200-v1", body: body)
        InstallerURLProtocol.state.reset { _, _ in
            .data(status: 200, headers: ["Content-Length": "\(body.count)"], body: body)
        }
        try await install(fixture)
        #expect(InstallerURLProtocol.state.snapshot() == ["bytes=0-\(body.count - 1)"])
        #expect(try Data(contentsOf: fixture.final.appending(path: fixture.file.path)) == body)
    }

    @Test func integrityFailureAndBadManifestPinKeepThePreviousInstall() async throws {
        let base = try temporaryBase(); defer { try? FileManager.default.removeItem(at: base) }
        let old = Fixture(base: base, id: "old-v1", body: Data("old model".utf8))
        InstallerURLProtocol.state.reset { request, _ in Self.response(for: request, body: old.body) }
        try await install(old)
        let oldPointer = try pointerData(old)
        let oldDirectory = old.final

        let body = Data("wrong!".utf8)
        let corrupt = Fixture(base: base, id: "corrupt-v2", body: body, expectedHash: installerDigest(Data("right!".utf8)))
        InstallerURLProtocol.state.reset { request, _ in Self.response(for: request, body: body) }
        do { try await install(corrupt); Issue.record("Expected corrupt package data to fail verification") }
        catch SpeechPackageError.integrity {}
        catch { Issue.record("Unexpected installer error: \(error)") }
        #expect(try pointerData(old) == oldPointer)
        #expect(FileManager.default.fileExists(atPath: oldDirectory.path))
        #expect(FileManager.default.fileExists(atPath: corrupt.final.path) == false)
        #expect(FileManager.default.fileExists(atPath: corrupt.target.path) == false)

        let badPin = Fixture(base: base, id: "bad-pin-v2", body: Data("new model".utf8))
        InstallerURLProtocol.state.reset { _, _ in .networkLost }
        let tampered = Data("not the pinned manifest".utf8)
        do {
            try await LocalSpeechProvisioning.installValidatedPackage(files: [badPin.file], data: tampered,
                entry: badPin.entry, pair: badPin.entry.pair, specializationReserveBytes: 64,
                root: badPin.root, base: badPin.base, sessionConfiguration: configuration())
            Issue.record("Expected a mismatched manifest pin to fail")
        } catch SpeechPackageError.integrity {}
        catch { Issue.record("Unexpected installer error: \(error)") }
        #expect(InstallerURLProtocol.state.snapshot().isEmpty)
        #expect(try pointerData(old) == oldPointer)
    }

    @Test func storageAndFilesystemFailuresDoNotReplaceTheActiveVersion() async throws {
        let base = try temporaryBase(); defer { try? FileManager.default.removeItem(at: base) }
        let old = Fixture(base: base, id: "stable-v1", body: Data("stable".utf8))
        InstallerURLProtocol.state.reset { request, _ in Self.response(for: request, body: old.body) }
        try await install(old)
        let oldPointer = try pointerData(old)

        let lowSpace = Fixture(base: base, id: "low-space-v2", body: Data("new".utf8))
        InstallerURLProtocol.state.reset { _, _ in .networkLost }
        do { try await install(lowSpace, availableBytes: { 0 }); Issue.record("Expected insufficient space to fail") }
        catch SpeechPackageError.storage {}
        catch { Issue.record("Unexpected installer error: \(error)") }
        #expect(InstallerURLProtocol.state.snapshot().isEmpty)
        #expect(try pointerData(old) == oldPointer)

        let failedWrite = Fixture(base: base, id: "write-failure-v2", body: Data("new".utf8))
        try FileManager.default.createDirectory(at: failedWrite.target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: failedWrite.target)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: failedWrite.target.path)
        await #expect(throws: (any Error).self) { try await install(failedWrite) }
        #expect(InstallerURLProtocol.state.snapshot().isEmpty)
        #expect(try pointerData(old) == oldPointer)
        #expect(FileManager.default.fileExists(atPath: old.final.path))
    }

    @Test func recoversFromStorageLossBetweenRangesWithoutReplacingActiveVersion() async throws {
        let base = try temporaryBase(); defer { try? FileManager.default.removeItem(at: base) }
        let old = Fixture(base: base, id: "storage-active-v1", body: Data("stable".utf8))
        InstallerURLProtocol.state.reset { request, _ in Self.response(for: request, body: old.body) }
        try await install(old)
        let oldPointer = try pointerData(old)

        let body = Data(repeating: 0x37, count: Int(SpeechPackage.chunkBytes) + 17)
        let new = Fixture(base: base, id: "storage-active-v2", body: body)
        InstallerURLProtocol.state.reset { request, _ in Self.response(for: request, body: body) }
        let budget = SpaceBudget([Int64.max, Int64.max, 0])
        do {
            try await install(new, availableBytes: { budget.next() })
            Issue.record("Expected storage loss before the second range")
        } catch SpeechPackageError.storage {}
        catch { Issue.record("Unexpected installer error: \(error)") }
        #expect(InstallerURLProtocol.state.snapshot() == ["bytes=0-4194303"])
        #expect((try new.target.resourceValues(forKeys: [.fileSizeKey])).fileSize == Int(SpeechPackage.chunkBytes))
        #expect(try pointerData(old) == oldPointer)

        InstallerURLProtocol.state.reset { request, _ in Self.response(for: request, body: body) }
        try await install(new)
        #expect(InstallerURLProtocol.state.snapshot() == ["bytes=4194304-4194320"])
        #expect(try active(new).id == new.entry.id)
        #expect(FileManager.default.fileExists(atPath: old.final.path))
    }

    @Test func interruptionBetweenDirectoryAndPointerPublicationRecoversAndRetainsOldVersion() async throws {
        let base = try temporaryBase(); defer { try? FileManager.default.removeItem(at: base) }
        let old = Fixture(base: base, id: "active-v1", body: Data("old".utf8))
        InstallerURLProtocol.state.reset { request, _ in Self.response(for: request, body: old.body) }
        try await install(old)
        let oldPointer = try pointerData(old)

        let new = Fixture(base: base, id: "active-v2", body: Data("new model".utf8))
        InstallerURLProtocol.state.reset { request, _ in Self.response(for: request, body: new.body) }
        await #expect(throws: SimulatedInterruption.self) {
            try await install(new, beforePointerPublication: { throw SimulatedInterruption() })
        }
        #expect(try pointerData(old) == oldPointer)
        #expect(FileManager.default.fileExists(atPath: old.final.path))
        #expect(FileManager.default.fileExists(atPath: new.final.path))
        #expect(FileManager.default.fileExists(atPath: new.staging.path) == false)

        let requestsBeforeRecovery = InstallerURLProtocol.state.snapshot().count
        InstallerURLProtocol.state.reset { _, _ in .networkLost }
        try await install(new)
        #expect(InstallerURLProtocol.state.snapshot().isEmpty)
        #expect(requestsBeforeRecovery == 1)
        #expect(try active(new).id == new.entry.id)
        #expect(FileManager.default.fileExists(atPath: old.final.path))
        #expect(try Data(contentsOf: new.final.appending(path: "package.json")) == new.data)
    }

}
#endif
