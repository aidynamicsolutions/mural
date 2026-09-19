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

    func testGateIsDefaultAndExplicitModesAreStrict() throws {
        XCTAssertEqual(try SpeechPresencePolicy.Mode(arguments: []), .gate)
        for mode in ["off", "observe", "gate"] {
            XCTAssertEqual(try SpeechPresencePolicy.Mode(arguments: ["Mural", "--asr-vad=\(mode)"]).rawValue, mode)
        }
        for flags in [["--asr-vad"], ["--asr-vad=unknown"], ["--asr-vad=gate", "--asr-vad=observe"]] {
            XCTAssertThrowsError(try SpeechPresencePolicy.Mode(arguments: flags))
        }
    }

    func testAllLowWindowsRejectOnlyInGateMode() {
        let result = evidence([0.01, 0.02, 0.03, 0.01], tail: 3712) // 1 s at 16 kHz.
        XCTAssertTrue(result.complete)
        XCTAssertTrue(result.wouldReject)
        XCTAssertFalse(result.rejects(in: .off))
        XCTAssertFalse(result.rejects(in: .observe))
        XCTAssertTrue(result.rejects(in: .gate))
        XCTAssertNil(result.firstActiveSample)
    }

    func testOneBriefSpikeRejectsAtEveryPosition() {
        for position in 0..<12 {
            var probabilities = Array(repeating: Float(0.001), count: 12)
            probabilities[position] = 1
            let result = evidence(probabilities, tail: 2944) // 3 s.
            XCTAssertTrue(result.wouldReject)
            XCTAssertEqual(result.activeWindows, 1)
            XCTAssertEqual(result.firstActiveSample, position * 4096)
        }
    }

    func testOneSampleActiveTailIsTrackedButCannotQualifySpeech() {
        let result = evidence([0, 0.8], tail: 1)
        XCTAssertTrue(result.wouldReject)
        XCTAssertEqual(result.activeWindowSamples, 1)
        XCTAssertEqual(result.firstActiveSample, 4096)
        XCTAssertEqual(result.lastActiveSampleExclusive, 4097)
    }

    func testInitialAndFinalSilenceDoNotUndoThreeStrongWindows() {
        let result = evidence([0, 0.9, 0.9, 0, 0.9, 0])
        XCTAssertFalse(result.wouldReject)
        XCTAssertEqual(result.activeWindows, 3)
        XCTAssertEqual(result.activeWindowSamples, 12_288)
        XCTAssertEqual(result.firstActiveSample, 4096)
        XCTAssertEqual(result.lastActiveSampleExclusive, 20_480)
        XCTAssertEqual(result.speechScore, 0.9, accuracy: 0.000001)
    }

    func testFewerThanThreeWindowsCannotQualifySpeech() {
        XCTAssertTrue(evidence([1], tail: 320).wouldReject)
        XCTAssertTrue(evidence([1, 1], tail: 320).wouldReject)
        XCTAssertFalse(evidence([1, 1, 1], tail: 320).wouldReject)
    }

    func testSpeechScoreBoundary() {
        XCTAssertTrue(evidence(Array(repeating: SpeechPresencePolicy.speechScoreThreshold.nextDown, count: 3)).wouldReject)
        XCTAssertFalse(evidence(Array(repeating: SpeechPresencePolicy.speechScoreThreshold, count: 3)).wouldReject)
    }

    func testRecordedFanAndBreathingRejectWhileQuietYesAndNoPass() {
        let fan: [Float] = [0.058594, 0.042480, 0.156738, 0.160645, 0.853516, 0.430664, 0.229492, 0.194824, 0.139160, 0.033691, 0.014160, 0.012207, 0.009766, 0.007324, 0.003906, 0.004395, 0.002441]
        let breathing: [Float] = [0.053223, 0.045898, 0.045410, 0.039062, 0.990723, 0.993164, 0.424805, 0.113281, 0.065918, 0.043457, 0.020996, 0.036621, 0.023438, 0.013184, 0.013672, 0.016113, 0.006348, 0.004395]
        let roomNoise: [Float] = [0.086426, 0.044922, 0.037598, 0.041992, 0.028809, 0.026367, 0.041992, 0.036133, 0.088379, 0.085449, 0.040039, 0.013672, 0.039062, 0.209961, 0.032715, 0.077637, 0.582031, 0.241211, 0.036621]
        let quietYes: [Float] = [0.064941, 0.032715, 1, 1, 0.925781, 0.823242, 0.225586]
        let quietNo: [Float] = [0.063965, 0.031738, 0.029785, 0.029785, 0.999512, 1, 0.769043, 0.237305, 0.229492]

        XCTAssertTrue(evidence(fan, tail: 1664).wouldReject)
        XCTAssertTrue(evidence(breathing, tail: 3968).wouldReject)
        XCTAssertTrue(evidence(roomNoise, tail: 1472).wouldReject)
        XCTAssertFalse(evidence(quietYes, tail: 2624).wouldReject)
        XCTAssertFalse(evidence(quietNo, tail: 2432).wouldReject)
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
        let first = evidence([1, 1, 1])
        let second = evidence([0, 0, 0])
        XCTAssertFalse(first.wouldReject)
        XCTAssertTrue(second.wouldReject)
        XCTAssertEqual(second.activeWindows, 0)
        XCTAssertEqual(second.speechScore, 0)
    }
}
