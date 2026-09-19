import Foundation

/// Explicit offline trials only. No model ownership, cache mutation or default switch.
enum DecoderTrialPolicy {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let combinedFlag = "--coreai-w8-v3-combined=pal6-pal6"
    static let combined4Flag = "--coreai-w8-v3-combined=pal4-pal4"

    /// The extra flag is required ONLY for the previously unqualified joint pair.
    /// The runtime still checks the h18p build, pinned manifests, ABI and response.
    static func combined(_ arguments: [String]) throws -> Bool {
        let flags = arguments.filter { $0.hasPrefix("--coreai-w8-v3-combined") }
        guard flags.count <= 1 else { throw Failure(message: "Duplicate combined precision trial flag") }
        guard let flag = flags.first else { return false }
        let pair: (String, String)
        switch flag {
        case combinedFlag: pair = ("pal6", "pal6")
        case combined4Flag: pair = ("pal4", "pal4")
        default: throw Failure(message: "Unknown combined precision trial")
        }
        guard arguments.filter({ $0.hasPrefix("--coreai-w8-v3-encoder=") }) == ["--coreai-w8-v3-encoder=\(pair.0)"],
              arguments.filter({ $0.hasPrefix("--coreai-w8-v3-decoder=") }) == ["--coreai-w8-v3-decoder=\(pair.1)"],
              !arguments.contains(where: { $0.hasPrefix("--coreai-compressed-encoder=") }) else {
            throw Failure(message: "Combined trial requires matching explicit PAL4 or PAL6 encoder and decoder")
        }
        let product = arguments.contains { $0.hasPrefix("--coreai-product-") }
        let modes = arguments.filter { $0.hasPrefix("--coreai-product-mode=") }
        guard !product || modes == ["--coreai-product-mode=staged-gpu"] ||
                modes == ["--coreai-product-mode=staged-gpu-encode"] else {
            throw Failure(message: "Combined trial requires the sequential GPU owner or explicit live Talk")
        }
        guard !arguments.contains("--coreai-product-coexistence") else {
            throw Failure(message: "Combined precision qualification does not authorize concurrent probe companions")
        }
        return true
    }

    static func validatePair(encoder: String, decoder: String, arguments: [String]) throws {
        let joint = try combined(arguments)
        guard ["fp16", "fp8", "int8", "pal6", "pal4"].contains(encoder),
              ["fp16", "pal8", "pal6", "pal4"].contains(decoder) else {
            throw Failure(message: "Unknown encoder/decoder precision")
        }
        guard !joint || (encoder == "pal6" && decoder == "pal6") ||
                (encoder == "pal4" && decoder == "pal4") else {
            throw Failure(message: "Combined flag does not match the resolved pair")
        }
        guard decoder != "pal6" || encoder == "fp8" || (joint && encoder == "pal6") else {
            throw Failure(message: "PAL6 decoder requires fixed FP8 or the explicit combined PAL6 trial")
        }
        guard decoder != "pal4" || encoder == "fp8" || (joint && encoder == "pal4") else {
            throw Failure(message: "PAL4 decoder requires fixed FP8 or the explicit combined PAL4 trial")
        }
        guard encoder != "pal6" || decoder == "pal8" || (joint && decoder == "pal6") else {
            throw Failure(message: "PAL6 encoder requires PAL8 or the explicit combined PAL6 trial")
        }
        guard encoder != "pal4" || decoder == "pal8" || (joint && decoder == "pal4") else {
            throw Failure(message: "PAL4 encoder requires PAL8 or the explicit combined PAL4 trial")
        }
    }

    static func once(_ arguments: [String]) throws -> Bool {
        let joint = try combined(arguments) // Reject stray flags even with the default policy.
        let prefix = "--coreai-w8-v3-prewarm="
        let flags = arguments.filter { $0.hasPrefix("--coreai-w8-v3-prewarm") }
        guard flags.count <= 1 else { throw Failure(message: "Duplicate decoder prewarm policy") }
        guard let flag = flags.first else { return false } // Default is unchanged: always.
        guard [prefix + "always", prefix + "once"].contains(flag) else {
            throw Failure(message: "Decoder prewarm policy must be always or once")
        }
        let encoders = arguments.filter { $0.hasPrefix("--coreai-w8-v3-encoder=") }
        let decoders = arguments.filter { $0.hasPrefix("--coreai-w8-v3-decoder=") }
        let fixedFP8 = encoders == ["--coreai-w8-v3-encoder=fp8"] && decoders.count == 1 &&
            ["--coreai-w8-v3-decoder=pal8", "--coreai-w8-v3-decoder=pal6", "--coreai-w8-v3-decoder=pal4"].contains(decoders[0])
        // Explicit always also supports the historical encoder-only controls.
        let encoderControl = (encoders == ["--coreai-w8-v3-encoder=pal6"] ||
            encoders == ["--coreai-w8-v3-encoder=pal4"]) &&
            decoders == ["--coreai-w8-v3-decoder=pal8"] && flag == prefix + "always"
        guard fixedFP8 || joint || encoderControl else {
            throw Failure(message: "Prewarm policy requires an explicit qualified precision trial")
        }
        let modes = arguments.filter { $0.hasPrefix("--coreai-product-mode=") }
        let product = arguments.contains { $0.hasPrefix("--coreai-product-") }
        let encodeOnly = joint && flag == prefix + "always" && modes == ["--coreai-product-mode=staged-gpu-encode"]
        guard !product || modes == ["--coreai-product-mode=staged-gpu"] || encodeOnly else {
            throw Failure(message: "Prewarm experiment requires sequential staged-gpu mode or live Talk")
        }
        return flag == prefix + "once" // Joint once is a LATER, separately reviewed policy experiment.
    }
}
