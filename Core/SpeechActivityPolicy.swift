import Foundation

/// Qualification policy, not a calibrated production threshold. Preserve short/quiet
/// speech: any positive window keeps the entire, unmodified recording.
public enum SpeechActivityPolicy {
    public static let sampleRate = 16_000
    public static let windowSamples = 4_096
    public static let maximumSamples = 480_000
    public static let threshold: Float = 0.30

    public enum Mode: String, Sendable {
        case off, observe, gate

        public static func resolve(_ arguments: [String]) throws -> Self {
            let flags = arguments.filter { $0.hasPrefix("--speech-vad") }
            guard !flags.isEmpty else { return .off }
            guard flags.count == 1,
                  let mode = Self(rawValue: String(flags[0].dropFirst("--speech-vad=".count))),
                  flags[0] == "--speech-vad=\(mode.rawValue)" else {
                throw ConfigurationError.invalidMode
            }
            return mode
        }
    }

    public enum ConfigurationError: LocalizedError {
        case invalidMode
        public var errorDescription: String? {
            "Use exactly one --speech-vad=off, --speech-vad=observe, or --speech-vad=gate argument."
        }
    }

    public enum Decision: String, Sendable { case speech, noSpeech, inconclusive }

    public struct Evidence: Sendable {
        public let decision: Decision
        public let activeWindowCount: Int
        public let activeSampleCount: Int
        public let firstActiveSample: Int?
        public let lastActiveSample: Int? // Exclusive; clipped to real audio, never padded length.
    }

    public static func assess(sampleCount: Int, probabilities: [Float]) -> Evidence {
        let unknown = Evidence(decision: .inconclusive, activeWindowCount: 0,
                               activeSampleCount: 0, firstActiveSample: nil, lastActiveSample: nil)
        guard (0...maximumSamples).contains(sampleCount),
              probabilities.count == (sampleCount + windowSamples - 1) / windowSamples,
              probabilities.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return unknown }
        var activeWindows = 0, activeSamples = 0
        var first: Int?, last: Int?
        for (index, probability) in probabilities.enumerated() where probability >= threshold {
            let start = index * windowSamples
            let end = min(start + windowSamples, sampleCount)
            activeWindows += 1; activeSamples += end - start
            if first == nil { first = start }
            last = end
        }
        // Do not reject a nonempty recording shorter than one model window.
        // A low final window must never override an earlier speech burst.
        let decision: Decision = activeWindows > 0 ? .speech
            : sampleCount > 0 && sampleCount < windowSamples ? .inconclusive : .noSpeech
        return Evidence(decision: decision, activeWindowCount: activeWindows,
                        activeSampleCount: activeSamples, firstActiveSample: first, lastActiveSample: last)
    }

    public static func shouldReject(_ decision: Decision, mode: Mode) -> Bool {
        mode == .gate && decision == .noSpeech
    }
}
