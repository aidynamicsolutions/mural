#if canImport(Darwin)
import Foundation
import Testing
@testable import MuralCore

/// Exercises the real bounded delegate through URLProtocol, not a live model/CDN.
private final class SpeechResponseProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var status = 206
        var headers = ["Content-Range": "bytes 4-7/12"]
        var data = Data([1, 2, 3, 4])
        var holdOpen = false
        var redirectURL: URL?
    }
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var response = Response()
        private var request: URLRequest?
        func reset(_ response: Response) { lock.lock(); defer { lock.unlock() }; self.response = response; request = nil }
        func start(_ request: URLRequest) -> Response { lock.lock(); defer { lock.unlock() }; self.request = request; return response }
        func lastRequest() -> URLRequest? { lock.lock(); defer { lock.unlock() }; return request }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let script = Self.state.start(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: script.status, httpVersion: "HTTP/1.1", headerFields: script.headers)!
        if let redirectURL = script.redirectURL {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: redirectURL), redirectResponse: response)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !script.data.isEmpty { client?.urlProtocol(self, didLoad: script.data) }
        if !script.holdOpen { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct SpeechHTTPTests {
    private var entry: ReviewedSpeechPackage {
        .init(id: "http-fixture", pair: .taiwanMandarinEnglish, manifestURL: URL(string: "https://models.example.test/package.json")!,
            filesURL: URL(string: "https://models.example.test/")!, manifestSHA256: String(repeating: "a", count: 64), allowedHosts: ["models.example.test"])
    }
    private var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpeechResponseProtocol.self]
        return configuration
    }
    private func fetch() async throws -> Data {
        try await SpeechHTTP.fetch(entry.filesURL.appending(path: "file"), entry: entry, maximumBytes: 4,
            range: (4, 4, 12), configuration: configuration)
    }
    @Test func acceptsAnExactRangeAndSendsIdentityEncoding() async throws {
        SpeechResponseProtocol.state.reset(.init())
        #expect(try await fetch() == Data([1, 2, 3, 4]))
        #expect(SpeechResponseProtocol.state.lastRequest()?.value(forHTTPHeaderField: "Range") == "bytes=4-7")
        #expect(SpeechResponseProtocol.state.lastRequest()?.value(forHTTPHeaderField: "Accept-Encoding") == "identity")
    }
    @Test func ignoresNoRangeResponseRatherThanAppending() async {
        SpeechResponseProtocol.state.reset(.init(status: 200))
        await #expect(throws: (any Error).self) { try await fetch() }
    }
    @Test func rejectsTruncatedRange() async {
        SpeechResponseProtocol.state.reset(.init(data: Data([1, 2])))
        await #expect(throws: (any Error).self) { try await fetch() }
    }
    @Test func rejectsOversizedBodyWithoutLengthHeader() async {
        SpeechResponseProtocol.state.reset(.init(data: Data(repeating: 0, count: 9)))
        await #expect(throws: (any Error).self) { try await fetch() }
    }
    @Test func rejectsOversizedOrEncodedHeaders() async {
        for headers in [["Content-Range": "bytes 4-7/12", "Content-Length": "9000000000"],
                        ["Content-Range": "bytes 4-7/12", "Content-Encoding": "gzip"]] {
            SpeechResponseProtocol.state.reset(.init(headers: headers))
            await #expect(throws: (any Error).self) { try await fetch() }
        }
    }
    @Test func rejectsRedirectToUnreviewedHost() async {
        SpeechResponseProtocol.state.reset(.init(status: 302, redirectURL: URL(string: "https://attacker.example.test/model")!))
        do { _ = try await fetch(); Issue.record("Expected an unreviewed redirect to fail") }
        catch SpeechPackageError.invalidManifest {}
        catch { Issue.record("Unexpected redirect error: \(error)") }
    }
    @Test func cancellationDrainsTheRequest() async throws {
        SpeechResponseProtocol.state.reset(.init(data: Data(), holdOpen: true))
        let worker = Task { try await fetch() }
        defer { worker.cancel() }
        for _ in 0..<200 {
            if SpeechResponseProtocol.state.lastRequest() != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(SpeechResponseProtocol.state.lastRequest() != nil)
        worker.cancel()
        await #expect(throws: CancellationError.self) { try await worker.value }
    }
}
#endif
