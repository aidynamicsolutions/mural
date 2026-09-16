import XCTest
@testable import MuralCore

final class MeaningControllerTests: XCTestCase {
    @MainActor
    func testFixedEnglishGreetingUsesBuiltInVietnameseMeaningWithoutTranslator() throws {
        var session = SessionRecord(languageID: "en")
        session.append(Fragment(speaker: .assistant, text: "Hi! What did you do today?", startMS: 0, endMS: 100))
        let passage = try XCTUnwrap(session.passages.last)
        var translatorCalls = 0
        let controller = MeaningController(delay: .zero) { _ in
            translatorCalls += 1
            return MeaningResult(text: "unexpected")
        }

        controller.update(MeaningRequest(sessionID: session.id, passage: passage,
                                         learningLanguageID: "en", meaningLanguage: "Vietnamese"))

        XCTAssertEqual(controller.text, "Chào bạn! Hôm nay bạn đã làm gì?")
        XCTAssertFalse(controller.isLoading)
        XCTAssertNil(controller.error)
        XCTAssertEqual(translatorCalls, 0)
    }
}
