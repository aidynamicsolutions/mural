import Foundation
import Testing
@testable import MuralCore

struct ChineseScriptPresentationTests {
    private func spoken(_ text: String) -> Fragment {
        var f = Fragment(speaker: .user, text: text, startMS: 0, endMS: 1, turnID: UUID())
        f.rawASRText = "  " + text + "\n"
        return f
    }

    @Test func separatesCanonicalRawAndDisplayAcrossPersistence() throws {
        var f = spoken("後天 book a flight，謝謝！")
        let original = f
        f.scriptPresentation = try ChineseScriptPresentation.converting(f.text) {
            $0.replacingOccurrences(of: "後", with: "后").replacingOccurrences(of: "謝", with: "谢")
        }
        #expect(f.text == original.text)
        #expect(Array(f.rawASRText!.utf8) == Array(original.rawASRText!.utf8))
        #expect(f.displayText == "后天 book a flight，谢谢！")
        let decoded = try JSONDecoder().decode(Fragment.self, from: JSONEncoder().encode(f))
        #expect(decoded == f)
        #expect(decoded.displayText == f.displayText)
    }

    @Test func nonHanBytesNeverReachConverter() throws {
        let input = "後  iPhone 17 / GPT-5.1, A+B  12:30\tCafe\u{301} 🙂\n謝\0END"
        var calls = [String]()
        let p = try ChineseScriptPresentation.converting(input) { run in
            calls.append(run)
            return run == "後" ? "后" : "谢"
        }
        #expect(calls == ["後", "謝"])
        #expect(Array(p.text.utf8) == Array("后  iPhone 17 / GPT-5.1, A+B  12:30\tCafe\u{301} 🙂\n谢\0END".utf8))
        #expect(p.isValid(for: input))
    }

    @Test func variationSequencesArePreservedRatherThanBroken() throws {
        let input = "後\u{E0100} A"
        var called = false
        let p = try ChineseScriptPresentation.converting(input) { _ in called = true; return "后" }
        #expect(!called)
        #expect(Array(p.text.utf8) == Array(input.utf8))
    }

    @Test func identityConversionAndLimits() throws {
        #expect(try ChineseScriptPresentation.converting("") { $0 }.text.isEmpty)
        #expect(try ChineseScriptPresentation.converting("English 123!") { _ in Issue.record("Unexpected conversion"); return "" }.text == "English 123!")
        #expect(throws: ChineseScriptPresentation.Failure.self) {
            try ChineseScriptPresentation.converting(String(repeating: "a", count: ChineseScriptPresentation.maximumUTF8Bytes + 1)) { $0 }
        }
        #expect(throws: ChineseScriptPresentation.Failure.self) { try ChineseScriptPresentation.converting("後") { _ in "" } }
        #expect(throws: ChineseScriptPresentation.Failure.self) { try ChineseScriptPresentation.converting("後") { _ in "A" } }
    }

    @Test func scopeAndStaleProjectionFailClosed() throws {
        var f = spoken("後天")
        f.scriptPresentation = try ChineseScriptPresentation.converting(f.text) { _ in "后天" }
        #expect(f.hasScriptPresentation)
        f.typed = true; #expect(f.displayText == "後天")
        f.typed = false; f.speaker = .assistant; #expect(f.displayText == "後天")
        f.speaker = .user; f.rawASRText = nil; #expect(f.displayText == "後天")
        f.rawASRText = "後天"; f.text = "明天"; #expect(f.displayText == "明天")
    }

    @Test func legacyFragmentAndExplicitCorrection() throws {
        let f = spoken("後天")
        let data = try JSONEncoder().encode(f)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["scriptPresentation"] == nil)
        #expect(try JSONDecoder().decode(Fragment.self, from: data).displayText == "後天")
        var s = SessionRecord(languageID: "en")
        var marked = f
        marked.scriptPresentation = try ChineseScriptPresentation.converting(f.text) { _ in "后天" }
        s.append(marked)
        s.correctFragment(id: f.id, text: "明天")
        #expect(s.fragments[0].scriptPresentation == nil)
        #expect(s.fragments[0].rawASRText == f.rawASRText)
    }

    @Test func pairAndAssetIdentityAreSeparate() throws {
        #expect(LocalSpeechPair.mainlandMandarinEnglish.recognitionAssetPair == .taiwanMandarinEnglish)
        #expect(LocalSpeechPair.mainlandMandarinEnglish.recognizerID == "breeze-asr25-pal8-v1")
        #expect(LocalSpeechPair.mainlandMandarinEnglish.supportLocale == "zh-Hans-CN")
        #expect(LocalSpeechPair.taiwanMandarinEnglish.supportLocale == "zh-Hant-TW")
        #expect(LocalSpeechPair.vietnameseEnglish.recognitionAssetPair == .vietnameseEnglish)
        #expect(LocalSpeechPair.mainlandMandarinEnglish.preparationContract.contains("tw2s"))
        // The old package stays trusted for preservation, but new CN setup cannot select it.
        #expect(throws: SpeechPackageError.self) { try SpeechPackageCatalog.entry(for: LocalSpeechPair.mainlandMandarinEnglish.recognitionAssetPair) }
    }

    @Test func actualPinnedOpenCCGoldens() async throws {
        // MUST run against the real dependency; synthetic maps do not qualify this test.
        let examples = [
            ("我想 book a flight，下週去上海。", "我想 book a flight，下周去上海。"),
            ("這個軟體支援 API 和 iPhone 17。", "这个软体支援 API 和 iPhone 17。"),
            ("滑鼠和記憶體", "滑鼠和记忆体"),
            ("後天去臺北，頭髮乾了。", "后天去台北，头发干了。"),
            ("已经是简体，please keep English.", "已经是简体，please keep English."),
            ("怎么说？", "怎么说？"),
            ("怎麼，怎么，幺妹，么么，後天。", "怎么，怎么，幺妹，么么，后天。"),
            ("怎么 API Kevin 17\t🙂\n後天么么", "怎么 API Kevin 17\t🙂\n后天么么"),
            ("\tYes, no. 12:30 / £20 🙂\n", "\tYes, no. 12:30 / £20 🙂\n"),
            ("後\u{E0100} A", "後\u{E0100} A"),
            ("後  iPhone 17 / GPT-5.1, A+B  12:30\tCafe\u{301} 🙂\n謝\0END",
             "后  iPhone 17 / GPT-5.1, A+B  12:30\tCafe\u{301} 🙂\n谢\0END")
        ]
        try await ChineseScriptRenderer.shared.prepare(for: .mainlandMandarinEnglish)
        for (raw, expected) in examples {
            let result = try await ChineseScriptRenderer.shared.presentation(for: raw, pair: .mainlandMandarinEnglish)
            let p = try #require(result)
            #expect(Array(p.text.utf8) == Array(expected.utf8))
            #expect(Array(p.sourceText.utf8) == Array(raw.utf8))
        }
        #expect(try await ChineseScriptRenderer.shared.presentation(for: "後天", pair: .taiwanMandarinEnglish) == nil)
    }
}
