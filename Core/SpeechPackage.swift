import Foundation

/// Pins originate in the reviewed local artifacts, never in the downloaded metadata itself.
public enum SpeechPackagePins {
    public static let breezeRevision = "cffe7ccb404d025296a00758d0a33468bec3a9d0"
    public static let breezeManifest = "64021fb776ee2ef4cf02c05b2a9dafde0e0700e9bf7d967b4bc5302558b5fdb4"
    public static let phoWhisperSupportManifest = "430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336"
    public static let phoWhisperEncoderManifest = "73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13"
}

public enum SpeechPackageError: LocalizedError, Sendable {
    case invalidManifest, incompatible, notPublished, integrity, unsafePath, rangeUnsupported
    case storage(required: Int64, available: Int64), download(String)
    public var errorDescription: String? {
        switch self {
        case .invalidManifest: "The speech package metadata is invalid. Retry after an app update; no installed model was replaced."
        case .incompatible: "This speech package is not qualified for this iPhone and iOS version. Choose another speech option; no backend was changed."
        case .notPublished: "The reviewed download for this speech mode has not been published in this build. Existing models and conversations are unchanged. Choose another mode or check for an app update."
        case .integrity: "The speech package did not pass verification. Retry the download. Your valid installed models are unchanged."
        case .unsafePath: "The speech package contains an unsafe file path. No model was installed."
        case .rangeUnsupported: "The server could not safely resume this download. Retry on a stable connection or check for an app update."
        case .storage(let required, let available): "Not enough storage. This step needs \(required) bytes; \(available) bytes are available. Open Manage Storage, free space, then Retry."
        case .download(let message): message
        }
    }
}

public struct SpeechPackage: Codable, Equatable, Sendable {
    public enum Backend: String, Codable, Sendable { case breezeCoreMLPAL8, phoWhisperCoreAIFP8PAL8 }
    public struct File: Codable, Equatable, Sendable {
        public let path: String
        public let bytes: Int64
        public let sha256: String
        public init(path: String, bytes: Int64, sha256: String) { self.path = path; self.bytes = bytes; self.sha256 = sha256 }
    }
    public let schema: Int
    public let id: String
    public let pair: LocalSpeechPair
    public let backend: Backend
    public let revision: String
    public let hardware: [String]
    public let osMajors: [Int]
    public let computeUnits: [String: String]
    /// Reviewed measured headroom for native specialization, in addition to package storage.
    public let specializationReserveBytes: Int64
    public let files: [File]

    public init(id: String, pair: LocalSpeechPair, backend: Backend, revision: String,
                hardware: [String], osMajors: [Int], computeUnits: [String: String],
                specializationReserveBytes: Int64, files: [File]) {
        schema = 1; self.id = id; self.pair = pair; self.backend = backend; self.revision = revision
        self.hardware = hardware; self.osMajors = osMajors; self.computeUnits = computeUnits
        self.specializationReserveBytes = specializationReserveBytes; self.files = files
    }
    public static let maximumManifestBytes = 1_048_576
    public static let chunkBytes: Int64 = 4 * 1_048_576

    public func canonicalData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumManifestBytes else { throw SpeechPackageError.invalidManifest }
        let value = try JSONDecoder().decode(Self.self, from: data)
        // Canonical encoding rejects duplicate JSON keys, unknown fields and ambiguous number encodings.
        // The publisher emits these exact bytes, without a trailing newline.
        guard try value.canonicalData() == data else { throw SpeechPackageError.invalidManifest }
        try value.validate()
        return value
    }
    public var downloadBytes: Int64 { files.reduce(0) { $0 + $1.bytes } } // Only use after validate().
    public func supports(hardware: String, osMajor: Int) -> Bool {
        self.hardware.contains(hardware) && osMajors.contains(osMajor)
    }
    public func validate() throws {
        guard schema == 1, id.utf8.count <= 80, Self.safeComponent(id), Self.hex(revision, count: 40),
              !hardware.isEmpty, Set(hardware).count == hardware.count,
              hardware.allSatisfy({ $0 == "iPhone18,3" }), // Widen only with separate device qualification.
              osMajors == [27], specializationReserveBytes > 0,
              specializationReserveBytes <= 100_000_000_000,
              !files.isEmpty, files.count <= 10_000 else { throw SpeechPackageError.invalidManifest }
        let expectedPair: LocalSpeechPair = backend == .breezeCoreMLPAL8 ? .taiwanMandarinEnglish : .vietnameseEnglish
        guard pair == expectedPair else { throw SpeechPackageError.invalidManifest }
        // Descriptive compute policy, not guessed Core AI enum raw values. Receipts use actual runtime enums.
        let expectedCompute = backend == .breezeCoreMLPAL8
            ? ["mel": "cpuAndGPU", "encoder": "cpuAndNeuralEngine", "decoder": "cpuAndNeuralEngine"]
            : ["mel": "cpuAndGPU", "encoder": "gpuPreferred", "decoder": "cpuAndNeuralEngine"]
        guard computeUnits == expectedCompute else { throw SpeechPackageError.invalidManifest }
        if backend == .breezeCoreMLPAL8, revision != SpeechPackagePins.breezeRevision {
            throw SpeechPackageError.invalidManifest
        }
        var seen = Set<String>(), total: Int64 = 0
        for file in files {
            try Self.validatePath(file.path)
            let folded = file.path.lowercased()
            guard seen.insert(folded).inserted, file.bytes >= 0, file.bytes <= 20_000_000_000,
                  Self.hex(file.sha256, count: 64) else { throw SpeechPackageError.invalidManifest }
            let (next, overflow) = total.addingReportingOverflow(file.bytes)
            guard !overflow, next <= 50_000_000_000 else { throw SpeechPackageError.invalidManifest }
            total = next
            guard file.path.hasPrefix("support/") || (backend == .phoWhisperCoreAIFP8PAL8 && file.path.hasPrefix("encoder/")) else {
                throw SpeechPackageError.invalidManifest
            }
        }
        guard files.map(\.path) == files.map(\.path).sorted(), total > 0 else { throw SpeechPackageError.invalidManifest }
        // A file cannot also be a parent directory, including on case-insensitive APFS.
        for file in files {
            let components = file.path.lowercased().split(separator: "/")
            for end in 1..<components.count {
                guard !seen.contains(components.prefix(end).joined(separator: "/")) else { throw SpeechPackageError.invalidManifest }
            }
        }
        let supportPin = backend == .breezeCoreMLPAL8 ? SpeechPackagePins.breezeManifest : SpeechPackagePins.phoWhisperSupportManifest
        let requiredSupport = ["manifest.json", "config.json", "generation_config.json", "tokenizer.json", "tokenizer_config.json"] +
            ["MelSpectrogram", "AudioEncoder", "TextDecoder"].flatMap { name in
                ["coremldata.bin", "metadata.json", "model.mil", "weights/weight.bin"].map { "\(name).mlmodelc/\($0)" }
            }
        guard requiredSupport.allSatisfy({ required in files.contains { $0.path == "support/" + required } }),
              files.contains(where: { $0.path == "support/manifest.json" && $0.sha256 == supportPin }) else {
            throw SpeechPackageError.invalidManifest
        }
        if backend == .phoWhisperCoreAIFP8PAL8 {
            guard files.contains(where: { $0.path == "encoder/manifest.json" && $0.sha256 == SpeechPackagePins.phoWhisperEncoderManifest }) else {
                throw SpeechPackageError.invalidManifest
            }
        }
    }
    public static func validatePath(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard path.utf8.count <= 512, !components.isEmpty,
              components.allSatisfy({ safeComponent(String($0)) }) else { throw SpeechPackageError.unsafePath }
    }
    private static func safeComponent(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 255 && value != "." && value != ".." && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0)
        }
    }
    public static func hex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// No silent restart or appending a 200 response to a partial file.
    public static func validateResponse(status: Int, contentRange: String?, offset: Int64,
                                        count: Int64, total: Int64) throws {
        guard offset >= 0, count > 0, total >= count, offset <= total - count else {
            throw SpeechPackageError.rangeUnsupported
        }
        if status == 200, offset == 0, count == total { return }
        guard status == 206, contentRange == "bytes \(offset)-\(offset + count - 1)/\(total)" else {
            throw SpeechPackageError.rangeUnsupported
        }
    }
}

public struct ReviewedSpeechPackage: Sendable {
    public let id: String
    public let pair: LocalSpeechPair
    public let manifestURL: URL
    public let filesURL: URL
    public let manifestSHA256: String
    public let allowedHosts: Set<String>
    public init(id: String, pair: LocalSpeechPair, manifestURL: URL, filesURL: URL,
                manifestSHA256: String, allowedHosts: Set<String>) {
        self.id = id; self.pair = pair; self.manifestURL = manifestURL; self.filesURL = filesURL
        self.manifestSHA256 = manifestSHA256; self.allowedHosts = allowedHosts
    }
    public func permits(_ url: URL) -> Bool {
        url.scheme == "https" && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil &&
        url.host.map { allowedHosts.contains($0.lowercased()) } == true
    }
    public func validate() throws {
        try SpeechPackage.validatePath(id)
        guard id.utf8.count <= 80, !id.contains("/"), SpeechPackage.hex(manifestSHA256, count: 64),
              permits(manifestURL), permits(filesURL) else { throw SpeechPackageError.invalidManifest }
    }
}
