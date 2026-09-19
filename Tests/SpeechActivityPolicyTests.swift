import XCTest
@testable import MuralCore

final class SpeechActivityPolicyTests: XCTestCase {
    private typealias Policy = SpeechActivityPolicy

    func testDefaultIsOffAndModesAreExplicit() throws {
        XCTAssertEqual(try Policy.Mode.resolve(["Mural"]), .off)
        for mode in [Policy.Mode.off, .observe, .gate] {
            XCTAssertEqual(try Policy.Mode.resolve(["Mural", "--speech-vad=\(mode.rawValue)"]), mode)
        }
    }

    func testInvalidOrDuplicateModeCannotSilentlyBecomeAGate() {
        for flags in [["--speech-vad"], ["--speech-vad=unknown"], ["--speech-vadgate"],
                      ["--speech-vad=gate", "--speech-vad=observe"],
                      ["--speech-vad=gate", "--speech-vad=gate"]] {
            XCTAssertThrowsError(try Policy.Mode.resolve(flags))
        }
    }

    func testObserveAndOffNeverReject() {
        for decision in [Policy.Decision.speech, .noSpeech, .inconclusive] {
            XCTAssertFalse(Policy.shouldReject(decision, mode: .off))
            XCTAssertFalse(Policy.shouldReject(decision, mode: .observe))
        }
        XCTAssertTrue(Policy.shouldReject(.noSpeech, mode: .gate))
        XCTAssertFalse(Policy.shouldReject(.speech, mode: .gate))
        XCTAssertFalse(Policy.shouldReject(.inconclusive, mode: .gate))
    }

    func testOneAndThreeSecondAllNegativeEvidence() {
        for count in [16_000, 48_000] {
            let probabilities = Array(repeating: Float(0.01), count: (count + 4095) / 4096)
            XCTAssertEqual(Policy.assess(sampleCount: count, probabilities: probabilities).decision, .noSpeech)
        }
    }

    func testSingleBurstSurvivesInitialAndFinalSilence() {
        for index in 0..<12 {
            var probabilities = Array(repeating: Float(0.01), count: 12)
            probabilities[index] = Policy.threshold
            let evidence = Policy.assess(sampleCount: 48_000, probabilities: probabilities)
            XCTAssertEqual(evidence.decision, .speech)
            XCTAssertEqual(evidence.activeWindowCount, 1)
            XCTAssertEqual(evidence.firstActiveSample, index * 4096)
            XCTAssertEqual(evidence.lastActiveSample, min((index + 1) * 4096, 48_000))
        }
    }

    func testShortNegativeRecordingIsInconclusiveNotSilence() {
        for count in [1, 800, 1600, 4095] {
            XCTAssertEqual(Policy.assess(sampleCount: count, probabilities: [0]).decision, .inconclusive)
            XCTAssertEqual(Policy.assess(sampleCount: count, probabilities: [0.31]).decision, .speech)
        }
    }

    func testThresholdAndWindowBoundaries() {
        XCTAssertEqual(Policy.assess(sampleCount: 4096, probabilities: [0.299]).decision, .noSpeech)
        XCTAssertEqual(Policy.assess(sampleCount: 4096, probabilities: [Policy.threshold]).decision, .speech)
        let evidence = Policy.assess(sampleCount: 4097, probabilities: [0, 0.31])
        XCTAssertEqual(evidence.activeSampleCount, 1)
        XCTAssertEqual(evidence.firstActiveSample, 4096)
        XCTAssertEqual(evidence.lastActiveSample, 4097)
        XCTAssertEqual(evidence.decision, .speech)
    }

    func testIncompleteInvalidOrExtraProbabilitiesFailOpen() {
        for probabilities: [Float] in [[], [0], [0, 0, 0], [.nan, 0], [.infinity, 0],
                                       [-0.01, 0], [1.01, 0], [0.9, .nan]] {
            XCTAssertEqual(Policy.assess(sampleCount: 8192, probabilities: probabilities).decision, .inconclusive)
        }
    }

    func testEmptyAndInvalidSampleCounts() {
        XCTAssertEqual(Policy.assess(sampleCount: 0, probabilities: []).decision, .noSpeech)
        for count in [-1, 480_001, Int.max] {
            XCTAssertEqual(Policy.assess(sampleCount: count, probabilities: []).decision, .inconclusive)
        }
    }

    func testDisjointActiveDurationDoesNotIncludeGapsOrPadding() {
        let evidence = Policy.assess(sampleCount: 9000, probabilities: [0.8, 0, 0.4])
        XCTAssertEqual(evidence.activeWindowCount, 2)
        XCTAssertEqual(evidence.activeSampleCount, 4904)
        XCTAssertEqual(evidence.firstActiveSample, 0)
        XCTAssertEqual(evidence.lastActiveSample, 9000)
    }

    func testMaximumLengthIsBoundedAndNoEvidenceLeaksBetweenCalls() {
        XCTAssertEqual(Policy.assess(sampleCount: 480_000,
                                    probabilities: Array(repeating: 0, count: 118)).decision, .noSpeech)
        XCTAssertEqual(Policy.assess(sampleCount: 4096, probabilities: [0.9]).decision, .speech)
        XCTAssertEqual(Policy.assess(sampleCount: 4096, probabilities: [0]).decision, .noSpeech)
    }
}
