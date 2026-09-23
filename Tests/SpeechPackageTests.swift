import CryptoKit
import Foundation
import Testing
@testable import MuralCore

private let exampleHash = String(repeating: "a", count: 64)
private func fixture(_ pair: LocalSpeechPair = .taiwanMandarinEnglish) -> SpeechPackage {
    let breeze = pair == .taiwanMandarinEnglish
    let names = ["manifest.json", "config.json", "generation_config.json", "tokenizer.json", "tokenizer_config.json"] +
        ["MelSpectrogram", "AudioEncoder", "TextDecoder"].flatMap { name in
            ["coremldata.bin", "metadata.json", "model.mil", "weights/weight.bin"].map { "\(name).mlmodelc/\($0)" }
        }
    var files = names.map { SpeechPackage.File(path: "support/" + $0, bytes: 1,
        sha256: $0 == "manifest.json" ? (breeze ? SpeechPackagePins.breezeManifest : SpeechPackagePins.phoWhisperSupportManifest) : exampleHash) }
    if !breeze { files.append(.init(path: "encoder/manifest.json", bytes: 1, sha256: SpeechPackagePins.phoWhisperEncoderManifest)) }
    return SpeechPackage(id: "fixture-v1", pair: pair, backend: breeze ? .breezeCoreMLPAL8 : .phoWhisperCoreAIFP8PAL8,
        revision: breeze ? SpeechPackagePins.breezeRevision : String(repeating: "b", count: 40),
        hardware: ["iPhone18,3"], osMajors: [27],
        computeUnits: ["mel": "cpuAndGPU", "encoder": breeze ? "cpuAndNeuralEngine" : "gpuPreferred", "decoder": "cpuAndNeuralEngine"],
        specializationReserveBytes: 100, files: files.sorted { $0.path < $1.path })
}
private func replacing(_ value: SpeechPackage, key: String, with replacement: Any) throws -> Data {
    var json = try #require(JSONSerialization.jsonObject(with: value.canonicalData()) as? [String: Any])
    json[key] = replacement
    return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])
}

struct SpeechPackageTests {
    @Test(arguments: LocalSpeechPair.allCases) func packageRoundTrip(_ pair: LocalSpeechPair) throws {
        let package = fixture(pair)
        #expect(try SpeechPackage.decode(package.canonicalData()) == package)
        #expect(package.supports(hardware: "iPhone18,3", osMajor: 27))
        #expect(!package.supports(hardware: "different-device", osMajor: 27))
        #expect(!package.supports(hardware: "iPhone18,3", osMajor: 28))
    }
    @Test func fixedPinAndNoModelRouter() {
        #expect(LocalSpeechPair.vietnameseEnglish.recognizerID != LocalSpeechPair.taiwanMandarinEnglish.recognizerID)
        #expect(SpeechPackagePins.breezeManifest == "64021fb776ee2ef4cf02c05b2a9dafde0e0700e9bf7d967b4bc5302558b5fdb4")
        #expect(SpeechPackagePins.breezeRevision == "cffe7ccb404d025296a00758d0a33468bec3a9d0")
        #expect(LocalSpeechPair.forSupportLanguage("Traditional Chinese") == .taiwanMandarinEnglish)
        #expect(LocalSpeechPair.forSupportLanguage("Simplified Chinese") == nil)
        #expect(LocalSpeechPair.taiwanMandarinEnglish.supportLocale == "zh-Hant-TW")
    }
    @Test func supportCacheDoesNotCrossPairs() {
        let vi = LocalSpeechPair.vietnameseEnglish.helpCacheKey(revisionKey: "a:0")
        let tw = LocalSpeechPair.taiwanMandarinEnglish.helpCacheKey(revisionKey: "a:0")
        #expect(vi != tw)
        #expect(tw != LocalSpeechPair.taiwanMandarinEnglish.helpCacheKey(revisionKey: "a:1"))
        #expect(LocalSpeechPair.taiwanSupportInstructions(help: true).contains("Traditional Chinese"))
    }
    @Test(arguments: ["../escape", "/absolute", "support/../x", "support//x", "support/", "support/./x", "support/x\\y", "support/%2e%2e", "support/é", "support/x?key", String(repeating: "x", count: 513)])
    func rejectsUnsafePaths(_ path: String) {
        #expect(throws: (any Error).self) { try SpeechPackage.validatePath(path) }
    }
    @Test func rejectsDuplicateCaseAndDirectoryCollisions() throws {
        let baseline = fixture()
        for path in ["support/CONFIG.json", "support/AudioEncoder.mlmodelc"] {
            var files = baseline.files
            files.append(.init(path: path, bytes: 1, sha256: exampleHash))
            let encoded = try JSONEncoder().encode(files.sorted { $0.path < $1.path })
            let replacement = try JSONSerialization.jsonObject(with: encoded)
            #expect(throws: (any Error).self) { try SpeechPackage.decode(replacing(baseline, key: "files", with: replacement)) }
        }
    }
    @Test func requiresCompleteSupportAndIndependentNestedPin() throws {
        let baseline = fixture()
        var files = baseline.files.filter { $0.path != "support/TextDecoder.mlmodelc/model.mil" }
        let missing = try JSONSerialization.jsonObject(with: JSONEncoder().encode(files))
        #expect(throws: (any Error).self) { try SpeechPackage.decode(replacing(baseline, key: "files", with: missing)) }
        files = baseline.files.map { .init(path: $0.path, bytes: $0.bytes, sha256: exampleHash) }
        let unpinned = try JSONSerialization.jsonObject(with: JSONEncoder().encode(files))
        #expect(throws: (any Error).self) { try SpeechPackage.decode(replacing(baseline, key: "files", with: unpinned)) }
    }
    @Test func rejectsUnknownFieldsAndDuplicateJSONKeys() throws {
        let value = fixture()
        let unknown = try replacing(value, key: "unexpected", with: true)
        #expect(throws: (any Error).self) { try SpeechPackage.decode(unknown) }
        var text = String(decoding: try value.canonicalData(), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"schema\":1", with: "\"schema\":1,\"schema\":1")
        #expect(throws: (any Error).self) { try SpeechPackage.decode(Data(text.utf8)) }
        #expect(throws: (any Error).self) { try SpeechPackage.decode(value.canonicalData() + Data([10])) }
    }
    @Test func rejectsUnsupportedConfigurationAndPrecision() throws {
        let baseline = fixture()
        let mutations: [(String, Any)] = [("schema", 2), ("pair", "vi-en"), ("revision", String(repeating: "0", count: 40)),
            ("hardware", ["iPhone18,4"]), ("osMajors", [27, 28]), ("specializationReserveBytes", 0),
            ("computeUnits", ["encoder": "cpuOnly"]), ("backend", "breezePAL4")]
        for (key, value) in mutations {
            #expect(throws: (any Error).self) { try SpeechPackage.decode(replacing(baseline, key: key, with: value)) }
        }
    }
    @Test func rejectsOversizedManifest() {
        #expect(throws: (any Error).self) { try SpeechPackage.decode(Data(repeating: 32, count: SpeechPackage.maximumManifestBytes + 1)) }
    }
    @Test func exactRangesAndWholeSmallFiles() throws {
        try SpeechPackage.validateResponse(status: 206, contentRange: "bytes 4-7/12", offset: 4, count: 4, total: 12)
        try SpeechPackage.validateResponse(status: 200, contentRange: nil, offset: 0, count: 4, total: 4)
    }
    @Test(arguments: [200, 204, 301, 404, 416, 500]) func cannotAppendWrongHTTPStatus(_ status: Int) {
        #expect(throws: (any Error).self) { try SpeechPackage.validateResponse(status: status, contentRange: "bytes 4-7/12", offset: 4, count: 4, total: 12) }
    }
    @Test(arguments: ["bytes 0-3/12", "bytes 4-8/12", "bytes 4-7/13", "bytes 4-7/*", "items 4-7/12", ""]) func rejectsMismatchedRanges(_ range: String) {
        #expect(throws: (any Error).self) { try SpeechPackage.validateResponse(status: 206, contentRange: range, offset: 4, count: 4, total: 12) }
    }
    @Test func rejectsOverflowingRange() {
        #expect(throws: (any Error).self) { try SpeechPackage.validateResponse(status: 206, contentRange: nil, offset: .max, count: 4, total: .max) }
        #expect(throws: (any Error).self) { try SpeechPackage.validateResponse(status: 206, contentRange: nil, offset: 0, count: 0, total: 1) }
    }
    @Test func reviewedHostsOnly() throws {
        let entry = ReviewedSpeechPackage(id: "fixture-v1", pair: .taiwanMandarinEnglish,
            manifestURL: URL(string: "https://models.example.test/v1/package.json")!, filesURL: URL(string: "https://models.example.test/v1/")!,
            manifestSHA256: exampleHash, allowedHosts: ["models.example.test", "cdn.example.test"])
        try entry.validate()
        #expect(entry.permits(URL(string: "https://cdn.example.test/immutable/model")!))
        for url in ["http://models.example.test/a", "https://other.example.test/a", "https://user:password@models.example.test/a", "https://models.example.test/a#fragment"] {
            #expect(!entry.permits(URL(string: url)!))
        }
    }
    @Test func disposableFilesystemVerificationFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appending(path: "package", directoryHint: .isDirectory)
        let payload = Data("verified model bytes".utf8)
        let relativePath = "support/model.bin"
        let file = SpeechPackage.File(path: relativePath, bytes: Int64(payload.count), sha256: Self.digest(payload))

        func restore() throws {
            try? FileManager.default.removeItem(at: package)
            try FileManager.default.createDirectory(at: package.appending(path: "support"), withIntermediateDirectories: true)
            try payload.write(to: package.appending(path: relativePath))
        }

        try restore()
        try LocalSpeechProvisioning.verifyFiles([file], at: package, base: root)

        try Data(payload.dropLast()).write(to: package.appending(path: relativePath))
        #expect(throws: (any Error).self) { try LocalSpeechProvisioning.verifyFiles([file], at: package, base: root) }

        try restore()
        try Data(repeating: 0, count: payload.count).write(to: package.appending(path: relativePath))
        #expect(throws: (any Error).self) { try LocalSpeechProvisioning.verifyFiles([file], at: package, base: root) }

        try restore()
        try Data().write(to: package.appending(path: "unexpected.bin"))
        #expect(throws: (any Error).self) { try LocalSpeechProvisioning.verifyFiles([file], at: package, base: root) }

        try restore()
        try FileManager.default.removeItem(at: package.appending(path: relativePath))
        try FileManager.default.createSymbolicLink(at: package.appending(path: relativePath), withDestinationURL: URL(filePath: "/dev/null"))
        #expect(throws: (any Error).self) { try LocalSpeechProvisioning.verifyFiles([file], at: package, base: root) }
    }
    @Test func activePointerPublishesOnlyAfterImmutableDirectoryExists() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pointer = root.appending(path: "active.json")
        let published = root.appending(path: "packages/new", directoryHint: .isDirectory)
        let old = Data("old".utf8), new = Data("new".utf8)
        try old.write(to: pointer)

        #expect(throws: (any Error).self) {
            try LocalSpeechProvisioning.publishPointer(new, to: pointer, publishedDirectory: published, base: root)
        }
        #expect(try Data(contentsOf: pointer) == old)

        try FileManager.default.createDirectory(at: published, withIntermediateDirectories: true)
        try LocalSpeechProvisioning.publishPointer(new, to: pointer, publishedDirectory: published, base: root)
        #expect(try Data(contentsOf: pointer) == new)
    }
    @Test func missingPublishedCatalogFailsClosed() {
        // Replace this test with concrete catalog checks when reviewed packages are published.
        guard SpeechPackageCatalog.entries.isEmpty else { return }
        for pair in LocalSpeechPair.allCases {
            #expect(throws: (any Error).self) { try SpeechPackageCatalog.entry(for: pair) }
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
