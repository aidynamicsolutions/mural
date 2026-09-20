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

    private func pcm(_ count: Int, offset: Int = 0) -> [Float] {
        (0..<count).map { Float($0 + offset) } // Unique exact values, including across turns.
    }

    private func assertSelection(_ analysis: SpeechPresencePolicy.Analysis, from samples: [Float],
                                 regions: [Range<Int>], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(analysis.regions, regions, file: file, line: line)
        XCTAssertEqual(analysis.samples, regions.flatMap { samples[$0] }, file: file, line: line)
        XCTAssertLessThanOrEqual(analysis.samples.count, samples.count, file: file, line: line)
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
        let samples = pcm(result.sampleCount)
        let analysis = result.analyze(samples, mode: .gate)
        XCTAssertTrue(analysis.rejected)
        XCTAssertFalse(analysis.failedOpen)
        assertSelection(analysis, from: samples, regions: [])
    }

    func testOneBriefSpikeRejectsAtEveryPosition() {
        for position in 0..<12 {
            var probabilities = Array(repeating: Float(0.001), count: 12)
            probabilities[position] = 1
            let result = evidence(probabilities, tail: 2944) // 3 s.
            XCTAssertTrue(result.wouldReject)
            XCTAssertEqual(result.activeWindows, 1)
            XCTAssertEqual(result.firstActiveSample, position * 4096)
            let analysis = result.analyze(pcm(result.sampleCount), mode: .gate)
            XCTAssertTrue(analysis.rejected)
            XCTAssertTrue(analysis.samples.isEmpty)
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

    func testShortCapturesNeedTwoFullVeryStrongWindows() {
        // Synthetic probabilities, not an acoustic minimum word duration.
        for count in [1, 320, 4096, 4097, 8191] {
            var result = SpeechPresencePolicy.Evidence(sampleCount: count)
            for offset in stride(from: 0, to: count, by: SpeechPresencePolicy.chunkSize) {
                result.append(probability: 1, sampleCount: min(4096, count - offset))
            }
            XCTAssertTrue(result.complete)
            XCTAssertEqual(result.speechScore, 0)
            XCTAssertTrue(result.wouldReject)
        }
        let pair = evidence([1, 1])
        XCTAssertEqual(pair.sampleCount, 8192)
        XCTAssertEqual(pair.speechScore, 0) // Legacy three-window score is unchanged.
        XCTAssertTrue(pair.hasStrongSpeechPair)
        XCTAssertFalse(pair.wouldReject)
        let partialThird = evidence([1, 1, 1], tail: 1)
        XCTAssertEqual(partialThird.sampleCount, 8193) // Captured geometry, not a word-duration requirement.
        XCTAssertEqual(partialThird.activeWindowSamples, 8193) // No SDK padding counted.
        XCTAssertEqual(partialThird.speechScore, 1)
        XCTAssertFalse(partialThird.wouldReject)
    }

    func testVeryStrongFullPairSurvivesSurroundingQuiet() {
        // Synthetic evidence at the FireRed rejected capture lengths. NOT their lost traces.
        for count in [36_800, 44_800, 54_400] {
            let windows = (count + 4095) / 4096
            for onset in 0..<windows - 1 {
                var probabilities = Array(repeating: Float(0.01), count: windows)
                probabilities[onset] = 1
                probabilities[onset + 1] = 1
                let result = evidence(probabilities, tail: count - (windows - 1) * 4096)
                XCTAssertTrue(result.complete)
                XCTAssertEqual(result.activeWindows, 2)
                XCTAssertEqual(result.speechScore, 0.67, accuracy: 0.000001)
                // A pair touching the padded final window cannot use the rescue.
                XCTAssertEqual(result.rejects(in: .gate), onset == windows - 2)
                XCTAssertFalse(result.rejects(in: .observe))
            }
        }
    }

    func testHistoricalObserveSpeechBlockTurnUsesPairBelowAggregateScore() {
        // Real logged probabilities: September 19 observe, ECCF6D2B-34C6-4540-BF60-A2761D2370E5.
        // No retained PCM or independently checked words: this documents policy behavior only.
        let result = evidence([0.046387, 0.025391, 1, 1, 0.497070, 0.330078], tail: 3520)
        XCTAssertEqual(result.sampleCount, 24_000)
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.activeWindows, 4) // 0.30 is not the turn acceptance threshold.
        XCTAssertEqual(result.speechScore, 0.8323567, accuracy: 0.000001)
        XCTAssertTrue(result.hasStrongSpeechPair)
        XCTAssertFalse(result.rejects(in: .gate))
        XCTAssertFalse(result.rejects(in: .observe))
    }

    func testVADOnlyPhoneShortRepliesUsePairWithoutLoweringAggregateCutoff() {
        // September 20, human-labeled normal Yes/No; actual logged probabilities, not PCM replay.
        // 0B83DFCD-9CFA-4423-9DF8-9AF2485D6551 and D354FEA0-FDE0-4FFD-9110-164B314BF6E1.
        let yes = evidence([0.099609, 0.048828, 0.023926, 1, 1, 0.392578, 0.104492, 0.038574], tail: 1728)
        let no = evidence([0.085449, 0.039551, 0.032715, 0.051758, 1, 1, 0.500977, 0.145508, 0.143066], tail: 4032)
        XCTAssertEqual(yes.sampleCount, 30_400)
        XCTAssertEqual(no.sampleCount, 36_800)
        XCTAssertEqual(yes.speechScore, 0.797526, accuracy: 0.000001)
        XCTAssertEqual(no.speechScore, 0.833659, accuracy: 0.000001)
        for result in [yes, no] {
            XCTAssertTrue(result.complete)
            XCTAssertEqual(result.activeWindows, 3) // Active coverage is not three strong windows.
            XCTAssertTrue(result.hasStrongSpeechPair)
            XCTAssertFalse(result.rejects(in: .gate))
            XCTAssertFalse(result.rejects(in: .observe))
        }
        // Lowering only the top-three cutoff enough to rescue this Yes reopens known breathing.
        let recordedBreathingScore: Float = (0.993164 + 0.990723 + 0.424805) / 3
        XCTAssertGreaterThan(recordedBreathingScore, yes.speechScore)
        XCTAssertLessThan(recordedBreathingScore, SpeechPresencePolicy.speechScoreThreshold)
    }

    func testFollowupShortSpeechIsRescuedWithoutAcceptingThroatClear() {
        // Real held-out phone probabilities: normal No, quiet Yes, quiet No (September 20 follow-up).
        // IDs: 72A2B33E, DE7FD4E0, 42BA5229. No original PCM retained for these turns.
        let speech: [([Float], Int)] = [
            ([0.071289, 0.041992, 0.024414, 0.081055, 1, 1, 0.229980, 0.233887, 0.101074], 4032),
            ([0.072266, 0.046387, 0.024902, 0.023926, 1, 1, 0.253906, 0.144043, 0.077637, 0.038574, 0.023438], 2240),
            ([0.091309, 0.042969, 0.031250, 0.024414, 1, 1, 0.312500, 0.187988, 0.074707], 4032)
        ]
        for (probabilities, tail) in speech {
            let result = evidence(probabilities, tail: tail)
            XCTAssertTrue(result.complete)
            XCTAssertLessThan(result.speechScore, SpeechPresencePolicy.speechScoreThreshold)
            XCTAssertFalse(result.rejects(in: .gate))
        }
        // Real non-word control 559D9CD5: near-saturated spike is not a pair.
        let throat = evidence([0.105469, 0.083496, 0.045898, 0.996582, 0.859863, 0.065430,
                               0.023926, 0.030762, 0.017090, 0.013672, 0.009277], tail: 2240)
        XCTAssertTrue(throat.rejects(in: .gate))
    }

    func testShortSpeechPairRequiresAdjacencyFullWindowsAndStrictScore() {
        let threshold = SpeechPresencePolicy.shortSpeechThreshold
        XCTAssertFalse(evidence([threshold, threshold]).wouldReject)
        for probabilities: [Float] in [[threshold.nextDown, 1], [1, threshold.nextDown], [1, 0, 1]] {
            let result = evidence(probabilities)
            XCTAssertFalse(result.hasStrongSpeechPair)
            XCTAssertTrue(result.wouldReject)
        }
        for tail in [1, 320, 4095] {
            let result = evidence([1, 1], tail: tail)
            XCTAssertFalse(result.hasStrongSpeechPair)
            XCTAssertTrue(result.wouldReject)
        }
        var incomplete = SpeechPresencePolicy.Evidence(sampleCount: 12_288)
        incomplete.append(probability: 1, sampleCount: 4096)
        incomplete.append(probability: 1, sampleCount: 4096)
        XCTAssertTrue(incomplete.hasStrongSpeechPair)
        XCTAssertTrue(incomplete.analyze(pcm(12_288), mode: .gate).failedOpen)
        incomplete.append(probability: .nan, sampleCount: 4096)
        XCTAssertTrue(incomplete.analyze(pcm(12_288), mode: .gate).failedOpen)
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
        for (probabilities, tail) in [(quietYes, 2624), (quietNo, 2432)] {
            let result = evidence(probabilities, tail: tail)
            let samples = pcm(result.sampleCount)
            let analysis = result.analyze(samples, mode: .gate)
            XCTAssertFalse(result.wouldReject)
            XCTAssertFalse(analysis.rejected)
            XCTAssertFalse(analysis.failedOpen)
            assertSelection(analysis, from: samples, regions: [0..<samples.count])
        }
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
        let first = evidence([1, 1])
        let second = evidence([0, 0, 0])
        XCTAssertTrue(first.hasStrongSpeechPair)
        XCTAssertFalse(second.hasStrongSpeechPair)
        XCTAssertFalse(first.wouldReject)
        XCTAssertTrue(second.wouldReject)
        XCTAssertEqual(second.activeWindows, 0)
        XCTAssertEqual(second.speechScore, 0)
    }

    func testLongInitialAndFinalSilenceKeepSafeBoundaries() {
        let chunk = SpeechPresencePolicy.chunkSize
        for (leading, trailing) in [(12, 0), (0, 14), (12, 14)] {
            let result = evidence(Array(repeating: 0, count: leading) + [1, 1, 1] + Array(repeating: 0, count: trailing))
            let samples = pcm(result.sampleCount)
            let analysis = result.analyze(samples, mode: .gate)
            XCTAssertFalse(analysis.rejected)
            XCTAssertFalse(analysis.failedOpen)
            let start = max(0, leading * chunk - SpeechPresencePolicy.preRollSamples)
            let end = min(samples.count, (leading + 3) * chunk + SpeechPresencePolicy.hangoverSamples)
            assertSelection(analysis, from: samples, regions: [start..<end])
        }
    }

    func testTwentySecondsWithFiveSecondInternalAndFinalPauses() {
        // Coarse evidence for speech at 0-5 s and 10-15 s in a 20 s capture.
        let result = evidence(Array(repeating: 1, count: 20) + Array(repeating: 0, count: 19)
            + Array(repeating: 1, count: 20) + Array(repeating: 0, count: 20), tail: 512)
        let samples = pcm(result.sampleCount)
        let analysis = result.analyze(samples, mode: .gate)
        XCTAssertEqual(samples.count, 320_000)
        XCTAssertFalse(analysis.rejected)
        XCTAssertFalse(analysis.failedOpen)
        assertSelection(analysis, from: samples, regions: [0..<98_304, 151_552..<258_048])
        XCTAssertEqual(analysis.samples.count, 204_800) // 12.8 s including padding, not captured duration.
    }

    func testNaturalPausesStayAndOnlyLongGapsAreRemoved() {
        // The phone controls had modest leading/trailing silence, not a long pause.
        for probabilities: [Float] in [Array(repeating: 0, count: 6) + [1, 1, 1],
                                      [1, 1, 1] + Array(repeating: 0, count: 9)] {
            let result = evidence(probabilities)
            let samples = pcm(result.sampleCount)
            assertSelection(result.analyze(samples, mode: .gate), from: samples, regions: [0..<samples.count])
        }
        let chunk = SpeechPresencePolicy.chunkSize
        for gap in 0...24 {
            let result = evidence([1, 1, 1] + Array(repeating: 0, count: gap) + [1, 1, 1])
            let samples = pcm(result.sampleCount)
            let analysis = result.analyze(samples, mode: .gate)
            let firstEnd = 3 * chunk + SpeechPresencePolicy.hangoverSamples
            let secondStart = (3 + gap) * chunk - SpeechPresencePolicy.preRollSamples
            let regions = secondStart - firstEnd < SpeechPresencePolicy.minimumRemovedSamples
                ? [0..<samples.count] : [0..<firstEnd, secondStart..<samples.count]
            assertSelection(analysis, from: samples, regions: regions)
            XCTAssertFalse(analysis.rejected)
        }
    }

    func testSingleWindowWordsAndOneSampleTailSurviveInQualifiedTurn() {
        let result = evidence([1, 1, 1] + Array(repeating: 0, count: 20)
            + [SpeechPresencePolicy.threshold] + Array(repeating: 0, count: 20) + [0.31], tail: 1)
        let samples = pcm(result.sampleCount)
        let analysis = result.analyze(samples, mode: .gate)
        let chunk = SpeechPresencePolicy.chunkSize
        // Never require a second local onset window or discard an active tail at Send.
        assertSelection(analysis, from: samples,
                        regions: [0..<7 * chunk, 21 * chunk..<28 * chunk, 42 * chunk..<samples.count])
        XCTAssertEqual(analysis.samples.last, samples.last) // No model repeat-last padding in output.
    }

    func testOffAndObserveNeverTrimOrReject() {
        for probabilities: [Float] in [Array(repeating: 0, count: 24), [1, 1, 1] + Array(repeating: 0, count: 21)] {
            let result = evidence(probabilities)
            let samples = pcm(result.sampleCount)
            for mode: SpeechPresencePolicy.Mode in [.off, .observe] {
                let analysis = result.analyze(samples, mode: mode)
                XCTAssertFalse(analysis.rejected)
                XCTAssertFalse(analysis.failedOpen)
                assertSelection(analysis, from: samples, regions: [0..<samples.count])
            }
        }
    }

    func testIncompleteInvalidAndMismatchedEvidenceReturnOriginalPCM() {
        let samples = pcm(20 * SpeechPresencePolicy.chunkSize)
        var missingTail = SpeechPresencePolicy.Evidence(sampleCount: samples.count)
        for _ in 0..<3 { missingTail.append(probability: 1, sampleCount: SpeechPresencePolicy.chunkSize) }
        var cases = [SpeechPresencePolicy.Evidence(sampleCount: samples.count), missingTail,
                     evidence([1, 1, 1])] // Wrong PCM count despite complete qualifying evidence.
        for invalid in [Float.nan, .infinity, -.infinity, -0.01, 1.01] {
            cases.append(evidence([1, 1, 1] + Array(repeating: 0, count: 16) + [invalid]))
        }
        for count in [0, -1, 4095, 4097] {
            var wrongWindow = missingTail
            wrongWindow.append(probability: 0, sampleCount: count)
            cases.append(wrongWindow)
        }
        var extra = evidence([1, 1, 1] + Array(repeating: 0, count: 17))
        extra.append(probability: 0, sampleCount: 4096)
        cases.append(extra)
        for result in cases {
            let analysis = result.analyze(samples, mode: .gate)
            XCTAssertTrue(analysis.failedOpen)
            XCTAssertFalse(analysis.rejected)
            assertSelection(analysis, from: samples, regions: [0..<samples.count])
        }
        let empty = SpeechPresencePolicy.Evidence(sampleCount: 0).analyze([], mode: .gate)
        XCTAssertTrue(empty.failedOpen)
        assertSelection(empty, from: [], regions: [])
    }

    func testAbandonedPartialTurnCannotAffectNextTurn() {
        let count = 24 * SpeechPresencePolicy.chunkSize
        var abandoned = SpeechPresencePolicy.Evidence(sampleCount: count)
        for _ in 0..<3 { abandoned.append(probability: 1, sampleCount: SpeechPresencePolicy.chunkSize) }
        // Cancellation discards this call's evidence. A new call starts from an empty value.
        let next = evidence(Array(repeating: 0, count: 24))
        let nextPCM = pcm(count, offset: count)
        XCTAssertTrue(next.analyze(nextPCM, mode: .gate).rejected)
        var newTurn = SpeechPresencePolicy.Evidence(sampleCount: count)
        let unavailable = newTurn.analyze(nextPCM, mode: .gate)
        XCTAssertTrue(unavailable.failedOpen)
        assertSelection(unavailable, from: nextPCM, regions: [0..<count])
        for index in 0..<24 { newTurn.append(probability: index >= 21 ? 1 : 0, sampleCount: 4096) }
        assertSelection(newTurn.analyze(nextPCM, mode: .gate), from: nextPCM, regions: [19 * 4096..<count])
        XCTAssertFalse(abandoned.complete)
        XCTAssertEqual(abandoned.processedSamples, 3 * 4096)
    }

    func testMaximumTurnAndAllSampleOrdersAreBounded() {
        // Sweep the position of a qualified onset across the full 30-second bound.
        for onset in stride(from: 0, through: 115, by: 5) {
            var probabilities = Array(repeating: Float(0), count: 118)
            for index in onset..<onset + 3 { probabilities[index] = 1 }
            let result = evidence(probabilities, tail: 768)
            let samples = pcm(result.sampleCount)
            let analysis = result.analyze(samples, mode: .gate)
            XCTAssertEqual(samples.count, 480_000)
            XCTAssertFalse(analysis.rejected)
            XCTAssertLessThanOrEqual(analysis.samples.count, samples.count)
            XCTAssertTrue(zip(analysis.samples, analysis.samples.dropFirst()).allSatisfy { $0 < $1 })
            XCTAssertTrue(analysis.regions.allSatisfy { !$0.isEmpty && $0.lowerBound >= 0 && $0.upperBound <= samples.count })
            XCTAssertEqual(analysis.samples, analysis.regions.flatMap { samples[$0] })
        }
    }
}
