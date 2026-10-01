import Foundation
import OpenCC

/// Serializes the pinned native wrapper and its dictionary-loader cache. A SINGLE
/// converter is retained for the process, never instantiated for each turn/view.
/// No network, model, GPU/ANE work, or language guessing occurs in this layer.
public actor ChineseScriptRenderer {
    public static let shared = ChineseScriptRenderer()
    private var converter: ChineseConverter?
    private init() {}

    public func prepare(for pair: LocalSpeechPair) throws {
        try Task.checkCancellation()
        guard pair == .mainlandMandarinEnglish, converter == nil else { return }
        // Taiwan glyph variants + Traditional->Simplified. Deliberately NO .twIdiom:
        // e.g. 軟體 -> 软体, NOT 软件; 滑鼠 stays 滑鼠, not 鼠标.
        _ = try ChineseScriptNotices.read() // Required bundled distribution notice.
        converter = try ChineseConverter(options: [.simplify, .twStandard])
        try Task.checkCancellation()
    }

    public func presentation(for source: String, pair: LocalSpeechPair) throws -> ChineseScriptPresentation? {
        try Task.checkCancellation()
        guard pair == .mainlandMandarinEnglish else { return nil }
        try prepare(for: pair)
        guard let converter else { throw ChineseScriptPresentation.Failure.invalidConversion }
        let value = try ChineseScriptPresentation.converting(source) { run in
            try Task.checkCancellation()
            // Pinned TWVariantsRev maps literal 么 to 幺, although 么 is also an
            // ordinary Simplified character (怎么). Preserve that ambiguous input
            // byte-for-byte. Traditional 麼 still goes through OpenCC and becomes
            // 么; legitimate 幺 is never changed into 么. No wording repair occurs.
            guard run.contains("么") else { return converter.convert(run) }
            return run.split(separator: "么", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? "" : converter.convert(String($0)) }
                .joined(separator: "么")
        }
        try Task.checkCancellation()
        return value
    }
}
