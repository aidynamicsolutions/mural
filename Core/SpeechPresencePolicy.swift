import Foundation

/// Whole-turn qualification followed by conservative silence trimming; never an energy gate.
public enum SpeechPresencePolicy {
    public static let sampleRate = 16_000
    public static let chunkSize = 4_096 // FluidAudio 0.15.7 Silero, not upstream's 512.
    public static let threshold: Float = 0.30
    public static let speechScoreThreshold: Float = 0.85 // Mean of the three strongest windows.
    // Whole 256 ms windows: protect uncertain word boundaries and keep natural pauses.
    public static let preRollSamples = 2 * chunkSize // 512 ms before an active window.
    public static let hangoverSamples = 4 * chunkSize // 1,024 ms after an active window.
    public static let minimumRemovedSamples = 8 * chunkSize // 2,048 ms: leave modest silence untouched.

    public struct Analysis: Sendable {
        public let samples: [Float]
        /// Half-open ranges in the original 16 kHz PCM, not in the concatenated output.
        public let regions: [Range<Int>]
        public let rejected: Bool
        public let failedOpen: Bool
    }

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
        private var strongestProbability: Float = 0
        private var secondStrongestProbability: Float = 0
        private var thirdStrongestProbability: Float = 0
        private var paddedRegions: [Range<Int>] = []

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
            if probability > strongestProbability {
                thirdStrongestProbability = secondStrongestProbability
                secondStrongestProbability = strongestProbability
                strongestProbability = probability
            } else if probability > secondStrongestProbability {
                thirdStrongestProbability = secondStrongestProbability
                secondStrongestProbability = probability
            } else if probability > thirdStrongestProbability {
                thirdStrongestProbability = probability
            }
            if probability >= threshold {
                activeWindows += 1
                activeWindowSamples += count // Never count repeat-last padding as captured audio.
                if firstActiveSample == nil { firstActiveSample = start }
                lastActiveSampleExclusive = processedSamples
                // One active window is enough for local onset AFTER the whole-turn gate.
                // Requiring consecutive 256 ms windows could drop a short No or number.
                let region = max(0, start - preRollSamples)..<min(sampleCount, processedSamples + hangoverSamples)
                if let last = paddedRegions.last, region.lowerBound - last.upperBound < minimumRemovedSamples {
                    paddedRegions[paddedRegions.count - 1] = last.lowerBound..<region.upperBound
                } else {
                    paddedRegions.append(region)
                }
            }
        }

        public var meanProbability: Double { windowCount == 0 ? 0 : probabilitySum / Double(windowCount) }
        public var speechScore: Float {
            windowCount < 3 ? 0 : (strongestProbability + secondStrongestProbability + thirdStrongestProbability) / 3
        }
        public var complete: Bool { valid && processedSamples == sampleCount }
        // Three strong windows preserve tested quiet Yes/No while rejecting observed fan and breathing spikes.
        public var wouldReject: Bool { complete && speechScore < speechScoreThreshold }
        public func rejects(in mode: Mode) -> Bool { mode == .gate && wouldReject }

        /// No PCM leaves this turn until all evidence qualifies. Missing/bad evidence
        /// returns the original PCM; off and observe never trim or reject.
        public func analyze(_ samples: [Float], mode: Mode) -> Analysis {
            let usable = complete && samples.count == sampleCount
            let original = Analysis(samples: samples, regions: samples.isEmpty ? [] : [0..<samples.count],
                                    rejected: false, failedOpen: mode != .off && !usable)
            guard mode == .gate, usable else { return original }
            guard !wouldReject else {
                return Analysis(samples: [], regions: [], rejected: true, failedOpen: false)
            }
            guard !paddedRegions.isEmpty else {
                return Analysis(samples: samples, regions: original.regions, rejected: false, failedOpen: true)
            }
            var regions = paddedRegions
            if regions[0].lowerBound < minimumRemovedSamples {
                regions[0] = 0..<regions[0].upperBound
            }
            let last = regions.count - 1
            if sampleCount - regions[last].upperBound < minimumRemovedSamples {
                regions[last] = regions[last].lowerBound..<sampleCount
            }
            guard regions != original.regions else { return original }
            return Analysis(samples: regions.flatMap { samples[$0] }, regions: regions,
                            rejected: false, failedOpen: false)
        }
    }
}
