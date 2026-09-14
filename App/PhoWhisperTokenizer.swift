import Foundation
import WhisperKit

/// Fixed large-v2 control-token contract; lexical BPE stays PhoWhisper's own.
/// Its old tokenizer omits timestamps and calls no-speech "nocaptions". The
/// stock WhisperKit wrapper otherwise treats unknown-token 50257 as their ID.
struct PhoWhisperTokenizer: WhisperTokenizer {
    let base: TokenizerWrapper
    let specialTokens = SpecialTokens(
        endToken: 50257, englishToken: 50259, noSpeechToken: 50362,
        noTimestampsToken: 50363, specialTokenBegin: 50257,
        startOfPreviousToken: 50361, startOfTranscriptToken: 50258,
        timeTokenBegin: 50364, transcribeToken: 50359, translateToken: 50358,
        whitespaceToken: 220)
    var allLanguageTokens: Set<Int> {
        Set(Constants.languages.values.compactMap { base.convertTokenToId("<|\($0)|>") }
            .filter { (50259...50357).contains($0) })
    }

    static func load(from folder: URL) async throws -> PhoWhisperTokenizer {
        // Local-only factory: a parse failure must not fall back to a Hub tokenizer.
        let base = try await AutoTokenizerWrapper.from(modelFolder: folder)
        guard base.convertTokenToId("<|notimestamps|>") == 50363,
              base.convertTokenToId("<|nocaptions|>") == 50362,
              base.convertTokenToId("<|vi|>") == 50278,
              base.convertTokenToId("Ġ") == 220 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return PhoWhisperTokenizer(base: base)
    }

    func encode(text: String) -> [Int] { base.encode(text: text) }
    func decode(tokens: [Int]) -> String { base.decode(tokens: tokens) }
    func convertTokenToId(_ token: String) -> Int? { base.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { base.convertIdToToken(id) }

    // Same Unicode-safe, space-delimited grouping as WhisperKit's VI/EN path.
    // Recognition uses no word timestamps; this never rewrites transcript text.
    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        let full = decode(tokens: tokenIds)
        var words: [String] = [], groups: [[Int]] = [], pending: [Int] = []
        var offset = 0
        for token in tokenIds {
            pending.append(token)
            let word = decode(tokens: pending)
            if let range = word.range(of: "\u{fffd}") {
                let start = word.distance(from: word.startIndex, to: range.lowerBound) + offset
                if Array(full).dropFirst(start).first != "\u{fffd}" { continue }
            }
            let punctuation = word.trimmingCharacters(in: .whitespaces).unicodeScalars
            if words.isEmpty || pending[0] >= specialTokens.specialTokenBegin || word.hasPrefix(" ") ||
                (!punctuation.isEmpty && punctuation.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) })) {
                words.append(word); groups.append(pending)
            } else {
                words[words.count - 1] += word; groups[groups.count - 1] += pending
            }
            offset += word.count
            pending.removeAll(keepingCapacity: true)
        }
        if !pending.isEmpty { words.append(decode(tokens: pending)); groups.append(pending) }
        return (words, groups)
    }
}
