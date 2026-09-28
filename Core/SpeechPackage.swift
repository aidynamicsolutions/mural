import Foundation

/// Pins originate in the reviewed local artifacts, never in the downloaded metadata itself.
public enum SpeechPackagePins {
    public static let fireRedRevision = "374cff185e952c40fcf2f6da972a3b6cf340608d"
    public static let fireRedFiles: [SpeechPackage.File] = [
        .init(path: "support/decoder.int8.onnx", bytes: 417_291_928,
              sha256: "b840ce7196ae4a14d05ae84bbf56082b6b61ccec5610fda907dddbcea37354ff", downloadPath: "decoder.int8.onnx"),
        .init(path: "support/encoder.int8.onnx", bytes: 817_286_833,
              sha256: "54048d66b6e8f3c80ea7ce95efe794587b0fd81d7271651d0decd3803852ae82", downloadPath: "encoder.int8.onnx"),
        .init(path: "support/tokens.txt", bytes: 79_172,
              sha256: "1bc613de2112d257e61a349c3e72d1b1a9cf19c33d3ca954197ad2171e5ea07b", downloadPath: "tokens.txt")
    ]
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
    public enum Backend: String, Codable, Sendable { case breezeCoreMLPAL8, phoWhisperCoreAIFP8PAL8, fireRedASR2Int8 }
    public struct File: Codable, Equatable, Sendable {
        public let path: String
        public let bytes: Int64
        public let sha256: String
        /// Explicit relative upstream name, only allowed by the reviewed FireRed contract.
        /// Nil preserves the original canonical Core ML manifest bytes.
        public let downloadPath: String?
        public init(path: String, bytes: Int64, sha256: String, downloadPath: String? = nil) {
            self.path = path; self.bytes = bytes; self.sha256 = sha256; self.downloadPath = downloadPath
        }
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
              osMajors == [27], specializationReserveBytes >= 0,
              specializationReserveBytes <= 100_000_000_000,
              !files.isEmpty, files.count <= 10_000 else { throw SpeechPackageError.invalidManifest }
        let expectedPair: LocalSpeechPair
        let expectedCompute: [String: String]
        switch backend {
        case .breezeCoreMLPAL8:
            expectedPair = .taiwanMandarinEnglish
            expectedCompute = ["mel": "cpuAndGPU", "encoder": "cpuAndNeuralEngine", "decoder": "cpuAndNeuralEngine"]
            guard revision == SpeechPackagePins.breezeRevision else { throw SpeechPackageError.invalidManifest }
        case .phoWhisperCoreAIFP8PAL8:
            expectedPair = .vietnameseEnglish
            expectedCompute = ["mel": "cpuAndGPU", "encoder": "gpuPreferred", "decoder": "cpuAndNeuralEngine"]
        case .fireRedASR2Int8:
            expectedPair = .mainlandMandarinEnglish
            expectedCompute = ["recognizer": "cpu"]
            // Existing exported ONNX graphs need no on-disk native specialization.
            // Download buffers/metadata are budgeted by the installer; VAD/voice separately.
            guard revision == SpeechPackagePins.fireRedRevision,
                  files == SpeechPackagePins.fireRedFiles, specializationReserveBytes == 0 else {
                throw SpeechPackageError.invalidManifest
            }
        }
        guard pair == expectedPair, computeUnits == expectedCompute,
              backend == .fireRedASR2Int8 || specializationReserveBytes > 0 else {
            throw SpeechPackageError.invalidManifest
        }
        var seen = Set<String>(), total: Int64 = 0
        for file in files {
            try Self.validatePath(file.path)
            if let downloadPath = file.downloadPath {
                try Self.validatePath(downloadPath)
                guard backend == .fireRedASR2Int8 else { throw SpeechPackageError.invalidManifest }
            }
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
        if backend == .fireRedASR2Int8 { return } // Exact three-file contract checked above.
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
    public enum Manifest: Sendable { case remote(URL), bundled(Data) }
    public let manifest: Manifest
    public let filesURL: URL
    public let manifestSHA256: String
    public let allowedHosts: Set<String>
    public init(id: String, pair: LocalSpeechPair, manifestURL: URL, filesURL: URL,
                manifestSHA256: String, allowedHosts: Set<String>) {
        self.id = id; self.pair = pair; self.manifest = .remote(manifestURL); self.filesURL = filesURL
        self.manifestSHA256 = manifestSHA256; self.allowedHosts = allowedHosts
    }
    public init(id: String, pair: LocalSpeechPair, bundledManifest: Data, filesURL: URL,
                manifestSHA256: String, allowedHosts: Set<String>) {
        self.id = id; self.pair = pair; self.manifest = .bundled(bundledManifest); self.filesURL = filesURL
        self.manifestSHA256 = manifestSHA256; self.allowedHosts = allowedHosts
    }
    private static let fireRedRepository = "csukuangfj2/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26"
    private static var fireRedPrefix: String { "/\(fireRedRepository)/resolve/\(SpeechPackagePins.fireRedRevision)/" }
    private static func secure(_ url: URL) -> Bool {
        url.scheme == "https" && (url.port == nil || url.port == 443) && url.user == nil &&
        url.password == nil && url.fragment == nil
    }
    public func permits(_ url: URL) -> Bool {
        guard Self.secure(url), url.query == nil, url.host.map({ allowedHosts.contains($0.lowercased()) }) == true else { return false }
        if pair == .mainlandMandarinEnglish {
            let originals = [Self.fireRedPrefix] + SpeechPackagePins.fireRedFiles.compactMap { file in
                file.downloadPath.map { Self.fireRedPrefix + $0 }
            }
            return originals.contains { url.absoluteString == "https://huggingface.co" + $0 }
        }
        return true
    }
    /// A signed URL is a redirect destination only, never an initial metadata/file URL.
    /// Pins below are the observed immutable Xet object paths, not generic CDN access.
    /// Query values stay opaque; exact downloaded size/range and SHA-256 remain authoritative.
    public func permitsRedirect(_ url: URL, from original: URL) -> Bool {
        guard permits(original), Self.secure(url) else { return false }
        guard pair == .mainlandMandarinEnglish else { return permits(url) }
        guard url.absoluteString.utf8.count <= 8192,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.percentEncodedPath == components.path,
              let items = components.queryItems,
              Set(items.map(\.name)).count == items.count,
              items.allSatisfy({ $0.value != nil }) else { return false }
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        if original.path == Self.fireRedPrefix + "tokens.txt" {
            return url.host == "huggingface.co" &&
                url.path == "/api/resolve-cache/models/\(Self.fireRedRepository)/\(SpeechPackagePins.fireRedRevision)/tokens.txt" &&
                values == [original.path: "", "etag": "\"50ac9cbd43d638b58f875e90b118ad8c9be51718\""]
        }
        guard items.allSatisfy({ $0.value?.isEmpty == false }) else { return false }
        let object: String
        switch original.path {
        case Self.fireRedPrefix + "encoder.int8.onnx": object = "f3d27ecf7506f46197f32617267f90ea8bfbbb3d35ed6ac3bb7434c74e6983d4"
        case Self.fireRedPrefix + "decoder.int8.onnx": object = "2760d7febf8699005dce85a8ca2d19f9164e066972859f9fb9a77f5be09b98a5"
        default: return false
        }
        return url.host == "us.aws.cdn.hf.co" && url.path == "/xet-bridge-us/699fdbe0354974651916cf42/\(object)" &&
            Set(values.keys) == ["Expires", "Hash-Algorithm", "Key-Pair-Id", "Policy", "Signature", "X-Xet-Cas-Uid", "response-content-disposition", "user_id", "xip"] &&
            values["Hash-Algorithm"] == "SHA256" && values["Expires"].flatMap(UInt64.init) != nil
    }
    public func validate() throws {
        try SpeechPackage.validatePath(id)
        guard id.utf8.count <= 80, !id.contains("/"), SpeechPackage.hex(manifestSHA256, count: 64),
              permits(filesURL) else { throw SpeechPackageError.invalidManifest }
        switch manifest {
        case .remote(let url):
            guard permits(url) else { throw SpeechPackageError.invalidManifest }
        case .bundled(let data):
            let package = try SpeechPackage.decode(data)
            guard package.id == id, package.pair == pair else { throw SpeechPackageError.invalidManifest }
        }
    }
}
