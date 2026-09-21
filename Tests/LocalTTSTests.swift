import XCTest
@testable import MuralCore

final class LocalTTSTests: XCTestCase {
    func testValidationAdmissionCorpusAndStatistics() throws {
        for value in ["", " \n\t", String(repeating: "a", count: 1_001)] {
            XCTAssertThrowsError(try LocalTTSAudio.validatedText(value))
        }
        XCTAssertEqual(try LocalTTSAudio.validatedText(" “Really?” "), "“Really?”")
        XCTAssertEqual(try LocalTTSAudio.validatedText(String(repeating: "é", count: 1_000)).count, 1_000)
        for rate in [24_000.0, 44_100.0] {
            let audio = try LocalTTSAudio(samples: Array(repeating: 0.01, count: Int(rate)), sampleRate: rate)
            XCTAssertEqual(audio.duration, 1)
            XCTAssertFalse(audio.hasClipping)
        }
        XCTAssertThrowsError(try LocalTTSAudio(samples: [], sampleRate: 24_000))
        XCTAssertThrowsError(try LocalTTSAudio(samples: [.nan], sampleRate: 24_000))
        XCTAssertThrowsError(try LocalTTSAudio(samples: [.infinity], sampleRate: 24_000))
        XCTAssertThrowsError(try LocalTTSAudio(samples: [0], sampleRate: .nan))
        XCTAssertThrowsError(try LocalTTSAudio(samples: [0], sampleRate: 0))
        XCTAssertTrue(try LocalTTSAudio(samples: [1.2], sampleRate: 24_000).hasClipping)

        var admission = LocalSpeechAdmission()
        let first = try admission.begin()
        XCTAssertThrowsError(try admission.begin())
        admission.cancel()
        XCTAssertFalse(admission.accepts(first))
        XCTAssertTrue(admission.isDraining)
        XCTAssertThrowsError(try admission.begin()) // Stop cannot admit work while native work drains.
        admission.finish(UUID()) // Late callback from another request cannot release this owner.
        XCTAssertTrue(admission.isBusy)
        admission.finish(first)
        let second = try admission.begin()
        admission.finish(first)
        XCTAssertTrue(admission.accepts(second))
        admission.finish(second)
        XCTAssertFalse(admission.isBusy)

        let corpus = try TTSComparisonPhrase.corpus()
        XCTAssertEqual(corpus.count, 30)
        XCTAssertEqual(Set(corpus.map(\.id)).count, 30)
        XCTAssertEqual(corpus.first?.text, "Yes.")
        XCTAssertEqual(corpus[16].text, "The total is $12.50.")
        XCTAssertTrue(corpus.allSatisfy { (try? LocalTTSAudio.validatedText($0.text)) != nil })
        XCTAssertTrue(corpus.allSatisfy { (try? LocalTTSAudio.validatedSupertonicText($0.text)) != nil })
        XCTAssertEqual(try LocalTTSAudio.validatedSupertonicText(" “Really?” Café at 3:45 p.m. "), "“Really?” Café at 3:45 p.m.")
        XCTAssertNoThrow(try LocalTTSAudio.validatedSupertonicText(String(repeating: "a", count: 70)))
        XCTAssertThrowsError(try LocalTTSAudio.validatedSupertonicText(String(repeating: "a", count: 71)))
        XCTAssertThrowsError(try LocalTTSAudio.validatedSupertonicText(String(repeating: "a", count: 150)))
        XCTAssertThrowsError(try LocalTTSAudio.validatedSupertonicText(String(repeating: "@ ", count: 20)))
        XCTAssertThrowsError(try LocalTTSAudio.validatedSupertonicText(String(repeating: "é ", count: 60)))
        XCTAssertEqual(TTSStatistics.percentile([100, 2, 3, 4], fraction: 0.5), 3)
        XCTAssertEqual(TTSStatistics.percentile([100, 2, 3, 4], fraction: 0.95), 100)
        XCTAssertNil(TTSStatistics.percentile([], fraction: 0.95))
        XCTAssertEqual(TTSStatistics.aggregateRTF(synthesis: [1, 1], audio: [2, 8]), 0.2)
        XCTAssertNil(TTSStatistics.aggregateRTF(synthesis: [1], audio: [0]))
    }
}
