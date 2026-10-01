import Foundation

/// A versioned DISPLAY snapshot. Never recognition, a correction, or tutor input.
/// Keep the source so a stale projection cannot survive an explicit transcript edit.
public struct ChineseScriptPresentation: Codable, Equatable, Sendable {
    public static let policyID = "tw2s-han-1d8105a0-v1"
    public static let maximumUTF8Bytes = 200_000
    public let sourceText: String
    public let text: String
    public let policy: String

    private enum CodingKeys: String, CodingKey {
        case sourceText, text
        case policy = "policyID"
    }

    public enum Failure: Error, LocalizedError {
        case invalidConversion
        public var errorDescription: String? {
            "Simplified display could not be prepared. The original recognition is unchanged."
        }
    }

    private init(sourceText: String, text: String) {
        self.sourceText = sourceText; self.text = text; policy = Self.policyID
    }

    /// Only ordinary, single-scalar ideographs enter OpenCC. Every other grapheme is
    /// copied byte-for-byte, including English, whitespace, NUL, emoji and variation
    /// sequences. Unusual Han+variation sequences remain unchanged, not damaged.
    /// `transform` is also the isolated failure-test seam; production uses only OpenCC.
    static func converting(_ source: String, transform: (String) throws -> String) throws -> Self {
        guard bounded(source) else { throw Failure.invalidConversion }
        var result = ""
        for segment in segments(source) {
            let value = segment.han ? try transform(segment.text) : segment.text
            if segment.han {
                guard !value.isEmpty, bounded(value), value.allSatisfy(isPlainHan) else {
                    throw Failure.invalidConversion
                }
            }
            guard value.utf8.count <= maximumUTF8Bytes - result.utf8.count else {
                throw Failure.invalidConversion
            }
            result += value
        }
        let snapshot = Self(sourceText: source, text: result)
        guard snapshot.isValid(for: source) else { throw Failure.invalidConversion }
        return snapshot
    }

    /// Structural/import validation, not independent proof of dictionary accuracy.
    /// English and punctuation must match at the SAME run boundaries, not just as a
    /// bag of characters. Never recompute history using the current language setting.
    public func isValid(for source: String) -> Bool {
        guard policy == Self.policyID, Self.bounded(sourceText), Self.bounded(text),
              sourceText.utf8.elementsEqual(source.utf8) else { return false }
        let old = Self.segments(sourceText), new = Self.segments(text)
        guard old.count == new.count else { return false }
        return zip(old, new).allSatisfy { lhs, rhs in
            lhs.han == rhs.han && (lhs.han || lhs.text.utf8.elementsEqual(rhs.text.utf8))
        }
    }

    private static func bounded(_ text: String) -> Bool {
        text.utf8.count <= maximumUTF8Bytes && text.count <= 50_000
    }

    private static func isPlainHan(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1 && character.unicodeScalars.first!.properties.isIdeographic
    }

    private static func segments(_ text: String) -> [(han: Bool, text: String)] {
        var result: [(han: Bool, text: String)] = []
        for character in text {
            let han = isPlainHan(character)
            if !result.isEmpty, result[result.count - 1].han == han {
                result[result.count - 1].text.append(character)
            } else {
                result.append((han, String(character)))
            }
        }
        return result
    }
}

extension Fragment {
    public var hasScriptPresentation: Bool {
        speaker == .user && !typed && turnID != nil && rawASRText != nil &&
            scriptPresentation?.isValid(for: text) == true
    }
    public var displayText: String { hasScriptPresentation ? scriptPresentation!.text : text }
}

extension Passage {
    /// UI only. `text` remains canonical for tutoring, revision keys and learning.
    public var displayText: String { fragments.map(\.displayText).joined() }
    public var hasScriptPresentation: Bool { fragments.contains(where: \.hasScriptPresentation) }
}
