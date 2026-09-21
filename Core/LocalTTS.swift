import Foundation

/// Shared validation, not a provider abstraction. Audio remains at its native rate.
public struct LocalTTSAudio: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    public var duration: Double { Double(samples.count) / sampleRate }
    public var hasClipping: Bool { samples.contains { abs($0) >= 1 } }

    public init(samples: [Float], sampleRate: Double) throws {
        guard sampleRate.isFinite, (8_000...96_000).contains(sampleRate),
              !samples.isEmpty, Double(samples.count) / sampleRate <= 120,
              samples.allSatisfy(\.isFinite) else { throw LocalTTSError.invalidAudio }
        self.samples = samples
        self.sampleRate = sampleRate
    }

    public static func validatedText(_ text: String) throws -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw LocalTTSError.emptyText }
        guard value.count <= 1_000 else { throw LocalTTSError.textTooLong }
        return value
    }

    /// Conservative preflight for FluidAudio's fixed token window, without duplicating its chunker.
    /// The pinned chunker does not split long individual words; its encoder silently takes a prefix.
    public static func validatedSupertonicText(_ text: String, chunkLimit: Int = 70, tokenLimit: Int = 128) throws -> String {
        let value = try validatedText(text)
        let expanded = value.decomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "@", with: " at ")
            .replacingOccurrences(of: "e.g.,", with: "for example, ")
            .replacingOccurrences(of: "i.e.,", with: "that is, ")
        // Charge the entire passage's expansion to one chunk: conservative, but no hidden truncation.
        // Reserve nine English language-tag scalars and one possible terminal period.
        guard chunkLimit > 0, tokenLimit >= chunkLimit + 10,
              value.split(whereSeparator: \.isWhitespace).allSatisfy({ $0.count <= chunkLimit }),
              expanded.unicodeScalars.count - value.count <= tokenLimit - chunkLimit - 10 else {
            throw LocalTTSError.unsafeSupertonicText
        }
        return value
    }
}

public enum LocalTTSError: LocalizedError {
    case busy, emptyText, textTooLong, invalidAudio, unsafeSupertonicText, phoneTooWarm
    public var errorDescription: String? {
        switch self {
        case .phoneTooWarm: "iOS reports that your iPhone is too warm. Mural has paused speech to protect performance. Let your phone cool down, then tap Resume."
        case .busy: "Speech is still working or stopping. Wait before trying again."
        case .emptyText: "Enter some English text to speak."
        case .textTooLong: "Speech accepts at most 1,000 characters. No text was truncated."
        case .invalidAudio: "The speech output was empty, nonfinite, or outside the supported rate/duration limits."
        case .unsafeSupertonicText: "This passage could exceed Supertonic's token window. Shorten unusually long words or simplify expanded symbols. No text was truncated."
        }
    }
}

/// Cancellation closes admission until the actual worker returns, not until Stop is tapped.
public struct LocalSpeechAdmission: Sendable {
    public private(set) var requestID: UUID?
    public private(set) var isDraining = false
    public var isBusy: Bool { requestID != nil }
    public init() {}
    public mutating func begin() throws -> UUID {
        guard !isBusy else { throw LocalTTSError.busy }
        let id = UUID()
        requestID = id
        return id
    }
    public func accepts(_ id: UUID) -> Bool { requestID == id && !isDraining }
    public mutating func cancel() { if isBusy { isDraining = true } }
    public mutating func finish(_ id: UUID) {
        guard requestID == id else { return }
        requestID = nil
        isDraining = false
    }
}

public struct TTSComparisonPhrase: Codable, Identifiable, Sendable {
    public let id: String
    public let category: String
    public let text: String
    public static func corpusData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "tts-corpus", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
    public static func corpus() throws -> [Self] { try JSONDecoder().decode([Self].self, from: corpusData()) }
}

public enum TTSStatistics {
    /// Nearest-rank percentile. Callers must report failure/cancellation counts separately.
    public static func percentile(_ values: [Double], fraction: Double) -> Double? {
        guard !values.isEmpty, values.allSatisfy({ $0.isFinite && $0 >= 0 }),
              fraction.isFinite, (0...1).contains(fraction) else { return nil }
        let sorted = values.sorted()
        return sorted[max(0, Int(ceil(fraction * Double(sorted.count))) - 1)]
    }
    public static func aggregateRTF(synthesis: [Double], audio: [Double]) -> Double? {
        guard synthesis.count == audio.count, !audio.isEmpty,
              synthesis.allSatisfy({ $0.isFinite && $0 >= 0 }),
              audio.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return synthesis.reduce(0, +) / audio.reduce(0, +)
    }
}
