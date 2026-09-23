#!/usr/bin/env python3
"""Compile real selection/default policy on host; no Apple native execution claims.

Core AI model/cache operations are deliberately not available here. The selector
uses the production source and verifier; only filesystem hashes and device
architecture are supplied as test doubles. Run Apple Release/device gates too.
"""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "App/LocalConversationEngine.swift"
VERIFIER = ROOT / "Tools/CoreAI/W8IdentityVerifier.swift"
SWIFTC = shutil.which("swiftc")


def selection_source() -> str:
    source = SOURCE.read_text()
    selection = source.split("    enum CompressionCandidate:", 1)[1].split("    static var enabled:", 1)[0]
    enabled = source.split("    static var enabled:", 1)[1].split("    @concurrent static func prepareForConversation", 1)[0]
    policy = "enum DecoderTrialPolicy {" + source.split("enum DecoderTrialPolicy {", 1)[1]
    return r'''import Foundation
#if os(Linux)
extension URL {
    static var applicationSupportDirectory: URL { URL(fileURLWithPath: "/mural-host-test-not-an-asset/support") }
    static var documentsDirectory: URL { URL(fileURLWithPath: "/mural-host-test-not-an-asset/documents") }
}
#endif
struct ReviewFailure: Error { init(_ message: String) {} }
enum AIModel {
    static var deviceArchitectureName: String {
        ProcessInfo.processInfo.environment["REVIEW_ARCH"] ?? "h18p"
    }
}
enum LocalSpeechPair { case vietnameseEnglish }
enum LocalSpeechProvisioning {
    static func installedDirectory(for pair: LocalSpeechPair, component: String) throws -> URL? { nil }
}
enum PhoWhisperStagedEncoder {
    typealias Failure = ReviewFailure
    enum CompressionCandidate:''' + selection + "    static var enabled:" + enabled + r'''
    static func sha256(_ data: Data) -> String { "not-a-qualified-v3-manifest" }
    static func bundleBytes(_ url: URL) throws -> Int { 0 }
    static func fingerprint(_ url: URL, includeHiddenFiles: Bool = false) throws -> String {
        ProcessInfo.processInfo.environment["REVIEW_FINGERPRINT"] ??
            "f783c9b539d90a589e1449e514599e240ce6036b3bab6c298858e49bba112829"
    }
}
''' + policy + r'''
@main struct ReviewCheck {
    static func main() async {
        if CommandLine.arguments.contains("--review-enabled") {
            print(PhoWhisperStagedEncoder.enabled)
            return
        }
        do {
            let result = try await PhoWhisperStagedEncoder.verifiedSelection()
            print(result.supportIdentity)
        } catch { exit(2) }
    }
}
'''


@unittest.skipUnless(SWIFTC, "Swift compiler required; no native Apple inference is tested")
class SelectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        cls.source = cls.root / "selection.swift"
        cls.source.write_text(selection_source())

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def compile(self, name, flags=()):
        binary = self.root / name
        result = subprocess.run(
            [SWIFTC, "-parse-as-library", "-D", "MURAL_W8_IDENTITY_PORTABLE_TEST",
             *flags, str(VERIFIER), str(self.source), "-o", str(binary)],
            text=True, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        return binary

    def run_binary(self, binary, args=(), **environment):
        return subprocess.run([str(binary), *args], text=True, capture_output=True,
                              timeout=10, env={**os.environ, **environment})

    def test_default_backend_is_enabled_in_every_build_matrix_entry(self):
        for name, flags in (
            ("release", ()),
            ("debug", ("-D", "DEBUG")),
            ("talk-release", ("-D", "MURAL_COREAI_TALK")),
            ("w8-release", ("-D", "MURAL_COREAI_TALK", "-D", "MURAL_COREAI_W8")),
        ):
            with self.subTest(build=name):
                binary = self.compile(name, flags)
                for args in ((), ("--coreai-talk-gpu",)):
                    result = self.run_binary(binary, ("--review-enabled", *args))
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), "true")

    def test_legacy_selection_checks_architecture_and_fingerprint(self):
        binary = self.compile("legacy", ("-D", "MURAL_COREAI_TALK", "-D", "MURAL_COREAI_W8"))
        for args, support in ((("--coreai-compressed-encoder=original-pal8",), "phowhisper-cs-pal8-g16-v1"),):
            with self.subTest(args=args):
                good = self.run_binary(binary, args)
                self.assertEqual(good.returncode, 0)
                self.assertEqual(good.stdout.strip(), support)
                self.assertNotEqual(self.run_binary(binary, args, REVIEW_ARCH="unqualified").returncode, 0)
                self.assertNotEqual(self.run_binary(binary, args, REVIEW_FINGERPRINT="changed").returncode, 0)

    def test_legacy_aliases_and_invalid_v3_selections_fail_closed(self):
        binary = self.compile("reject", ("-D", "MURAL_COREAI_TALK", "-D", "MURAL_COREAI_W8"))
        cases = [
            *[(f"--coreai-compressed-encoder={fmt}",) for fmt in ("fp8", "int8", "fp8-pal8", "int8-pal8")],
            ("--coreai-w8-v3-decoder=pal8",),
            ("--coreai-w8-v3-encoder=unknown",),
            ("--coreai-w8-v3-encoder=fp8", "--coreai-w8-v3-encoder=fp8"),
            ("--coreai-w8-v3-encoder=fp8", "--coreai-w8-v3-decoder=unknown"),
            ("--coreai-w8-v3-encoder=pal4", "--coreai-w8-v3-decoder=pal4"),
            ("--coreai-w8-v3-encoder=pal6", "--coreai-w8-v3-decoder=pal6"),
            ("--coreai-w8-v3-encoder=fp8", "--coreai-compressed-encoder=original-pal8"),
            ("--coreai-w8-v3-encoder=fp8", "--coreai-w8-v3-decoder=pal8"), # no pinned assets on host
        ]
        for args in cases:
            with self.subTest(args=args):
                self.assertNotEqual(self.run_binary(binary, args).returncode, 0)


@unittest.skipUnless(SWIFTC, "Swift compiler required")
class DecoderPolicyTests(unittest.TestCase):
    def test_actual_decoder_and_combined_policy_matrix(self):
        swift = r'''import Foundation
func rejects(_ operation: () throws -> Void) {
    do { try operation(); fatalError("Invalid trial was admitted") }
    catch is DecoderTrialPolicy.Failure {} catch { fatalError("Unexpected failure: \(error)") }
}
@main struct Check {
    static func main() throws {
        let allowed = Set(["fp16/fp16", "fp16/pal8", "fp8/fp16", "fp8/pal8", "fp8/pal6", "fp8/pal4",
                           "int8/fp16", "int8/pal8", "pal6/pal8", "pal4/pal8"])
        for encoder in ["fp16", "fp8", "int8", "pal6", "pal4"] {
            for decoder in ["fp16", "pal8", "pal6", "pal4"] {
                let args = ["--coreai-w8-v3-encoder=\(encoder)", "--coreai-w8-v3-decoder=\(decoder)"]
                if allowed.contains("\(encoder)/\(decoder)") {
                    try DecoderTrialPolicy.validatePair(encoder: encoder, decoder: decoder, arguments: args)
                    let once = try DecoderTrialPolicy.once(args)
                    precondition(!once) // Historical/default policy must remain always.
                } else {
                    rejects { try DecoderTrialPolicy.validatePair(encoder: encoder, decoder: decoder, arguments: args) }
                }
            }
        }
        for precision in ["pal6", "pal4"] {
            let args = ["--coreai-w8-v3-encoder=\(precision)", "--coreai-w8-v3-decoder=\(precision)",
                        "--coreai-w8-v3-combined=\(precision)-\(precision)"]
            try DecoderTrialPolicy.validatePair(encoder: precision, decoder: precision, arguments: args)
            for mode in ["staged-gpu", "staged-gpu-encode"] {
                let once = try DecoderTrialPolicy.once(args + ["--coreai-product-mode=\(mode)", "--coreai-w8-v3-prewarm=always"])
                precondition(!once)
            }
            for extra in [["--coreai-product-mode=hybrid"], ["--coreai-product-coexistence"],
                          [args.last!], ["--coreai-product-mode=staged-gpu-encode", "--coreai-w8-v3-prewarm=once"]] {
                rejects { _ = try DecoderTrialPolicy.once(args + extra) }
            }
        }
        let selected = ["--coreai-w8-v3-encoder=fp8", "--coreai-w8-v3-decoder=pal8"]
        let repeated = try DecoderTrialPolicy.once(selected + ["--coreai-w8-v3-prewarm=always"])
        let once = try DecoderTrialPolicy.once(selected + ["--coreai-w8-v3-prewarm=once"])
        precondition(!repeated && once)
        for extra in [["--coreai-w8-v3-prewarm=unknown"],
                      ["--coreai-w8-v3-prewarm=always", "--coreai-w8-v3-prewarm=always"],
                      ["--coreai-w8-v3-prewarm=once", "--coreai-product-mode=hybrid"],
                      ["--coreai-w8-v3-combined=pal6-pal6"], ["--coreai-w8-v3-combined=unknown"]] {
            rejects { _ = try DecoderTrialPolicy.once(selected + extra) }
        }
        rejects { _ = try DecoderTrialPolicy.once(["--coreai-w8-v3-prewarm=once"]) }
        print("PASS: 20 precision pairs, both joint opt-ins, default/once and rejection boundaries")
    }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "check.swift"
            path.write_text(swift)
            binary = Path(directory) / "check"
            compilation = subprocess.run([SWIFTC, "-parse-as-library",
                str(ROOT / "Tools/CoreAI/DecoderTrialPolicy.swift"), str(path), "-o", str(binary)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("PASS: 20 precision pairs", result.stdout)


@unittest.skipUnless(SWIFTC and sys.platform == "darwin", "Apple AVAudioConverter required")
class ConverterTests(unittest.TestCase):
    def test_actual_converter_preserves_short_packets_and_drains_tail(self):
        # Native Mac conversion, synthetic PCM only. No microphone or ASR accuracy claim.
        method = SOURCE.read_text().split('    private nonisolated static func convert(', 1)[1].split(
            '    #if (DEBUG || MURAL_COREAI_W8)', 1)[0]
        swift = r'''import Foundation
import AVFoundation
enum Check {
    enum CaptureError: Error { case format }
    static func convert(''' + method + r'''
    static func run(_ frames: Int, packetSize: Int, channels: AVAudioChannelCount) throws -> [Float] {
        let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000,
                                  channels: channels, interleaved: false)!
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                  channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: source, to: target)!
        var result: [Float] = []
        for offset in stride(from: 0, to: frames, by: packetSize) {
            let count = min(packetSize, frames - offset)
            let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(count))!
            input.frameLength = AVAudioFrameCount(count)
            for channel in 0..<Int(channels) {
                for i in 0..<count {
                    let position = offset + i
                    let wave = Float(sin(Double(position) * 2 * .pi * 440 / 48000)) * 0.2
                    input.floatChannelData![channel][i] = wave + (position == 0 || position == frames - 1 ? 0.5 : 0)
                }
            }
            result += try convert(converter, input: input, target: target,
                                  capacity: AVAudioFrameCount(ceil(Double(count) / 3) + 64))
        }
        result += try convert(converter, input: nil, target: target, capacity: 4096)
        let remaining = try convert(converter, input: nil, target: target, capacity: 4096)
        precondition(remaining.isEmpty, "Single tail flush left converter output")
        precondition(result.count == frames / 3,
                     "frames=\(frames) packet=\(packetSize) channels=\(channels) output=\(result.count)")
        precondition(result.allSatisfy(\.isFinite))
        return result
    }
}
@main struct Main {
    static func main() throws {
        var cases = 0
        for frames in [480, 4800, 24576, 24579, 91200, 110400, 134400, 163200] {
            for channels: AVAudioChannelCount in [1, 2] {
                let whole = try Check.run(frames, packetSize: frames, channels: channels)
                for packet in [480, 4800] {
                    let chunked = try Check.run(frames, packetSize: packet, channels: channels)
                    precondition(chunked.count == whole.count)
                    precondition(zip(chunked, whole).allSatisfy { abs($0 - $1) < 0.000001 })
                    cases += 1
                }
            }
        }
        print("PASS: \(cases) synthetic packetizations, exact counts, tail drain and boundary sample parity")
    }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "converter.swift"
            path.write_text(swift)
            binary = Path(directory) / "converter"
            build = subprocess.run([SWIFTC, "-parse-as-library", str(path), "-o", str(binary)],
                                   text=True, capture_output=True, timeout=60)
            self.assertEqual(build.returncode, 0, build.stderr)
            result = subprocess.run([str(binary)], text=True, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("PASS: 32 synthetic packetizations", result.stdout)


@unittest.skipUnless(SWIFTC and sys.platform == "darwin", "Apple AVAudioFile required")
class VADFixtureTests(unittest.TestCase):
    def test_actual_writer_preserves_pcm_bounds_and_cancellation(self):
        method = SOURCE.read_text().split('    private nonisolated static func writeVADFixture(', 1)[1].split('\n    #endif', 1)[0]
        swift = r'''import Foundation
import AVFoundation
import CryptoKit
enum Check {
    enum CaptureError: Error { case format; case operation(String) }
    static func writeVADFixture(''' + method + r'''
}
func rejects(_ operation: () throws -> Void) {
    do { try operation(); fatalError("Invalid or excess fixture accepted") } catch {}
}
@main struct Main {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let directory = root.appending(path: "fixtures")
        let pattern: [Float] = [0, -0.25, 0.5, -1, 1]
        let samples = Array(repeating: pattern, count: 7680).flatMap { $0 }
        let id = UUID()
        let hash = try Check.writeVADFixture(samples, turnID: id, directory: directory)
        let file = directory.appending(path: "\(id.uuidString).wav")
        let originalBytes = try Data(contentsOf: file)
        let audio = try AVAudioFile(forReading: file)
        precondition(audio.processingFormat.sampleRate == 16000 && audio.processingFormat.channelCount == 1)
        precondition(audio.length == samples.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length))!
        var reread: [Float] = []
        while reread.count < samples.count {
            try audio.read(into: buffer) // A native read may return fewer frames than capacity.
            precondition(buffer.frameLength > 0, "Premature audio EOF")
            reread.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        }
        precondition(reread == samples, "Saved PCM differs from analyzed PCM")
        let bytes = reread.withUnsafeBufferPointer { Data(buffer: $0) }
        precondition(hash == SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        rejects { _ = try Check.writeVADFixture(samples, turnID: id, directory: directory) }
        let rereadBytes = try Data(contentsOf: file)
        precondition(rereadBytes == originalBytes)
        for invalid: [Float] in [[], [.nan], Array(repeating: 0, count: 480001)] {
            rejects { _ = try Check.writeVADFixture(invalid, turnID: UUID(), directory: directory) }
        }
        for _ in 0..<7 { _ = try Check.writeVADFixture(samples, turnID: UUID(), directory: directory) }
        rejects { _ = try Check.writeVADFixture(samples, turnID: UUID(), directory: directory) }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        precondition(files.count == 8 && files.allSatisfy { !$0.lastPathComponent.contains("partial") })
        let cancelledDirectory = root.appending(path: "cancelled")
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try Check.writeVADFixture(samples, turnID: UUID(), directory: cancelledDirectory)
                return false
            } catch is CancellationError { return true } catch { return false }
        }
        let didCancel = await cancelled.value
        precondition(didCancel && !FileManager.default.fileExists(atPath: cancelledDirectory.path))
        print("PASS: exact float PCM, no overwrite, finite bounded input, eight-file cap, cancellation")
    }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.swift"
            path.write_text(swift)
            binary = Path(directory) / "fixture"
            build = subprocess.run([SWIFTC, "-parse-as-library", str(path), "-o", str(binary)],
                                   text=True, capture_output=True, timeout=60)
            self.assertEqual(build.returncode, 0, build.stderr)
            result = subprocess.run([str(binary), directory], text=True, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("PASS: exact float PCM", result.stdout)


class SourceContractTests(unittest.TestCase):
    def test_default_selection_is_fp8_pal8_without_launch_or_build_opt_in(self):
        source = SOURCE.read_text()
        self.assertIn('return try makeV3Selection(format: "fp8", decoder: "pal8")', source)
        self.assertIn('static var enabled: Bool { true }', source)
        self.assertIn('"packed:fp8": "73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13"', source)
        self.assertNotIn('W8TinyProbe.fullManifestPins', source)

    def test_measurement_scopes_and_verified_support_label(self):
        source = SOURCE.read_text()
        self.assertIn('logMemory(stage: "asset-verification-end", model: directory.lastPathComponent)', source)
        self.assertIn('scope=replay-transcription-not-native-decoder', source)
        self.assertIn('scope=staged-transcribe-through-unload-not-ui-send', source)
        self.assertIn('decoder_prewarm=with-greeting', source)
        self.assertIn('asr_trial_final id=', source)
        self.assertIn('asr_trial_audio id=', source)

    def test_memory_warning_preserves_stop_and_reports_relaunch_instead_of_a_build_switch(self):
        source = SOURCE.read_text()
        warning = source.split('let previousState = self.asrState.rawValue', 1)[1].split('\n                    }', 1)[0]
        self.assertLess(warning.index('self.stagedMemoryWarning = true'), warning.index('self.stop()'))
        self.assertIn('self.asrError = Self.memoryWarningMessage', warning)
        self.assertIn('stage: "staged-memory-warning"', warning)
        self.assertIn('decoder_prewarm_active=', warning)
        message = source.split('private static let memoryWarningMessage = "', 1)[1].split('"', 1)[0]
        self.assertIn('close Mural from the app switcher, then reopen it.', message)
        self.assertNotIn('use the default build', message.lower())
        self.assertIn('guard !stagedMemoryWarning else {', source)
        self.assertIn('asrError ?? Self.memoryWarningMessage', source)
        self.assertEqual(source.count('stagedMemoryWarning = false'), 1)  # Initialization only.
        schedule = source.split('private func startStagedDecoderPrewarmIfNeeded()', 1)[1].split('\n    #endif', 1)[0]
        self.assertIn('stagedDecoderWarmup == nil', schedule)
        self.assertIn('stagedDecoderWarmupActive = true', schedule)
        self.assertIn('defer { self?.stagedDecoderWarmupActive = false }', schedule)
        self.assertIn('try await whisper.prewarmStagedDecoder()', schedule)

    def test_v3_fingerprint_covers_hidden_entries_without_changing_legacy_hashes(self):
        source = SOURCE.read_text()
        v3 = source.split("    private static func makeV3Selection", 1)[1].split("    @concurrent static func verifiedSelection", 1)[0]
        self.assertIn("fingerprint(artifactURL, includeHiddenFiles: true)", v3)
        helper = source.split("    static func fingerprint", 1)[1].split("\n}\n#endif", 1)[0]
        self.assertIn("includeHiddenFiles: Bool = false", helper)
        self.assertIn("includeHiddenFiles ? [] : [.skipsHiddenFiles]", helper)
        self.assertIn("fingerprint(child, includeHiddenFiles: includeHiddenFiles)", helper)
        self.assertIn("values.isSymbolicLink != true", helper)

    def test_pal8_pin_and_fp16_transport_remain_unchanged(self):
        source = SOURCE.read_text()
        self.assertIn('supportIdentity = "phowhisper-cs-pal8-g16-v1"', source)
        self.assertIn("430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336", source)
        verifier = VERIFIER.read_text()
        self.assertIn('"fp8": 40', verifier)
        self.assertIn('try requireResponse(Array(values.suffix(markerValues.count)), challenge: challenge)', verifier)
        self.assertIn('guard names == [entrypoint]', verifier)
        self.assertIn('case .float16: copy(Float16.self)', source)
        self.assertIn('let result = try MLMultiArray(shape: [1, 1280, 1, 1500], dataType: .float16)', source)

    def test_vad_uses_one_turn_local_pass_and_only_selected_pcm_reaches_asr(self):
        source = SOURCE.read_text()
        capture = source.split('    @concurrent private static func transcribe(', 1)[1].split('    private nonisolated static func convert', 1)[0]
        self.assertEqual(capture.count('whisper.analyzeSpeech('), 1)
        self.assertIn('try await whisper.transcribe(analysis.samples)', capture)
        self.assertLess(capture.index('if !analysis.rejected'), capture.index('try await decoderWarmup.value'))
        self.assertIn('seconds: Double(frames) / sampleRate', capture)
        analysis = source.split('        func analyzeSpeech(', 1)[1].split('        #if canImport(CoreAI)', 1)[0]
        self.assertEqual(source.count('vad.processStreamingChunk('), 1)
        self.assertIn('var evidence = SpeechPresencePolicy.Evidence(sampleCount: samples.count)', analysis)
        self.assertIn('var state = VadStreamState.initial()', analysis)
        prediction = analysis.index('try await vad.processStreamingChunk(')
        self.assertLess(analysis.index('try Task.checkCancellation()', prediction), analysis.index('evidence.append('))
        self.assertIn('catch is CancellationError', analysis)
        self.assertIn('throw CancellationError()', analysis)
        self.assertIn('return original', analysis.split('evidence=error', 1)[1])
        stop = source.split('    func stop() {', 1)[1].split('    nonisolated func speechSynthesizer', 1)[0]
        self.assertIn('asrTask?.cancel()', stop)
        self.assertIn('generation = UUID()', stop)

    def test_vad_only_probe_cannot_load_or_invoke_a_recognizer(self):
        source = SOURCE.read_text()
        prepare = source.split('if selected == .vadOnly {', 1)[1].split('let directory: URL', 1)[0]
        self.assertIn('try await recognizer.prepareVADOnly()', prepare)
        self.assertIn('guard self.generation == token', prepare)
        self.assertIn('return', prepare)
        vad = source.split('func prepareVADOnly()', 1)[1].split('#endif', 1)[0]
        self.assertIn('guard vadMode == .gate', vad)
        self.assertIn('MLModel(contentsOf: url, configuration: configuration)', vad)
        self.assertIn('Repo.vad.folderName', vad)
        self.assertIn('vadModel: model', vad)
        for prohibited in ['prepare(directory:', 'prewarmModels', 'loadModels', 'download(', 'ModelHub.']:
            self.assertNotIn(prohibited, vad)
        capture = source.split('    @concurrent private static func transcribe(', 1)[1].split('    private nonisolated static func convert', 1)[0]
        probe = capture.split('if await whisper.vadOnly {', 1)[1].split('#endif', 1)[0]
        self.assertIn('try Task.checkCancellation()', probe)
        self.assertIn('guard !analysis.failedOpen', probe)
        self.assertIn('return Recognition(text: ""', probe)
        self.assertIn('if let directory = try vadFixtureDirectory()', probe)
        self.assertIn('writeVADFixture(turnSamples, turnID: turnID, directory: directory)', probe)
        self.assertNotIn('writeVADFixture(analysis.samples', probe)
        retention = source.split('private nonisolated static func vadFixtureDirectory()', 1)[1].split('private nonisolated static func writeVADFixture', 1)[0]
        self.assertIn('arguments.contains("--asr-vad-only")', retention)
        self.assertIn('flags.count == 1', retention)
        self.assertIn('UUID(uuidString:', retention)
        self.assertIn('guard !flags.isEmpty else { return nil }', retention)
        self.assertLess(capture.index('if await whisper.vadOnly'), capture.index('try await decoderWarmup.value'))
        self.assertIn('guard !vadOnly else', source)
        app = (ROOT / 'App/MuralApp.swift').read_text()
        self.assertLess(app.index('if LocalTutorProbeView.vadOnlyRequested { return }'), app.index('try LearningStore('))
        view = (ROOT / 'App/RootView.swift').read_text()
        self.assertIn('#if MURAL_VAD_PROBE\n        ProcessInfo.processInfo.arguments.contains("--asr-vad-only")', view)
        self.assertIn('if Self.vadOnlyRequested { return [.vadOnly] }', view)

    def test_all_vad_callers_drain_tail_and_keep_full_pcm_for_breeze_and_firered(self):
        source = SOURCE.read_text()
        capture = source.split('    @concurrent private static func transcribe(', 1)[1].split('    private nonisolated static func convert', 1)[0]
        for actor, filename, decode in [('fireRed', 'FireRedEnglishRecognizer.swift', 'SherpaOnnxDecodeOfflineStream'),
                                         ('breeze', 'BreezeEnglishRecognizer.swift', 'kit.transcribe(audioArray: samples')]:
            self.assertIn(f'turnSamples.append(contentsOf: tail)\n            text = try await {actor}.transcribe(turnSamples)', capture)
            code = (ROOT / 'App' / filename).read_text()
            turn = code.split('func transcribe(_ samples:', 1)[1]
            self.assertIn('var state = VadStreamState.initial()', turn)
            self.assertIn('state = result.state', turn)
            self.assertIn('evidence.append(probability: result.probability, sampleCount: chunk.count)', turn)
            prediction = turn.index('try await vad.processStreamingChunk(')
            self.assertLess(turn.index('try Task.checkCancellation()', prediction), turn.index('evidence.append('))
            self.assertLess(turn.index('if rejected { return "" }'), turn.index(decode))
            self.assertIn('catch is CancellationError', turn)
            self.assertIn('action=allow_asr', turn)
            self.assertNotIn('evidence.analyze(', turn)  # No PhoWhisper trimming in these actors.
        self.assertIn('capture?.finish() // Drain every accepted packet', source)
        self.assertIn('continuation.finish(throwing: CaptureError.overloaded)', source)

    def test_empty_turn_skips_save_reply_and_both_automatic_meaning_paths(self):
        coordinator = (ROOT / 'App/ConversationCoordinator.swift').read_text()
        record = coordinator.split('    func recordLocal()', 1)[1].split('    func sendLocal()', 1)[0]
        empty = record.split('guard !text.isEmpty else {', 1)[1].split('\n                }', 1)[0]
        self.assertIn('self.localAudio.clearSubmissionTiming()', empty)
        self.assertIn('self.localPhase = .ready', empty)
        self.assertIn('return', empty)
        self.assertLess(record.index('guard !text.isEmpty'), record.index('self.appendLocal('))
        self.assertLess(record.index('guard !text.isEmpty'), record.index('self.replyLocal('))
        self.assertIn('if !self.localAudio.lastRecordingHadNoSpeech { self.scheduleTranslation() }', record)
        self.assertIn('func refreshLocalMeaning() { if isLocal, !localAudio.lastRecordingHadNoSpeech', coordinator)
        self.assertIn('try self.checkLocal(id)', record)
        view = (ROOT / 'App/RootView.swift').read_text()
        self.assertIn('if !coordinator.localResourcesBusy { coordinator.refreshLocalMeaning() }', view)
        source = SOURCE.read_text()
        publish = source.split('self.asrText = result.text', 1)[0].rsplit('await manager?.reset()', 1)[1]
        self.assertIn('try Task.checkCancellation()', publish)
        self.assertIn('guard self.generation == token else { return }', publish)
        stop = source.split('    func stop() {', 1)[1].split('    nonisolated func speechSynthesizer', 1)[0]
        self.assertNotIn('asrTask = nil', stop)  # Owner remains busy until the task defer drains.

    def test_policy_mirror_matches_runtime(self):
        source = SOURCE.read_text()
        runtime = "enum DecoderTrialPolicy {" + source.split("enum DecoderTrialPolicy {", 1)[1]
        tool = (ROOT / "Tools/CoreAI/DecoderTrialPolicy.swift").read_text()
        self.assertEqual(runtime, "enum DecoderTrialPolicy {" + tool.split("enum DecoderTrialPolicy {", 1)[1])


if __name__ == "__main__":
    unittest.main()
