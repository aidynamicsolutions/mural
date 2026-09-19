import Foundation

/// Whole-turn qualification policy; never an audio trimmer or an energy gate.
public enum SpeechPresencePolicy {
    public static let sampleRate = 16_000
    public static let chunkSize = 4_096 // FluidAudio 0.15.7 Silero, not upstream's 512.
    public static let threshold: Float = 0.30 // Hypothesis, NOT device-qualified.

    public enum Mode: String, Sendable {
        case off, observe, gate

        public init(arguments: [String]) throws {
            let prefix = "--asr-vad="
            let flags = arguments.filter { $0 == "--asr-vad" || $0.hasPrefix(prefix) }
            guard !flags.isEmpty else { self = .gate; return }
            guard flags.count == 1, flags[0].hasPrefix(prefix),
                  let mode = Self(rawValue: String(flags[0].dropFirst(prefix.count))) else {
                throw ConfigurationError()
            }
            self = mode
        }
    }

    public struct ConfigurationError: LocalizedError {
        public var errorDescription: String? { "Use exactly one --asr-vad=off, observe, or gate argument." }
    }

    /// Window coverage is coarse evidence, NOT the duration of words within a window.
    public struct Evidence: Sendable {
        public let sampleCount: Int
        public private(set) var processedSamples = 0
        public private(set) var windowCount = 0
        public private(set) var activeWindows = 0
        public private(set) var activeWindowSamples = 0
        public private(set) var firstActiveSample: Int?
        public private(set) var lastActiveSampleExclusive: Int?
        public private(set) var maxProbability: Float = 0
        public private(set) var valid = true
        private var probabilitySum: Double = 0

        public init(sampleCount: Int) {
            self.sampleCount = sampleCount
            valid = (1...480_000).contains(sampleCount)
        }

        public mutating func append(probability: Float, sampleCount count: Int) {
            guard valid, count > 0, count == min(chunkSize, sampleCount - processedSamples),
                  probability.isFinite, (0...1).contains(probability) else {
                valid = false
                return
            }
            let start = processedSamples
            processedSamples += count
            windowCount += 1
            probabilitySum += Double(probability)
            maxProbability = max(maxProbability, probability)
            if probability >= threshold {
                activeWindows += 1
                activeWindowSamples += count // Never count repeat-last padding as captured audio.
                if firstActiveSample == nil { firstActiveSample = start }
                lastActiveSampleExclusive = processedSamples
            }
        }

        public var meanProbability: Double { windowCount == 0 ? 0 : probabilitySum / Double(windowCount) }
        public var complete: Bool { valid && processedSamples == sampleCount }
        // One brief active window is enough. Missing/invalid evidence cannot reject speech.
        public var wouldReject: Bool { complete && activeWindows == 0 }
        public func rejects(in mode: Mode) -> Bool { mode == .gate && wouldReject }
    }
}
