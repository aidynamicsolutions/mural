#if (DEBUG || MURAL_COREAI_W8) && canImport(CoreAI)
import CoreAI
import CryptoKit
import Foundation

/// V3 computed FP16 marker. One attempt per process; never changes normal Talk.
/// A diagnosed compiler failure may be repaired and tested in a NEW process by
/// the local agent. It must not be retried blindly by this runtime owner.
actor W8TinyProbe {
    static let shared = W8TinyProbe()
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("--w8-tiny") }
    private var attempted = false
    private struct Manifest: Decodable {
        struct Vector: Decodable { let input: [[Float]]; let uncompressed_output: [[Float]] }
        struct Artifact: Decodable { let path: String; let fingerprint: String; let bytes: Int }
        let schema: String
        let status: String
        let identity: W8RuntimeIdentitySpec
        let aot: Artifact
        let source: Artifact
        let tiny_vectors: [Vector]
        let tiny_max_abs_error_bound: Float
    }

    func run(directory: URL, warningCount: @escaping @Sendable () async -> Int) async throws {
        guard !attempted else { throw W8IdentityFailure("Tiny probe already attempted; no automatic retry") }
        attempted = true
        let args = ProcessInfo.processInfo.arguments
        let flags = args.filter { $0.hasPrefix("--w8-tiny") }
        let transportFlags = flags.filter { $0.hasPrefix("--w8-tiny-transport=") }
        guard Set(flags).count == flags.count, transportFlags.count <= 1,
              flags.allSatisfy({ ["--w8-tiny", "--w8-tiny-reverse", "--w8-tiny-source"].contains($0)
                  || $0.hasPrefix("--w8-tiny-transport=") }) else {
            throw W8IdentityFailure("Invalid/duplicate tiny flags")
        }
        let transport = transportFlags.first.map { String($0.dropFirst("--w8-tiny-transport=".count)) } ?? "packed"
        let reverse = args.contains("--w8-tiny-reverse")
        let sourceDiagnostic = args.contains("--w8-tiny-source")
        guard ["packed", "split"].contains(transport), !(sourceDiagnostic && reverse) else {
            throw W8IdentityFailure("Invalid transport/source/reverse combination")
        }
        let root = URL.documentsDirectory.appending(path: "CoreAI/W8TinyV3/\(transport)")
        let order = sourceDiagnostic ? ["fp16"] : (reverse
            ? ["int8", "fp8", "fp16", "int8", "fp8", "fp16"]
            : ["fp16", "fp8", "int8", "fp16", "fp8", "int8"])
        // Complete manifests pin recipe, artifacts, ABI and synthetic vectors.
        for format in Set(order) {
            guard Self.manifestPins["\(transport):\(format)"] != nil else {
                throw W8IdentityFailure("Missing v3 build pin for \(transport):\(format). Generate audited manifests and insert --print-swift-pins output; never reuse v2 pins.")
            }
        }
        var prior: [String: [String]] = [:]
        for (index, format) in order.enumerated() {
            try Task.checkCancellation()
            guard await warningCount() == 0 else { throw W8IdentityFailure("Memory warning latched") }
            let hashes: [String]
            do {
                // No model/function/tensor crosses this awaited scope boundary.
                hashes = try await scope(format, transport: transport, root: root, directory: directory,
                    requireCached: reverse || index >= 3, sourceDiagnostic: sourceDiagnostic,
                    visit: index, warningCount: warningCount)
                try event(directory, "scope-returned", ["format": format, "success": true])
            } catch {
                try? event(directory, "scope-returned", ["format": format, "success": false,
                    "error": String(reflecting: error)])
                throw error
            }
            if let previous = prior[format], previous != hashes {
                throw W8IdentityFailure("Repeated hidden output changed for \(format)")
            }
            prior[format] = hashes
        }
        try event(directory, sourceDiagnostic ? "source-diagnostic-complete" : "tiny-complete",
            ["reverse": reverse, "transport": transport,
             "scope": sourceDiagnostic ? "fp16-source-only-not-isolation" : "v3-trio-one-sequence"])
    }

    private func scope(_ format: String, transport: String, root: URL, directory: URL,
                       requireCached: Bool, sourceDiagnostic: Bool, visit: Int,
                       warningCount: @escaping @Sendable () async -> Int) async throws -> [String] {
        let folder = root.appending(path: "tiny-\(format)")
        let manifestURL = folder.appending(path: "manifest.json")
        let size = try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 2_000_000 else { throw W8IdentityFailure("Unexpected tiny manifest size") }
        let data = try Data(contentsOf: manifestURL)
        guard Self.hash(data) == Self.manifestPins["\(transport):\(format)"] else {
            throw W8IdentityFailure("Manifest pin mismatch")
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        let spec = manifest.identity
        try spec.validate()
        guard manifest.schema == "mural-w8-runtime-identity-v3", manifest.status == "aot-static-only",
              spec.kind == "tiny", spec.format == format, spec.transport == transport,
              manifest.tiny_vectors.count == 3, manifest.tiny_max_abs_error_bound == 0.05 else {
            throw W8IdentityFailure("Tiny v3 manifest contract changed")
        }
        let artifact = sourceDiagnostic ? manifest.source : manifest.aot
        guard artifact.bytes > 0, artifact.bytes <= 16_777_216 else {
            throw W8IdentityFailure("Not a bounded tiny artifact")
        }
        let url = folder.appending(path: (sourceDiagnostic ? "" : "aot/")
            + URL(fileURLWithPath: artifact.path).lastPathComponent)
        guard url.pathExtension == (sourceDiagnostic ? "aimodel" : "aimodelc"),
              try Self.fingerprint(url) == artifact.fingerprint else {
            throw W8IdentityFailure("Artifact pin mismatch")
        }
        let options = SpecializationOptions(preferredComputeUnitKind: .gpu)
        try event(directory, "load-begin", ["format": format, "entrypoint": spec.entrypoint,
            "artifact": artifact.fingerprint, "sourceDiagnostic": sourceDiagnostic,
            "manifest": Self.hash(data), "transport": transport])
        let cached = try AIModelCache.default.model(for: url, options: options)
        try event(directory, "cache-lookup", ["format": format, "hit": cached != nil, "required": requireCached])
        guard !requireCached || cached != nil else { throw W8IdentityFailure("Required cache hit absent; not a wrong-output result") }
        let model: AIModel
        if let cached { model = cached }
        else {
            do { model = try await AIModel.specialize(contentsOf: url, options: options, cachePolicy: .persistent) }
            catch {
                try event(directory, "specialization-failed", ["format": format,
                    "error": String(reflecting: error), "transport": transport])
                throw error
            }
        }
        try Task.checkCancellation()
        guard await warningCount() == 0 else { throw W8IdentityFailure("Memory warning latched") }
        try spec.requireModel(model)
        guard let descriptor = model.functionDescriptor(for: spec.entrypoint),
              case .ndArray(let inputDescriptor) = descriptor.inputDescriptor(of: "input_features"),
              inputDescriptor.shape == spec.inputShape, inputDescriptor.scalarType == .float16,
              case .ndArray(let nonceDescriptor) = descriptor.inputDescriptor(of: spec.challengeInput),
              nonceDescriptor.shape == spec.challengeShape, nonceDescriptor.scalarType == .float16 else {
            throw W8IdentityFailure("Native v3 input ABI mismatch")
        }
        if transport == "packed" {
            guard case .ndArray(let packet) = descriptor.outputDescriptor(of: spec.packedOutput),
                  packet.shape == spec.packetShape, packet.scalarType == .float16 else {
                throw W8IdentityFailure("Native packed output ABI mismatch")
            }
        } else {
            guard case .ndArray(let hidden) = descriptor.outputDescriptor(of: "encoder_hidden_states"),
                  hidden.shape == spec.hiddenShape, hidden.scalarType == .float16,
                  case .ndArray(let response) = descriptor.outputDescriptor(of: spec.responseOutput),
                  response.shape == spec.challengeShape, response.scalarType == .float16 else {
                throw W8IdentityFailure("Native split output ABI mismatch")
            }
        }
        guard let function = try model.loadFunction(named: spec.entrypoint) else {
            throw W8IdentityFailure("Named function absent; no main fallback")
        }
        try event(directory, "load-complete", ["format": format])
        var hashes: [String] = []
        for (index, vector) in manifest.tiny_vectors.enumerated() {
            let expected = vector.uncompressed_output.flatMap { $0 }
            let source = vector.input.flatMap { $0 }
            guard source.count == 64, expected.count == 64, source.allSatisfy(\.isFinite),
                  expected.allSatisfy(\.isFinite) else { throw W8IdentityFailure("Invalid synthetic vector") }
            let values = source.map(Float16.init)
            guard values.allSatisfy(\.isFinite) else { throw W8IdentityFailure("Synthetic input overflows FP16") }
            var referenceHash: String?
            // Same numerical input, CHANGING runtime challenge. This catches a
            // constant/baked marker and stale output without touching hidden math.
            for seed in [0, 7, 23].map({ ($0 + visit) % 32 }) {
                try Task.checkCancellation()
                guard await warningCount() == 0 else { throw W8IdentityFailure("Memory warning latched") }
                let nonceValues = try spec.challenge(seed: seed)
                var input = NDArray(descriptor: inputDescriptor)
                do { var view = input.mutableView(as: Float16.self); view.copyElements(fromContentsOf: values) }
                var nonce = NDArray(descriptor: nonceDescriptor)
                do { var view = nonce.mutableView(as: Float16.self); view.copyElements(fromContentsOf: nonceValues) }
                let inputHash = values.withUnsafeBytes { Self.hash(Data($0)) }
                try event(directory, "inference-begin", ["format": format, "vector": index,
                    "challengeSeed": seed, "inputSHA256": inputHash])
                let started = ProcessInfo.processInfo.systemUptime
                var output = try await function.run(inputs: ["input_features": input, spec.challengeInput: nonce])
                let nativeSeconds = ProcessInfo.processInfo.systemUptime - started
                let copyStart = ProcessInfo.processInfo.systemUptime
                let owned: [Float16]
                if transport == "packed" {
                    guard let packet = output.remove(spec.packedOutput)?.ndArray else {
                        throw W8IdentityFailure("Missing computed packet")
                    }
                    let all = try W8RuntimeIdentitySpec.readFP16(packet, shape: spec.packetShape)
                    owned = try spec.unpack(all, challenge: nonceValues)
                } else {
                    guard let hidden = output.remove("encoder_hidden_states")?.ndArray,
                          let response = output.remove(spec.responseOutput)?.ndArray else {
                        throw W8IdentityFailure("Missing computed split outputs")
                    }
                    let hiddenValues = try W8RuntimeIdentitySpec.readFP16(hidden, shape: spec.hiddenShape)
                    let responseValues = try W8RuntimeIdentitySpec.readFP16(response, shape: spec.challengeShape)
                    owned = try spec.unpack(hiddenValues, response: responseValues, challenge: nonceValues)
                }
                let error = zip(owned, expected).map { abs(Float($0) - $1) }.max()!
                let hash = owned.withUnsafeBytes { Self.hash(Data($0)) }
                try event(directory, "numerical-output", ["format": format, "vector": index,
                    "challengeSeed": seed, "markerVerified": true, "inputSHA256": inputHash,
                    "outputSHA256": hash, "values": owned.map(Float.init), "maxAbsoluteError": error,
                    "nativeSeconds": nativeSeconds,
                    "validationCopySeconds": ProcessInfo.processInfo.systemUptime - copyStart])
                guard error <= manifest.tiny_max_abs_error_bound else { throw W8IdentityFailure("Wrong numerical output") }
                if let referenceHash, hash != referenceHash { throw W8IdentityFailure("Challenge changed hidden values") }
                referenceHash = hash
                guard await warningCount() == 0 else { throw W8IdentityFailure("Memory warning latched") }
                try Task.checkCancellation()
            }
            guard let referenceHash else { throw W8IdentityFailure("No numerical output checked") }
            hashes.append(referenceHash)
        }
        return hashes
    }

    private func event(_ directory: URL, _ stage: String, _ fields: [String: Any]) throws {
        var row = fields
        row["stage"] = stage
        row["uptime"] = ProcessInfo.processInfo.systemUptime
        row["thermalState"] = ProcessInfo.processInfo.thermalState.rawValue
        row["memory"] = VietnameseEnglishRecognizer.logMemory(stage: stage, model: "w8-tiny-v3")
        let url = directory.appending(path: "tiny-events.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url, options: .withoutOverwriting) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) + Data([10]))
        try handle.synchronize()
    }

    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func fingerprint(_ url: URL) throws -> String {
        let info = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
        guard info.isSymbolicLink != true else { throw W8IdentityFailure("Symlink in artifact") }
        if info.isRegularFile == true {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var digest = SHA256()
            while try autoreleasepool(invoking: { () throws -> Bool in
                guard let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty else { return false }
                digest.update(data: chunk); return true
            }) {}
            return digest.finalize().map { String(format: "%02x", $0) }.joined()
        }
        guard info.isDirectory == true else { throw W8IdentityFailure("Invalid artifact file") }
        var children: [String: String] = [:]
        for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            children[child.lastPathComponent] = try fingerprint(child)
        }
        return hash(try JSONSerialization.data(withJSONObject: children, options: [.sortedKeys, .withoutEscapingSlashes]))
    }

    // Local BUILD step: insert actual --print-swift-pins lines after the v3 audit.
    // Empty by design: generated AOT bytes do not exist on the connector host.
    // This is a routine pin-generation step, NOT a reason to abandon the task.
    private static let manifestPins: [String: String] = [
        "unqualified:no-assets": "", // Not a candidate; keeps the placeholder a dictionary literal.
        // BEGIN W8_V3_PINS
        "packed:fp16": "773e442a49b4261ec60ee8874cb538223b37a2dd0d0a53235c797898cf2782d1",
        "packed:fp8": "3df5ae743d2c34bad77578afd3531eeae850c7b2da0632d19c55f0ea3f234f21",
        "packed:int8": "1dde35bf9f2e4deac1066400639de3dbff5cfa9b20e38a7f5a1d47a754b4e5b7",
        // END W8_V3_PINS
    ]

    static let fullManifestPins: [String: String] = [
        // BEGIN W8_V3_FULL_PINS
        "packed:fp16": "3c87a4cc096d842c2ddb530d23ec2c808c034da5839f1589dde26a13582d9b14",
        "packed:fp8": "73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13",
        "packed:int8": "93b4706943dcc5612d67c73d7f6a6ab11acb48fe1d588d7e3510a4133f081acc",
        "packed:pal6": "b3437340b110c14349cd3f12ae0955adb8254fdc277e263907eaa3d96e651966",
        "packed:pal4": "96c7c788ec49b76aa8a4d52ac961a1f93869676d05fcb5109eeb8be581bf765f",
        // END W8_V3_FULL_PINS
    ]
}
#endif
