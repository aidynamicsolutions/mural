import Foundation
import Testing
@testable import MuralCore

/// Runs in the complete repository suite; no ASR or tutor is mocked as qualified.
struct LocalSpeechPairPersistenceTests {
    @Test func legacyPreferencesDecodeWithoutNewPair() throws {
        var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Preferences())) as? [String: Any])
        old.removeValue(forKey: "localSpeechPair")
        old["meaningLanguage"] = "Vietnamese"
        let preferences = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(preferences.localSpeechPair == nil)
        #expect(preferences.meaningLanguage == "Vietnamese")
    }
    @Test func legacySessionsRemainVietnameseByDefault() throws {
        var session = SessionRecord(languageID: "en")
        session.append(Fragment(speaker: .user, text: "Hello", startMS: 0, endMS: 1, turnID: UUID()))
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: data)
        #expect(decoded.localSpeechPair == nil)
        #expect((decoded.localSpeechPair ?? .vietnameseEnglish) == .vietnameseEnglish)
        #expect(decoded.fragments[0].rawASRText == nil)
    }
    @Test func rawRecognitionAndSessionPairSurviveArchiveAndDisplayEdit() throws {
        var archive = Archive()
        archive.preferences.learningLanguageID = "en"
        archive.preferences.meaningLanguage = "Traditional Chinese"
        archive.preferences.localSpeechPair = .taiwanMandarinEnglish
        var session = SessionRecord(languageID: "en")
        session.localSpeechPair = .taiwanMandarinEnglish
        let raw = "  今天 I bought two apples.\n"
        var fragment = Fragment(speaker: .user, text: raw.trimmingCharacters(in: .whitespacesAndNewlines), startMS: 0, endMS: 1, turnID: UUID())
        fragment.rawASRText = raw
        session.append(fragment)
        session.correctFragment(id: fragment.id, text: "Today I bought two apples.")
        archive.sessions = [session]
        let decoded = try Archive.decode(archive.encoded())
        #expect(decoded.sessions[0].localSpeechPair == .taiwanMandarinEnglish)
        #expect(decoded.sessions[0].fragments[0].rawASRText == raw)
        #expect(decoded.sessions[0].fragments[0].text == "Today I bought two apples.")
        #expect(decoded.preferences.localSpeechPair == .taiwanMandarinEnglish)
    }
    @Test func unknownPairDoesNotSilentlySelectVietnamese() throws {
        var value = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Preferences())) as? [String: Any])
        value["localSpeechPair"] = "unknown-new-mode"
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: value)) }
    }
    @Test @MainActor func greetingMeaningIsTraditionalChineseWithoutModelInference() throws {
        let passage = try #require(Transcript.passages([Fragment(speaker: .assistant, text: "Hi! What did you do today?", startMS: 0, endMS: 1, turnID: UUID())]).first)
        let request = MeaningRequest(sessionID: UUID(), passage: passage, learningLanguageID: "en", meaningLanguage: "Traditional Chinese")
        let controller = MeaningController { _ in
            Issue.record("Built-in greeting must not invoke a model")
            return MeaningResult(text: "unexpected")
        }
        controller.update(request)
        #expect(controller.text == "你好！你今天做了什麼？")
        #expect(!controller.isLoading)
    }
}
