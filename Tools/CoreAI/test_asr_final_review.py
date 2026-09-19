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
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "App/LocalConversationEngine.swift"
VERIFIER = ROOT / "Tools/CoreAI/W8IdentityVerifier.swift"
SWIFTC = shutil.which("swiftc")


def selection_source() -> str:
    source = SOURCE.read_text()
    selection = source.split("    enum CompressionCandidate:", 1)[1].split("    static var enabled:", 1)[0]
    enabled = source.split("    static var enabled:", 1)[1].split("    @concurrent static func verifiedURL", 1)[0]
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

    def test_policy_mirror_matches_runtime(self):
        source = SOURCE.read_text()
        runtime = "enum DecoderTrialPolicy {" + source.split("enum DecoderTrialPolicy {", 1)[1]
        tool = (ROOT / "Tools/CoreAI/DecoderTrialPolicy.swift").read_text()
        self.assertEqual(runtime, "enum DecoderTrialPolicy {" + tool.split("enum DecoderTrialPolicy {", 1)[1])


if __name__ == "__main__":
    unittest.main()
