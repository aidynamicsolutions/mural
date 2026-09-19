import Foundation

/// Diagnostic v2 identity only. The caller must verify/pin the artifact and
/// manifest first. A correct marker alone does not attest all weight resources.
/// Kept under Tools until the local agent wires it into the bounded device probe.
struct W8IdentitySpec: Decodable, Sendable {
    let schema: String
    let recipeSHA256: String
    let entrypoint: String
    let markerOutput: String
    let markerDtype: String
    let markerShape: [Int]
    let markerValues: [Int32]

    enum CodingKeys: String, CodingKey {
        case schema, entrypoint
        case recipeSHA256 = "recipe_sha256", markerOutput = "marker_output"
        case markerDtype = "marker_dtype", markerShape = "marker_shape"
        case markerValues = "marker_values"
    }

    func validate() throws {
        let formats: [String: Int] = ["fp16": 16, "fp8": 8, "int8": 9]
        guard schema == "mural-w8-identity-v2", recipeSHA256.count == 64,
              recipeSHA256.allSatisfy({ "0123456789abcdef".contains($0) }),
              markerDtype == "int32", markerShape.count == 1 else {
            throw W8IdentityFailure("Invalid v2 identity specification")
        }
        let suffix = String(recipeSHA256.prefix(20))
        guard formats.contains(where: { format, width in
            markerOutput == "mural_identity_\(format)" && markerShape == [width] &&
            markerValues.count == width &&
            ["mural_tiny_\(format)_\(suffix)", "mural_encoder_\(format)_\(suffix)"].contains(entrypoint)
        }) else { throw W8IdentityFailure("Identity names/shape do not match the recipe") }
        // Bind all returned words to the SHA-256 digest, not just a JSON array.
        let chars = Array(recipeSHA256.utf8)
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(bytes: chars[i...i + 1], encoding: .utf8)!, radix: 16) else {
                throw W8IdentityFailure("Invalid recipe digest")
            }
            bytes.append(byte)
        }
        let words: [Int32] = stride(from: 0, to: 32, by: 4).map { i in
            let value = UInt32(bytes[i]) | (UInt32(bytes[i + 1]) << 8) |
                        (UInt32(bytes[i + 2]) << 16) | (UInt32(bytes[i + 3]) << 24)
            return Int32(bitPattern: value)
        }
        guard markerValues.enumerated().allSatisfy({ $0.element == words[$0.offset % 8] }) else {
            throw W8IdentityFailure("Manifest marker is not bound to its recipe digest")
        }
    }

    func requireFunctions(_ names: [String]) throws {
        try validate()
        guard names == [entrypoint] else {
            throw W8IdentityFailure("Wrong cached model function; do not fall back to main")
        }
    }

    func requireMarker(_ values: [Int32]) throws {
        try validate()
        guard values == markerValues else {
            throw W8IdentityFailure("Wrong cached model marker; no embeddings accepted")
        }
    }
}

struct W8IdentityFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

#if canImport(CoreAI) && !MURAL_W8_IDENTITY_PORTABLE_TEST
import CoreAI

@available(iOS 27.0, macOS 27.0, *)
extension W8IdentitySpec {
    /// Call BEFORE loadFunction(named: entrypoint). Asset selection and cache
    /// admission remain with the existing serialized owner, not this helper.
    func requireModel(_ model: AIModel) throws {
        try requireFunctions(model.functionNames)
    }

    /// Check the returned marker BEFORE making encoder_hidden_states available
    /// to a decoder. Respect physical strides; do not assume contiguous storage.
    func requireMarkerArray(_ marker: NDArray) throws {
        try validate()
        guard marker.scalarType == .int32, marker.shape == markerShape else {
            throw W8IdentityFailure("Wrong native marker dtype or shape")
        }
        let actual = marker.view(as: Int32.self).withUnsafePointer { p, _, strides in
            (0..<markerValues.count).map { p[$0 * strides[0]] }
        }
        try requireMarker(actual)
    }
}
#endif

/// V3 avoids the v2 constant Int32 return. It checks an exact FP16 response to a
/// runtime challenge. This is a diagnostic, NOT cryptographic weight attestation.
/// Keep artifact pins, native cache-isolation tests and numerical oracles as well.
struct W8RuntimeIdentitySpec: Decodable, Sendable {
    let schema: String
    let recipeSHA256: String
    let kind: String
    let format: String
    let transport: String
    let entrypoint: String
    let challengeInput: String
    let challengeShape: [Int]
    let responseOutput: String
    let packedOutput: String
    let markerDtype: String
    let markerValues: [Float]
    let inputShape: [Int]
    let hiddenShape: [Int]

    enum CodingKeys: String, CodingKey {
        case schema, kind, format, transport, entrypoint
        case recipeSHA256 = "recipe_sha256", challengeInput = "challenge_input"
        case challengeShape = "challenge_shape", responseOutput = "response_output"
        case packedOutput = "packed_output", markerDtype = "marker_dtype"
        case markerValues = "marker_values", inputShape = "input_shape", hiddenShape = "hidden_shape"
    }

    var hiddenCount: Int { hiddenShape.reduce(1, *) }
    var packetShape: [Int] { [1, hiddenCount + markerValues.count] }

    func validate() throws {
        let widths = ["fp16": 32, "fp8": 40, "int8": 48, "pal6": 56, "pal4": 64]
        guard schema == "mural-w8-runtime-identity-v3", let width = widths[format],
              ["tiny", "encoder"].contains(kind), ["packed", "split"].contains(transport),
              recipeSHA256.count == 64, recipeSHA256.allSatisfy({ "0123456789abcdef".contains($0) }),
              entrypoint == "mural_v3_\(kind)_\(format)_\(transport)_\(recipeSHA256.prefix(20))",
              markerDtype == "float16", challengeInput == "identity_challenge",
              responseOutput == "identity_response", packedOutput == "encoded_packet",
              challengeShape == [1, width], markerValues.count == width,
              inputShape == (kind == "tiny" ? [1, 64] : [1, 80, 3000]),
              hiddenShape == (kind == "tiny" ? [1, 64] : [1, 1500, 1280]) else {
            throw W8IdentityFailure("Invalid v3 identity/ABI")
        }
        let chars = Array(recipeSHA256.utf8)
        var bytes: [Float] = []
        for i in stride(from: 0, to: 64, by: 2) {
            guard let value = UInt8(String(bytes: chars[i...i + 1], encoding: .utf8)!, radix: 16) else {
                throw W8IdentityFailure("Invalid v3 digest")
            }
            bytes.append(Float(value))
        }
        guard markerValues.enumerated().allSatisfy({ $0.element == bytes[$0.offset % 32] }) else {
            throw W8IdentityFailure("V3 marker is not bound to the pinned recipe")
        }
    }

    func requireFunctions(_ names: [String]) throws {
        try validate()
        guard names == [entrypoint] else { throw W8IdentityFailure("Wrong v3 cached function; no main fallback") }
    }

    func challenge(seed: Int) throws -> [Float16] {
        try validate()
        guard (0...31).contains(seed) else { throw W8IdentityFailure("Invalid challenge seed") }
        return (0..<markerValues.count).map { Float16((seed + $0 * 13) % 32) }
    }

    func requireResponse(_ response: [Float16], challenge: [Float16]) throws {
        try validate()
        guard response.count == markerValues.count, challenge.count == markerValues.count,
              challenge.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 31 && $0.rounded() == $0 }) else {
            throw W8IdentityFailure("Invalid v3 response/challenge")
        }
        for i in markerValues.indices {
            // The sum of these small integers is exactly representable in FP16.
            guard response[i].isFinite, response[i] == Float16(markerValues[i]) + challenge[i] else {
                throw W8IdentityFailure("Wrong or stale runtime marker; no embeddings accepted")
            }
        }
    }

    func unpack(_ values: [Float16], response: [Float16]? = nil,
                challenge: [Float16]) throws -> [Float16] {
        try validate()
        let hidden: [Float16]
        if transport == "packed" {
            guard response == nil, values.count == hiddenCount + markerValues.count else {
                throw W8IdentityFailure("Invalid packed v3 output")
            }
            try requireResponse(Array(values.suffix(markerValues.count)), challenge: challenge)
            hidden = Array(values.prefix(hiddenCount))
        } else {
            guard values.count == hiddenCount, let response else {
                throw W8IdentityFailure("Invalid split v3 output")
            }
            try requireResponse(response, challenge: challenge)
            hidden = values
        }
        guard hidden.allSatisfy(\.isFinite) else { throw W8IdentityFailure("Non-finite v3 hidden output") }
        return hidden
    }
}

#if canImport(CoreAI) && !MURAL_W8_IDENTITY_PORTABLE_TEST
@available(iOS 27.0, macOS 27.0, *)
extension W8RuntimeIdentitySpec {
    func requireModel(_ model: AIModel) throws { try requireFunctions(model.functionNames) }

    /// Only bounded shapes used by the v3 contract. Includes real strides.
    static func readFP16(_ array: NDArray, shape: [Int]) throws -> [Float16] {
        guard array.scalarType == .float16, array.shape == shape,
              shape.first == 1, (shape.count == 2 || shape == [1, 1500, 1280]),
              shape.allSatisfy({ $0 > 0 && $0 <= 1_920_064 }), shape.reduce(1, *) <= 1_920_064 else {
            throw W8IdentityFailure("Unexpected v3 native tensor shape/type")
        }
        return array.view(as: Float16.self).withUnsafePointer { p, _, strides in
            if shape.count == 2 { return (0..<shape[1]).map { p[$0 * strides[1]] } }
            var values = [Float16](repeating: 0, count: 1500 * 1280)
            for t in 0..<1500 { for c in 0..<1280 {
                values[t * 1280 + c] = p[t * strides[1] + c * strides[2]]
            }}
            return values
        }
    }
}
#endif
