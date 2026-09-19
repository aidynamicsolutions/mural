import XCTest
@testable import MuralCore

final class SpeechPresencePolicyTests: XCTestCase {
    private func evidence(_ probabilities: [Float], tail: Int = SpeechPresencePolicy.chunkSize) -> SpeechPresencePolicy.Evidence {
        var result = SpeechPresencePolicy.Evidence(sampleCount: max(0, probabilities.count - 1) * SpeechPresencePolicy.chunkSize + tail)
        for (index, probability) in probabilities.enumerated() {
            result.append(probability: probability, sampleCount: index == probabilities.count - 1 ? tail : SpeechPresencePolicy.chunkSize)
        }
        return result
    }

    func testControlIsDefaultAndExplicitModesAreStrict() throws {
        XCTAssertEqual(try SpeechPresencePolicy.Mode(arguments: []), .off)
        for mode in ["off", "observe", "gate"] {
            XCTAssertEqual(try SpeechPresencePolicy.Mode(arguments: ["Mural", "--asr-vad=\(mode)"]).rawValue, mode)
        }
        for flags in [["--asr-vad"], ["--asr-vad=unknown"], ["--asr-vad=gate", "--asr-vad=observe"]] {
            XCTAssertThrowsError(try SpeechPresencePolicy.Mode(arguments: flags))
        }
    }

    func testAllLowWindowsRejectOnlyInExperimentalGate() {
        let result = evidence([0.01, 0.02, 0.03, 0.01], tail: 3712) // 1 s at 16 kHz.
        XCTAssertTrue(result.complete)
        XCTAssertTrue(result.wouldReject)
        XCTAssertFalse(result.rejects(in: .off))
        XCTAssertFalse(result.rejects(in: .observe))
        XCTAssertTrue(result.rejects(in: .gate))
        XCTAssertNil(result.firstActiveSample)
    }

    func testAnySingleActiveWindowPreservesShortBurstsAtEveryPosition() {
        // Synthetic probabilities test policy semantics, NOT recognition of quiet Yes/No.
        for position in 0..<12 {
            var probabilities = Array(repeating: Float(0.001), count: 12)
            probabilities[position] = SpeechPresencePolicy.threshold
            let result = evidence(probabilities, tail: 2944) // 3 s.
            XCTAssertFalse(result.wouldReject)
            XCTAssertEqual(result.activeWindows, 1)
            XCTAssertEqual(result.firstActiveSample, position * 4096)
        }
    }

    func testOneSampleActiveTailIsNotDroppedOrCountedAs256Milliseconds() {
        let result = evidence([0, 0.8], tail: 1)
        XCTAssertFalse(result.wouldReject)
        XCTAssertEqual(result.activeWindowSamples, 1)
        XCTAssertEqual(result.firstActiveSample, 4096)
        XCTAssertEqual(result.lastActiveSampleExclusive, 4097)
    }

    func testInitialAndFinalSilenceDoNotUndoSpeechEvidence() {
        let result = evidence([0, 0.6, 0, 0, 0.8, 0])
        XCTAssertFalse(result.wouldReject)
        XCTAssertEqual(result.activeWindows, 2)
        XCTAssertEqual(result.activeWindowSamples, 8192)
        XCTAssertEqual(result.firstActiveSample, 4096)
        XCTAssertEqual(result.lastActiveSampleExclusive, 20480)
        XCTAssertEqual(result.meanProbability, 1.4 / 6, accuracy: 0.000001)
    }

    func testNoDurationOrVolumeMinimum() {
        let result = evidence([0.31], tail: 320) // A 20 ms capture is not rejected by length.
        XCTAssertFalse(result.wouldReject)
        XCTAssertEqual(result.activeWindowSamples, 320)
    }

    func testThresholdBoundary() {
        XCTAssertTrue(evidence([SpeechPresencePolicy.threshold.nextDown]).wouldReject)
        XCTAssertFalse(evidence([SpeechPresencePolicy.threshold]).wouldReject)
    }

    func testMissingEvidenceFailsOpen() {
        var result = SpeechPresencePolicy.Evidence(sampleCount: 8192)
        XCTAssertFalse(result.wouldReject)
        result.append(probability: 0, sampleCount: 4096)
        XCTAssertFalse(result.wouldReject)
        XCTAssertFalse(result.complete)
    }

    func testInvalidProbabilityFailsOpenEvenAfterLowWindows() {
        for invalid in [Float.nan, .infinity, -.infinity, -0.01, 1.01] {
            let result = evidence([0, invalid])
            XCTAssertFalse(result.valid)
            XCTAssertFalse(result.wouldReject)
        }
    }

    func testMissingExtraOrWrongSizeWindowsCannotReject() {
        for count in [0, -1, 1, 4095, 4097] {
            var result = SpeechPresencePolicy.Evidence(sampleCount: 4096)
            result.append(probability: 0, sampleCount: count)
            XCTAssertFalse(result.wouldReject)
        }
        var extra = evidence([0])
        extra.append(probability: 0, sampleCount: 4096)
        XCTAssertFalse(extra.wouldReject)
    }

    func testInvalidCaptureCountsFailOpenAndMaximumTurnIsBounded() {
        for count in [-1, 0, 480_001, Int.max] {
            let result = SpeechPresencePolicy.Evidence(sampleCount: count)
            XCTAssertFalse(result.wouldReject)
            XCTAssertFalse(result.valid)
        }
        let maximum = evidence(Array(repeating: 0, count: 118), tail: 768)
        XCTAssertEqual(maximum.sampleCount, 480_000)
        XCTAssertTrue(maximum.wouldReject)
    }

    func testEvidenceDoesNotLeakBetweenTurns() {
        let first = evidence([1])
        let second = evidence([0])
        XCTAssertFalse(first.wouldReject)
        XCTAssertTrue(second.wouldReject)
        XCTAssertEqual(second.activeWindows, 0)
    }
}
