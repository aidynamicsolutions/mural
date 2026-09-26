#if MURAL_TTS_EXPERIMENT
import AVFoundation
import CryptoKit
import Foundation
import MuralCore
import Observation
import UIKit

#if DEBUG && targetEnvironment(simulator)
@MainActor private final class DelayedTTSSafetySample {
    private var calls = 0
    private var staleSample: CheckedContinuation<[String: UInt64], Never>?
    private var staleStarted: CheckedContinuation<Void, Never>?
    private var currentStarted: CheckedContinuation<Void, Never>?

    func next() async -> [String: UInt64] {
        calls += 1
        switch calls {
        case 1:
            return await withCheckedContinuation { continuation in
                staleSample = continuation
                staleStarted?.resume(); staleStarted = nil
            }
        case 2:
            currentStarted?.resume(); currentStarted = nil
            return ["footprintBytes": 0]
        default:
            return ["footprintBytes": 0]
        }
    }

    func waitForStaleSample() async {
        if staleSample != nil { return }
        await withCheckedContinuation { staleStarted = $0 }
    }

    func waitForCurrentSample() async {
        if calls >= 2 { return }
        await withCheckedContinuation { currentStarted = $0 }
    }

    func releaseStaleSample() {
        staleSample?.resume(returning: ["footprintBytes": 3_000_000_000])
        staleSample = nil
    }
}
#endif

@MainActor @Observable final class TTSComparisonRunner {
    let audio: LocalConversationEngine
    private(set) var phrases: [TTSComparisonPhrase] = []
    private(set) var status = "Prepare a voice, or explicitly play a quiet test signal."
    private(set) var error: String?
    private(set) var prepared = false
    private(set) var summary = "No measurements yet."
    private(set) var exportURL: URL?
    private var task: Task<Void, Never>?
    private var stopped = false
    private var safetyStopped = false
    private(set) var thermalStopped = false
    private var resetWhenDrained = false
    private var records: [[String: Any]] = []
    var busy: Bool { task != nil || audio.speechBusy }

    init(audio: LocalConversationEngine) {
        self.audio = audio
        do { phrases = try TTSComparisonPhrase.corpus() }
        catch { self.error = "The fixed speech corpus could not be read." }
    }

    func select(_ backend: LocalTTSBackend) {
        guard !busy else { return }
        do { try audio.selectTTS(backend); prepared = false; error = nil }
        catch { self.error = error.localizedDescription }
    }

    func prepare() {
        guard !busy, !safetyStopped else { return }
        if thermalStopped || audio.thermalStopped {
            do { try audio.resumeAfterCooling(); thermalStopped = false }
            catch { self.error = error.localizedDescription; return }
        }
        start {
            self.status = "Preparing…"; self.prepared = false
            let begin = ProcessInfo.processInfo.systemUptime
            let before = Self.footprint()
            var maximum = before
            try self.checkSafety(footprint: before)
            let sampling = Task { @MainActor in
                while !Task.isCancelled {
                    if let value = Self.footprint() { maximum = max(maximum ?? 0, value) }
                    do { try self.checkSafety(footprint: maximum) }
                    catch { self.recordSafetyStop(error); self.stop(); return }
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
            }
            var failure: Error?
            do {
                try await self.audio.prepareTTS { [self] message in status = message }
                try Task.checkCancellation()
            } catch { failure = error }
            sampling.cancel()
            await sampling.value
            let after = Self.footprint()
            if let after { maximum = max(maximum ?? 0, after) }
            do { try self.checkSafety(footprint: maximum) }
            catch { self.recordSafetyStop(error); if failure == nil { failure = error } }
            var record = self.audio.ttsPreparation
            record["backend"] = self.audio.ttsBackend.rawValue
            record["status"] = failure == nil ? "prepared" : self.stopped ? "cancelled" : "failed"
            record["error_category"] = failure.map { String(describing: type(of: $0)) } as Any? ?? NSNull()
            record["total_setup_ms"] = (ProcessInfo.processInfo.systemUptime - begin) * 1_000
            record["phys_footprint_before_bytes"] = before as Any? ?? NSNull()
            record["max_sampled_phys_footprint_bytes"] = maximum as Any? ?? NSNull()
            record["phys_footprint_after_bytes"] = after as Any? ?? NSNull()
            record["thermal_after"] = ProcessInfo.processInfo.thermalState.rawValue
            let directory = URL.documentsDirectory.appending(path: "TTSComparison")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try self.writeJSON(record, to: directory.appending(path: "prepare-\(UUID().uuidString).json"))
            if let failure { throw failure }
            self.prepared = true
            self.status = String(format: "Prepared in %.0f ms. %@", (ProcessInfo.processInfo.systemUptime - begin) * 1_000,
                self.audio.ttsBackend == .apple ? "Apple voice." : "\(self.audio.supertonicVoice.rawValue) ready; first synthesis loads its int4 bucket.")
        }
    }

    func play(phraseID: String) {
        guard prepared, let phrase = phrases.first(where: { $0.id == phraseID }) else { return }
        measure([phrase], signalRate: nil)
    }

    func runCorpus() {
        guard prepared else { return }
        measure(phrases, signalRate: nil)
    }

    func runSmoke() {
        guard prepared else { return }
        measure(phrases.filter { ["01", "06", "11", "17", "29"].contains($0.id) }, signalRate: nil)
    }

    func playSignal(rate: Double) { measure([], signalRate: rate) }

    func stop(leaving: Bool = false) {
        stopped = true
        resetWhenDrained = resetWhenDrained || leaving
        task?.cancel()
        audio.stopSpeech()
        prepared = false
        status = busy ? "Stopping; waiting for work to drain…" : "Stopped."
        if task == nil {
            task = Task {
                if resetWhenDrained { await audio.finishTTSComparison() }
                else { await audio.waitForTTSCleanup() }
                resetWhenDrained = false
                status = "Stopped. Work drained."
                task = nil
            }
        }
    }

    func memoryWarning() {
        safetyStopped = true
        stop()
        error = "Speech experiment stopped after an iPhone memory warning."
    }

    /// Exercises the actual app admission/cancellation seam with suspended work, not native inference.
    func checkLifecycle() {
        start {
            func require(_ value: Bool) throws {
                if !value { throw SafetyStop(message: "Lifecycle check failed. Stop and inspect the implementation.") }
            }
            #if DEBUG && targetEnvironment(simulator)
            let delayedAudio = LocalConversationEngine()
            let delayedSample = DelayedTTSSafetySample()
            delayedAudio.testTTSSafetySampler = { await delayedSample.next() }
            delayedAudio.startTTSConversationMonitorForTesting()
            await delayedSample.waitForStaleSample()
            guard let staleMonitor = delayedAudio.testTTSConversationMonitorTask else {
                throw SafetyStop(message: "Safety monitor did not start.")
            }
            delayedAudio.stop()
            delayedAudio.startTTSConversationMonitorForTesting()
            await delayedSample.waitForCurrentSample()
            guard let currentMonitor = delayedAudio.testTTSConversationMonitorTask else {
                throw SafetyStop(message: "Replacement safety monitor did not start.")
            }
            delayedSample.releaseStaleSample()
            await staleMonitor.value
            try require(delayedAudio.canPrepare && !delayedAudio.thermalStopped)
            delayedAudio.stop()
            await currentMonitor.value

            let sampledMemoryAudio = LocalConversationEngine()
            var sampledMemoryStopped = false
            sampledMemoryAudio.onSafetyStop = { reason in sampledMemoryStopped = reason == .memoryPressure }
            sampledMemoryAudio.testTTSSafetySampler = { ["footprintBytes": 3_000_000_000] }
            sampledMemoryAudio.startTTSConversationMonitorForTesting()
            guard let sampledMemoryMonitor = sampledMemoryAudio.testTTSConversationMonitorTask else {
                throw SafetyStop(message: "Memory safety monitor did not start.")
            }
            await sampledMemoryMonitor.value
            try require(sampledMemoryStopped && sampledMemoryAudio.canPrepare)

            let sampledThermalAudio = LocalConversationEngine()
            sampledThermalAudio.testThermalState = .serious
            var sampledThermalStopped = false
            sampledThermalAudio.onSafetyStop = { reason in sampledThermalStopped = reason == .thermal }
            sampledThermalAudio.testTTSSafetySampler = { ["footprintBytes": 0] }
            sampledThermalAudio.startTTSConversationMonitorForTesting()
            guard let sampledThermalMonitor = sampledThermalAudio.testTTSConversationMonitorTask else {
                throw SafetyStop(message: "Thermal safety monitor did not start.")
            }
            await sampledThermalMonitor.value
            try require(sampledThermalStopped && sampledThermalAudio.thermalStopped)

            let thermalAudio = LocalConversationEngine()
            thermalAudio.testThermalState = .serious
            thermalAudio.stopForTTSSafety(footprint: 80_000_000, thermal: .serious)
            try require(thermalAudio.thermalStopped && thermalAudio.canPrepare)
            do { try thermalAudio.resumeAfterCooling(); try require(false) } catch LocalTTSError.phoneTooWarm { }
            thermalAudio.testThermalState = .nominal
            try require(thermalAudio.thermalStopped) // Cooling alone does not resume.
            do { try await thermalAudio.speak("No automatic restart"); try require(false) } catch LocalTTSError.phoneTooWarm { }
            try thermalAudio.resumeAfterCooling()
            try require(!thermalAudio.thermalStopped && !thermalAudio.speechBusy)
            // Memory pressure stops current work but does not latch the engine after drain.
            thermalAudio.stopForTTSSafety(footprint: 3_000_000_000, thermal: .nominal)
            try require(thermalAudio.canPrepare && !thermalAudio.thermalStopped)
            #endif
            try self.audio.selectTTS(.apple)
            for text in ["", " \n\t", String(repeating: "a", count: 1_001)] {
                do { try await self.audio.speak(text); try require(false) }
                catch is LocalTTSError { }
            }
            var release: CheckedContinuation<Void, Never>?
            let worker = Task { @MainActor in
                try await self.audio.performSpeech { _ in
                    await withCheckedContinuation { release = $0 } // Intentionally noncooperative, like native inference.
                }
            }
            defer { release?.resume(); worker.cancel() }
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            while release == nil, ProcessInfo.processInfo.systemUptime < deadline {
                try await Task.sleep(for: .milliseconds(1))
            }
            try require(release != nil && self.audio.speechBusy && !self.audio.canPrepare && !self.audio.canRecord)
            do { try await self.audio.speak("Second request"); try require(false) }
            catch is LocalTTSError { }
            do { try self.audio.selectTTS(.supertonic); try require(false) }
            catch is LocalTTSError { }
            do { try self.audio.selectSupertonicVoice(.f1); try require(false) }
            catch is LocalTTSError { }
            self.audio.stopSpeech()
            try require(self.audio.speechBusy && self.audio.speechDraining)
            release?.resume(); release = nil
            do { try await worker.value; try require(false) } catch is CancellationError { }
            try require(!self.audio.speechBusy && self.audio.canPrepare)
            var entered = false
            let cancelled = Task { try await self.audio.performSpeech { _ in entered = true } }
            cancelled.cancel()
            do { try await cancelled.value; try require(false) } catch is CancellationError { }
            try require(!entered && !self.audio.speechBusy)
            try self.audio.selectTTS(.kokoro)
            var failedPreparation = false
            do { try await self.audio.prepareTTS() } catch { failedPreparation = true }
            try require(failedPreparation && !self.audio.speechBusy)
            try self.audio.selectTTS(.apple)
            self.prepared = false
            self.status = "Lifecycle checks passed. No audio or models used."
        }
    }

    private func start(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy, !safetyStopped else { return }
        error = nil; stopped = false
        task = Task {
            do { try Task.checkCancellation(); try await operation() }
            catch is CancellationError { status = "Stopped. Waiting for cleanup…" }
            catch LocalTTSError.phoneTooWarm {
                recordSafetyStop(LocalTTSError.phoneTooWarm)
                prepared = false; audio.stopSpeech()
                status = "Speech paused. Let your iPhone cool, then tap Resume."
            }
            catch let failure as SafetyStop {
                safetyStopped = true; error = failure.localizedDescription; prepared = false; audio.stopSpeech()
                status = "Safety stop. Do not retry unchanged."
            }
            catch { self.error = error.localizedDescription; status = "Failed. No fallback used."; prepared = false; audio.stopSpeech() }
            await audio.waitForTTSCleanup()
            if stopped { status = thermalStopped ? "Speech paused. Let your iPhone cool, then tap Resume." : "Stopped. Work drained." }
            if resetWhenDrained { await audio.finishTTSComparison(); resetWhenDrained = false }
            task = nil
        }
    }

    private func measure(_ batch: [TTSComparisonPhrase], signalRate: Double?) {
        start {
            let run = UUID().uuidString
            let directory = URL.documentsDirectory.appending(path: "TTSComparison/\(run)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.exportURL = nil; self.records = []
            self.audio.clearSubmissionTiming()
            let corpusHash = SHA256.hash(data: try TTSComparisonPhrase.corpusData()).map { String(format: "%02x", $0) }.joined()
            let session = AVAudioSession.sharedInstance()
            UIDevice.current.isBatteryMonitoringEnabled = true
            let manifest: [String: Any] = [
                "schema_version": 1, "run_id": run, "created_at": Date().ISO8601Format(),
                "mode": "tts-only", "backend": signalRate == nil ? self.audio.ttsBackend.rawValue : "synthetic-signal-not-speech",
                "voice": signalRate == nil ? self.audio.ttsVoiceDescription : "440 Hz at 0.035 amplitude, 20 ms fades",
                "os": ProcessInfo.processInfo.operatingSystemVersionString, "device": UIDevice.current.model,
                "bundle": Bundle.main.bundleIdentifier ?? "unknown", "corpus_sha256": corpusHash,
                "package_revision": "41540ea237350afe5117a082b5c28eda642d0612",
                "volume": session.outputVolume, "audio_route": session.currentRoute.outputs.map(\.portType.rawValue),
                "low_power_mode": ProcessInfo.processInfo.isLowPowerModeEnabled,
                "battery_state": UIDevice.current.batteryState.rawValue,
                "timing_method": signalRate == nil && self.audio.ttsBackend == .apple ? "AVSpeechSynthesizer.didStart callback" : "player sample clock observed every 5 ms; acoustic latency excluded",
                "preparation": signalRate == nil && self.audio.ttsBackend == .supertonic ? self.audio.ttsPreparation : [:],
                "debugger_attachment": "not-measured",
                "limitations": "TTS-only. Apple has no generated waveform/synthesis timing. Synthetic signals are not model performance. Exact executable/device identity is in agent evidence. Native inference may only drain after Stop."
            ]
            try self.writeJSON(manifest, to: directory.appending(path: "manifest.json"))
            let jsonl = directory.appending(path: "utterances.jsonl")
            FileManager.default.createFile(atPath: jsonl.path, contents: nil)
            let handle = try FileHandle(forWritingTo: jsonl)
            defer { try? handle.close() }
            let iterations = signalRate == nil ? batch.count : 1
            for index in 0..<iterations {
                try Task.checkCancellation()
                let phrase = signalRate == nil ? batch[index] : nil
                self.status = signalRate == nil ? "Playing \(index + 1) of \(iterations)…" : "Playing quiet synthetic signal…"
                let before = Self.footprint()
                var maximum = before
                let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
                try self.checkSafety(footprint: before)
                let sampling = Task { @MainActor in
                    while !Task.isCancelled {
                        if let value = Self.footprint() { maximum = max(maximum ?? 0, value) }
                        do { try self.checkSafety(footprint: maximum) }
                        catch { self.recordSafetyStop(error); self.stop(); return }
                        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    }
                }
                let requested = ProcessInfo.processInfo.systemUptime
                var playbackStart: Double?
                var playbackEnd: Double?
                var completed = false
                self.audio.onPlayback = { start, end, done in playbackStart = start; playbackEnd = end; completed = done }
                var failure: Error?
                do {
                    if let rate = signalRate { try await self.audio.playTestSignal(sampleRate: rate) }
                    else if let phrase { try await self.audio.speak(phrase.text) }
                } catch { failure = error }
                sampling.cancel()
                await sampling.value
                self.audio.onPlayback = nil
                let after = Self.footprint()
                if let after { maximum = max(maximum ?? 0, after) }
                do { try self.checkSafety(footprint: maximum) }
                catch { self.recordSafetyStop(error); if failure == nil { failure = error } }
                let synthesis = self.audio.lastSynthesis
                let record: [String: Any] = [
                    "schema_version": 1, "run_id": run, "phrase_id": phrase?.id ?? "synthetic",
                    "category": phrase?.category ?? "signal", "backend": manifest["backend"]!,
                    "sample_rate_hz": (signalRate ?? synthesis.map { _ in 44_100 }) as Any? ?? NSNull(),
                    "synth_ms": synthesis?.milliseconds as Any? ?? NSNull(),
                    "audio_ms": (signalRate == nil ? synthesis?.audioMilliseconds : 1_000) as Any? ?? NSNull(),
                    "cache_state": synthesis.map { $0.first ? "first-synthesis-after-init" : "warm" } ?? "not-applicable",
                    "clipping_detected": synthesis?.clipping as Any? ?? NSNull(),
                    "native_drain_ms": self.audio.speechDrainMilliseconds as Any? ?? NSNull(),
                    "stop_to_silence_estimated_ms": self.audio.speechStopMilliseconds as Any? ?? NSNull(),
                    "rtf": synthesis.map { $0.milliseconds / $0.audioMilliseconds } as Any? ?? NSNull(),
                    "request_to_playback_start_estimated_ms": playbackStart.map { ($0 - requested) * 1_000 } as Any? ?? NSNull(),
                    "playback_elapsed_ms": playbackStart.flatMap { start in playbackEnd.map { ($0 - start) * 1_000 } } as Any? ?? NSNull(),
                    "phys_footprint_before_bytes": before as Any? ?? NSNull(),
                    "max_sampled_phys_footprint_bytes": maximum as Any? ?? NSNull(),
                    "phys_footprint_after_bytes": after as Any? ?? NSNull(),
                    "thermal_before": thermalBefore, "thermal_after": ProcessInfo.processInfo.thermalState.rawValue,
                    "status": failure == nil && completed ? "completed" : self.stopped ? "cancelled" : "failed",
                    "error_category": failure.map { String(describing: type(of: $0)) } as Any? ?? NSNull()
                ]
                var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                data.append(0x0A)
                try handle.write(contentsOf: data)
                try handle.synchronize() // Preserve earlier utterances if a later operation crashes.
                self.records.append(record)
                let successful = self.records.filter { $0["status"] as? String == "completed" }
                let startups = successful.compactMap { $0["request_to_playback_start_estimated_ms"] as? Double }
                let warm = successful.filter { $0["cache_state"] as? String == "warm" }
                let synthTimes = warm.compactMap { $0["synth_ms"] as? Double }
                let durations = warm.compactMap { $0["audio_ms"] as? Double }
                let result: [String: Any] = ["manifest": manifest, "utterances": self.records,
                    "warm_synth_p50_ms": TTSStatistics.percentile(synthTimes, fraction: 0.5) as Any? ?? NSNull(),
                    "warm_synth_p95_ms": TTSStatistics.percentile(synthTimes, fraction: 0.95) as Any? ?? NSNull(),
                    "warm_aggregate_rtf": TTSStatistics.aggregateRTF(synthesis: synthTimes, audio: durations) as Any? ?? NSNull(),
                    "completed": successful.count, "failed_or_cancelled": self.records.count - successful.count,
                    "playback_start_p50_ms": TTSStatistics.percentile(startups, fraction: 0.5) as Any? ?? NSNull(),
                    "playback_start_p95_ms": TTSStatistics.percentile(startups, fraction: 0.95) as Any? ?? NSNull()]
                let url = directory.appending(path: "report.json")
                try self.writeJSON(result, to: url)
                self.exportURL = url
                self.summary = "\(successful.count) completed; \(self.records.count - successful.count) failed or cancelled."
                if let synthesis {
                    self.summary += String(format: " Last synthesis %.0f ms; audio %.1f s; RTF %.3f.%@", synthesis.milliseconds,
                        synthesis.audioMilliseconds / 1_000, synthesis.milliseconds / synthesis.audioMilliseconds,
                        synthesis.clipping ? " Clipping detected; no normalization applied." : "")
                }
                if let failure { throw failure }
                guard completed else { throw CancellationError() }
            }
            self.status = "Finished."
        }
    }

    private func checkSafety(footprint: UInt64?) throws {
        if let footprint, footprint >= 3_000_000_000 { throw SafetyStop(message: "Stopped at the 3.0 GB sampled footprint guard. Do not retry unchanged.") }
        if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
            throw LocalTTSError.phoneTooWarm
        }
    }
    private func recordSafetyStop(_ failure: Error) {
        if case LocalTTSError.phoneTooWarm = failure { thermalStopped = true }
        else { safetyStopped = true }
        error = failure.localizedDescription
    }
    private struct SafetyStop: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
    private static func footprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }
}
#endif
