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
        private var responses = [Response()]
        private var request: URLRequest?
        func reset(_ response: Response) { lock.lock(); defer { lock.unlock() }; self.responses = [response]; request = nil }
        func reset(sequence responses: [Response]) { lock.lock(); defer { lock.unlock() }; self.responses = responses; request = nil }
        func start(_ request: URLRequest) -> Response {
            lock.lock(); defer { lock.unlock() }; self.request = request
            return responses.count > 1 ? responses.removeFirst() : responses[0]
        }
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
    // Before implementation: accept only this immutable graph destination and observed
    // signature fields, retain Range/identity, reject direct signed requests, altered
    // object/host/query/credentials, and stop redirect loops without accepting a body.
    private var signedGraph: URL {
        URL(string: "https://us.aws.cdn.hf.co/xet-bridge-us/699fdbe0354974651916cf42/f3d27ecf7506f46197f32617267f90ea8bfbbb3d35ed6ac3bb7434c74e6983d4?Expires=9999999999&Hash-Algorithm=SHA256&Key-Pair-Id=key&Policy=policy&Signature=signature&X-Xet-Cas-Uid=public&response-content-disposition=inline&user_id=public&xip=127.0.0.1")!
    }
    @Test func reviewedSignedRedirectPreservesRangeAndCannotBeAnInitialRequest() async throws {
        let entry = try SpeechPackageCatalog.entry(for: .mainlandMandarinEnglish)
        let original = entry.filesURL.appending(path: "encoder.int8.onnx")
        SpeechResponseProtocol.state.reset(sequence: [.init(status: 302, redirectURL: signedGraph), .init()])
        #expect(try await SpeechHTTP.fetch(original, entry: entry, maximumBytes: 4, range: (4, 4, 12), configuration: configuration) == Data([1, 2, 3, 4]))
        #expect(SpeechResponseProtocol.state.lastRequest()?.url == signedGraph)
        #expect(SpeechResponseProtocol.state.lastRequest()?.value(forHTTPHeaderField: "Range") == "bytes=4-7")
        #expect(SpeechResponseProtocol.state.lastRequest()?.value(forHTTPHeaderField: "Accept-Encoding") == "identity")
        await #expect(throws: SpeechPackageError.self) {
            try await SpeechHTTP.fetch(signedGraph, entry: entry, maximumBytes: 4, range: (4, 4, 12), configuration: configuration)
        }
    }
    @Test func fireRedRedirectContractRejectsUnreviewedDestinations() throws {
        let entry = try SpeechPackageCatalog.entry(for: .mainlandMandarinEnglish)
        let original = entry.filesURL.appending(path: "encoder.int8.onnx")
        #expect(entry.permitsRedirect(signedGraph, from: original))
        #expect(entry.permitsRedirect(signedGraph, from: entry.filesURL.appending(path: "decoder.int8.onnx")) == false)
        let text = signedGraph.absoluteString
        for bad in [text.replacingOccurrences(of: "https:", with: "http:"),
                    text.replacingOccurrences(of: "us.aws.cdn.hf.co", with: "evil.us.aws.cdn.hf.co"),
                    text.replacingOccurrences(of: "us.aws.cdn.hf.co", with: "user:pass@us.aws.cdn.hf.co"),
                    text.replacingOccurrences(of: "f3d27ec", with: "a3d27ec"),
                    text.replacingOccurrences(of: "Signature=signature", with: "Signature="),
                    text + "&Signature=duplicate", text + "&unknown=value", text + "#fragment"] {
            #expect(entry.permitsRedirect(try #require(URL(string: bad)), from: original) == false)
        }
        #expect(entry.permits(entry.filesURL.appending(path: "../main/encoder.int8.onnx")) == false)
        #expect(entry.permits(URL(string: "https://huggingface.co/other/model")!) == false)
        let tokenURL = entry.filesURL.appending(path: "tokens.txt")
        let tokenRedirect = observedTokenRedirect
        #expect(entry.permitsRedirect(tokenRedirect, from: tokenURL))
        #expect(entry.permitsRedirect(tokenRedirect, from: original) == false)
        #expect(entry.permits(tokenRedirect) == false)
    }
    // Regression copied verbatim from retained HEAD and GET Location headers, not
    // a hand-simplified query. Empty route echo and quoted ETag are intentional.
    private var observedTokenRedirect: URL { URL(string: "https://huggingface.co/api/resolve-cache/models/csukuangfj2/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26/374cff185e952c40fcf2f6da972a3b6cf340608d/tokens.txt?%2Fcsukuangfj2%2Fsherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26%2Fresolve%2F374cff185e952c40fcf2f6da972a3b6cf340608d%2Ftokens.txt=&etag=%2250ac9cbd43d638b58f875e90b118ad8c9be51718%22")! }
    @Test func observedTokenRedirectTransfersAndRejectsQueryMutations() async throws {
        let entry = try SpeechPackageCatalog.entry(for: .mainlandMandarinEnglish)
        let original = entry.filesURL.appending(path: "tokens.txt")
        SpeechResponseProtocol.state.reset(sequence: [.init(status: 307, redirectURL: observedTokenRedirect), .init()])
        #expect(try await SpeechHTTP.fetch(original, entry: entry, maximumBytes: 4,
            range: (4, 4, 12), configuration: configuration) == Data([1, 2, 3, 4]))
        let text = observedTokenRedirect.absoluteString
        for bad in [text.replacingOccurrences(of: "tokens.txt=&", with: "tokens.txt=unexpected&"),
                    text.replacingOccurrences(of: "%2Ftokens.txt=", with: "%2Fother.txt="),
                    text.replacingOccurrences(of: "50ac9cbd", with: "00ac9cbd"),
                    text + "&etag=duplicate", text + "&unknown=", text + "#fragment"] {
            #expect(entry.permitsRedirect(try #require(URL(string: bad)), from: original) == false)
        }
        #expect(entry.permitsRedirect(observedTokenRedirect, from: entry.filesURL.appending(path: "encoder.int8.onnx")) == false)
    }
    @Test func signedRedirectLoopIsBounded() async throws {
        let entry = try SpeechPackageCatalog.entry(for: .mainlandMandarinEnglish)
        SpeechResponseProtocol.state.reset(.init(status: 302, redirectURL: signedGraph))
        await #expect(throws: SpeechPackageError.self) {
            try await SpeechHTTP.fetch(entry.filesURL.appending(path: "encoder.int8.onnx"), entry: entry,
                maximumBytes: 4, range: (4, 4, 12), configuration: configuration)
        }
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
