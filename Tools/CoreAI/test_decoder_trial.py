#!/usr/bin/env python3
"""Portable synthetic contract tests, not Apple conversion or device evidence."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

import analyze_asr_trial as analyze
import decoder_trial_patch as patcher
import prepare_pal6_decoder_trial as assets


def write_support(root, *, decoder=b"decoder", mel=b"mel", extra=False):
    root.mkdir()
    data = {"TextDecoder.mlmodelc/weights/weight.bin": decoder,
            "TextDecoder.mlmodelc/model.mil": b"synthetic compiled description",
            "AudioEncoder.mlmodelc/weights/weight.bin": b"unused",
            "MelSpectrogram.mlmodelc/model.mil": mel,
            "generation_config.json": b'{"suppress_tokens":[]}',
            "tokenizer.json": b'{}'}
    files = {}
    for name, value in data.items():
        p = root / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(value)
        files[name] = {"bytes": len(value), "sha256": hashlib.sha256(value).hexdigest()}
    (root / "manifest.json").write_text(json.dumps({"files": files}))
    if extra:
        (root / "cache-extra.bin").write_bytes(b"do not delete")
    return assets.sha(root / "manifest.json")


def synthetic_run(root, label, *, candidate=False):
    root.mkdir()
    turns, preps, events = [], [], []
    for i, name in enumerate(analyze.EXPECTED, 1):
        turns.append({"turn": i, "file": name, "sampleCount": 16000,
            "audioSHA256": name + "-synthetic-audio", "rawTranscript": "Synthetic test only.",
            "normalizedTranscript": "synthetic test only", "detectedLanguages": ["vi"],
            "generatedTokens": [[1, 2, 3]], "segmentTokens": [[1, 2, 3]],
            "melSHA256": [name + "-mel"], "encoderHiddenSHA256": [name + "-hidden"],
            "thermalBefore": 0, "thermalAfter": 0, "termination": "endToken", "error": None,
            "timings": {"totalSeconds": 0.8 if candidate else 1.0, "decoderSeconds": 0.7 if candidate else 0.9,
                        "decodingPredictionsSeconds": 0.6, "decodingLoopSeconds": 0.7}})
        preps.append({"index": i, "whisperKitPrewarmSeconds": 0.1, "whisperKitLoadSeconds": 0.2})
        base = {"runID": label, "sessionID": label, "turn": i, "memory": {
            "footprintBytes": 900 if candidate else 1000, "processRSSPeakBytes": 1500}, "thermalState": 0}
        stages = [
            ("encoder-load-complete", {"cacheHit": True, "cacheLookupSeconds": 0.01,
                                       "specializationSeconds": 0, "functionLoadSeconds": 0.03}),
            ("encoder-response-verified", {"nativeSeconds": 0.5, "validationCopySeconds": 0.01}),
            ("encoder-run-end", {}),
            ("whisperkit-load-complete", {"phase": "models"}),
            ("decoder-run-end", {"phase": "text"}),
            ("staged-asr-full-complete", {"file": name, "seconds": 1.8 if candidate else 2.0,
                "scope": "after-audio-read-through-encoder-prepare-decoder-not-UI-send"}),
        ]
        for j, (stage, fields) in enumerate(stages):
            events.append({**base, "uptime": i * 10 + j, "stage": stage, **fields})
    report = {"runID": label, "mode": "staged-gpu", "status": "complete", "errors": [],
              "cancellation": None, "corpusRequested": True, "turns": turns, "preparations": preps,
              "architecture": "h18p", "tokenizer": "PhoWhisperTokenizer", "melBoundary": "same",
              "decodingOptions": {"task": "transcribe"}, "lifecycle": "recreate",
              "modelPrecision": "v3 packed fp8 encoder, FP16 handoff",
              "encoderArtifactSHA256": "a" * 64, "expectedEncoderArtifactSHA256": "a" * 64,
              "supportManifestSHA256": assets.CANDIDATE_PIN if candidate else assets.REFERENCE_PIN}
    (root / "report.json").write_text(json.dumps({"runID": label, "productGate": report, "memoryWarnings": 0}))
    (root / "events.jsonl").write_text("".join(json.dumps(e) + "\n" for e in events))
    context = {"source_commit": "b" * 40, "app_executable_sha256": "c" * 64, "device_model": "synthetic",
               "os_build": "synthetic", "cache_condition": "retained-cache-new-process", "measurement_protocol": "synthetic-v1",
               "prewarm_policy": "always", "process_session_id": label,
               "launch_arguments": ["--coreai-product-mode=staged-gpu", "--coreai-product-corpus",
                   "--coreai-w8-v3-encoder=fp8", "--coreai-w8-v3-decoder=" + ("pal6" if candidate else "pal8")]}
    (root / "trial-context.json").write_text(json.dumps(context))


class SupportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.a = self.root / "a"; self.b = self.root / "b"
        self.pa = write_support(self.a)
        self.pb = write_support(self.b, decoder=b"six", extra=True)

    def test_decoder_only_admission(self):
        result = assets.compare_supports(assets.inspect_support(self.a, self.pa), assets.inspect_support(self.b, self.pb))
        self.assertEqual(result["changed_components"], ["TextDecoder.mlmodelc"])
        self.assertEqual(result["runtime_memory_or_latency_improvement"], "NOT MEASURED")

    def test_wrong_pin_rejected(self):
        with self.assertRaises(ValueError): assets.inspect_support(self.a, "0" * 64)

    def test_changed_weight_rejected(self):
        (self.a / "TextDecoder.mlmodelc/weights/weight.bin").write_bytes(b"corrupt")
        with self.assertRaises(ValueError): assets.inspect_support(self.a, self.pa)

    def test_common_file_change_rejected(self):
        a = assets.inspect_support(self.a, self.pa); b = assets.inspect_support(self.b, self.pb)
        b["files"]["tokenizer.json"]["sha256"] = "0" * 64
        with self.assertRaises(ValueError): assets.compare_supports(a, b)

    def test_identical_decoder_rejected(self):
        a = assets.inspect_support(self.a, self.pa)
        with self.assertRaises(ValueError): assets.compare_supports(a, a)

    def test_unsafe_paths_rejected(self):
        for name in ("../outside", "/absolute", "x/../tokenizer.json", "./tokenizer.json", "x//y", "x\\y"):
            with self.subTest(name=name), self.assertRaises(ValueError): assets.safe_file(self.a, name)

    def test_symlink_rejected(self):
        (self.a / "link").symlink_to(self.b)
        with self.assertRaises(ValueError): assets.inspect_support(self.a, self.pa)

    def test_stage_is_exclusive_and_leaves_caches(self):
        b = assets.inspect_support(self.b, self.pb)
        destination = self.root / "new"
        assets.stage_support(b, destination)
        self.assertTrue((self.b / "cache-extra.bin").exists())
        self.assertFalse((destination / "cache-extra.bin").exists())
        self.assertEqual(assets.sha(destination / "manifest.json"), self.pb)
        with self.assertRaises(FileExistsError): assets.stage_support(b, destination)

    def test_duplicate_json_rejected(self):
        p = self.root / "bad.json"; p.write_text('{"a":1,"a":2}')
        with self.assertRaises(ValueError): assets.read_json(p)


class AnalysisTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.a = self.root / "a"; self.b = self.root / "b"
        synthetic_run(self.a, "ref"); synthetic_run(self.b, "cand", candidate=True)

    def test_matched_corpus_keeps_scopes_separate(self):
        result = analyze.compare(analyze.load_run(self.a), analyze.load_run(self.b), "decoder")
        self.assertEqual(result["normalized_agreement_out_of_21_not_accuracy"], 21)
        self.assertAlmostEqual(result["scored_mean_change_percent"]["staged_full_seconds"], -10)
        self.assertAlmostEqual(result["scored_mean_change_percent"]["replay_pipeline_seconds_not_send"], -20)
        self.assertEqual(result["reference"]["scored"]["staged_full_seconds"]["count"], 21)
        self.assertEqual(result["reference"]["warm_scored"]["staged_full_seconds"]["count"], 20)
        self.assertEqual(result["process_lifetime_rss_peak_bytes"], {"reference": 1500, "candidate": 1500})

    def test_missing_warning_evidence_rejected(self):
        p = self.a / "report.json"; obj = assets.read_json(p); del obj["memoryWarnings"]; p.write_text(json.dumps(obj))
        with self.assertRaises(ValueError): analyze.load_run(self.a)

    def test_warning_or_failure_rejected(self):
        p = self.a / "report.json"; obj = assets.read_json(p); obj["memoryWarnings"] = 1; p.write_text(json.dumps(obj))
        with self.assertRaises(ValueError): analyze.load_run(self.a)

    def test_missing_full_scope_not_reconstructed(self):
        p = self.a / "events.jsonl"; p.write_text("\n".join(x for x in p.read_text().splitlines() if "staged-asr-full-complete" not in x))
        with self.assertRaises(ValueError): analyze.load_run(self.a)

    def test_missing_native_time_rejected(self):
        p = self.a / "events.jsonl"; p.write_text(p.read_text().replace('"nativeSeconds": 0.5', '"oldNative": 0.5'))
        with self.assertRaises(ValueError): analyze.load_run(self.a)

    def test_changed_encoder_hidden_rejected_for_decoder(self):
        a = analyze.load_run(self.a); b = analyze.load_run(self.b)
        b["report"]["turns"][3]["encoderHiddenSHA256"] = ["different"]
        with self.assertRaises(ValueError): analyze.compare(a, b, "decoder")

    def test_unmatched_cache_conditions_rejected(self):
        a = analyze.load_run(self.a); b = analyze.load_run(self.b)
        b["context"]["cache_condition"] = "fresh"
        with self.assertRaises(ValueError): analyze.compare(a, b, "decoder")

    def test_mixed_prewarm_and_precision_rejected(self):
        a = analyze.load_run(self.a); b = analyze.load_run(self.b)
        b["context"]["prewarm_policy"] = "once"
        with self.assertRaises(ValueError): analyze.compare(a, b, "decoder")

    def test_raw_diagnostic_difference_is_retained_separately(self):
        a = analyze.load_run(self.a); b = analyze.load_run(self.b)
        b["report"]["turns"][16]["rawTranscript"] = "Diagnostic changed."
        result = analyze.compare(a, b, "decoder")
        self.assertEqual(result["normalized_agreement_out_of_21_not_accuracy"], 21)
        self.assertFalse(result["all_raw_token_language_differences"][0]["scored"])

    def test_diagnostic_token_limit_does_not_become_scored_gate(self):
        p = self.b / "report.json"; obj = assets.read_json(p)
        obj["productGate"]["turns"][16]["termination"] = "tokenLimit"
        p.write_text(json.dumps(obj))
        result = analyze.compare(analyze.load_run(self.a), analyze.load_run(self.b), "decoder")
        self.assertEqual(result["normalized_agreement_out_of_21_not_accuracy"], 21)
        self.assertEqual(result["candidate"]["diagnostic_017"]["termination"], "tokenLimit")

    def test_scored_token_limit_is_not_successful_benchmark(self):
        p = self.b / "report.json"; obj = assets.read_json(p)
        obj["productGate"]["turns"][0]["termination"] = "tokenLimit"
        p.write_text(json.dumps(obj))
        with self.assertRaises(ValueError): analyze.load_run(self.b)

    def test_missing_corpus_row_rejected(self):
        p = self.a / "report.json"; obj = assets.read_json(p); obj["productGate"]["turns"].pop(); p.write_text(json.dumps(obj))
        with self.assertRaises(ValueError): analyze.load_run(self.a)

    def test_duplicate_session_rejected(self):
        a = analyze.load_run(self.a); b = analyze.load_run(self.b)
        b["context"]["process_session_id"] = a["context"]["process_session_id"]
        with self.assertRaises(ValueError): analyze.compare(a, b, "decoder")

    def test_nonfinite_and_zero_memory_are_not_savings(self):
        for value in (float("nan"), float("inf"), -1, True, 0):
            with self.subTest(value=value), self.assertRaises(ValueError): analyze.number(value, "memory", positive=True)


class LiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "log.txt"
        self.token = "11111111-1111-1111-1111-111111111111"

    def log(self, capture=100, send=105, end=107):
        text = (f"asr_trial_capture id={self.token} uptime={capture}\n"
                f"asr_trial_send id={self.token} uptime={send}\n"
                f"asr_trial_final id={self.token} uptime={end} send_to_final_seconds=2 captured_seconds={send-capture}\n")
        self.path.write_text(text)

    def test_instruction_pause_not_added_to_send_time(self):
        self.log(); first = analyze.live_metrics(self.path)
        self.log(capture=100, send=110, end=112); second = analyze.live_metrics(self.path)
        self.assertEqual(first["turns"][0]["send_to_final_seconds"], second["turns"][0]["send_to_final_seconds"])
        self.assertEqual(second["turns"][0]["capture_to_send_seconds"], 10)

    def test_browser_receipt_timestamp_ignored(self):
        self.log()
        self.path.write_text("browser feedback received uptime=5000\n" + self.path.read_text())
        self.assertEqual(analyze.live_metrics(self.path)["turns"][0]["send_to_final_seconds"], 2)

    def test_bad_timer_rejected(self):
        self.log(end=111)
        with self.assertRaises(ValueError): analyze.live_metrics(self.path)

    def test_incomplete_and_warning_not_passed(self):
        self.path.write_text(f"asr_trial_capture id={self.token} uptime=1\nasr_staged_memory_warning stopped=true\n")
        result = analyze.live_metrics(self.path)
        self.assertFalse(result["timing_sample_valid"])
        self.assertTrue(result["incomplete_or_failed_turns"])

    def test_duplicate_capture_rejected(self):
        self.log(); self.path.write_text(self.path.read_text() * 2)
        with self.assertRaises(ValueError): analyze.live_metrics(self.path)


class PatchPolicyTests(unittest.TestCase):
    def test_unique_anchor_refuses_drift_and_duplicates(self):
        for text in ("gone", "old old"):
            with self.assertRaises(ValueError): patcher.once(text, "old", "new")
        self.assertEqual(patcher.once("old rest", "old", "new"), "new rest")

    def test_probe_patch_preserves_other_guards(self):
        original = ('            if let v3 = selection.v3 {\n                guard v3.format != "pal6" || ["staged-gpu"].contains(mode) else {}\n}\n'
                    '        let prewarmTask = Task { try await kit.prewarmModels() }\n        try await prewarmTask.value\n'
                    'if compressed == nil, selection.v3?.format != "pal6", config.mode.hasPrefix("staged"), file.lastPathComponent == "001.wav", !Self.productRecoveryMatches(turn) {\n}\n'
                    'await kit.loadModels()\nawait kit.unloadModels()\ntry await productRequireNoWarnings()\n')
        result = patcher.patch_probe(original)
        self.assertIn('index > 1', result)
        self.assertIn('guard v3.format != "pal6" ||', result)
        self.assertIn('await kit.loadModels()', result)
        self.assertIn('await kit.unloadModels()', result)
        self.assertIn('try await productRequireNoWarnings()', result)
        with self.assertRaises(ValueError): patcher.patch_probe(result)

    def test_product_test_patch_includes_portable_helper(self):
        result = patcher.patch_product_test("swift = " + "'" * 3 + "import Foundation\n")
        self.assertIn("DecoderTrialPolicy.swift", result)

    def test_real_swift_policy(self):
        policy = Path(__file__).with_name("DecoderTrialPolicy.swift")
        with tempfile.TemporaryDirectory() as directory:
            main = Path(directory) / "main.swift"
            main.write_text(r'''
import Foundation
func reject(_ args: [String]) { do { _ = try DecoderTrialPolicy.once(args); fatalError("Expected rejection") } catch {} }
let valid = ["--coreai-w8-v3-encoder=fp8", "--coreai-w8-v3-decoder=pal8"]
precondition(try DecoderTrialPolicy.once([]) == false)
precondition(try DecoderTrialPolicy.once(valid) == false)
precondition(try DecoderTrialPolicy.once(valid + ["--coreai-w8-v3-prewarm=once"]) == true)
precondition(try DecoderTrialPolicy.once(valid + ["--coreai-w8-v3-prewarm=always"]) == false)
precondition(try DecoderTrialPolicy.once(valid + ["--coreai-w8-v3-prewarm=once", "--coreai-product-mode=staged-gpu", "--coreai-product-corpus"]) == true)
for bad in ["", "off", "auto", "ONCE"] { reject(valid + ["--coreai-w8-v3-prewarm=" + bad]) }
reject(valid + ["--coreai-w8-v3-prewarm"])
reject(valid + ["--coreai-w8-v3-prewarm=once", "--coreai-w8-v3-prewarm=once"])
reject(["--coreai-w8-v3-prewarm=once"])
for mode in ["hybrid", "staged", "encoder-only", "staged-gpu-encode"] {
    reject(valid + ["--coreai-w8-v3-prewarm=once", "--coreai-product-mode=" + mode])
}
for encoder in ["pal6", "fp16", "int8", "unknown"] {
    reject(["--coreai-w8-v3-encoder=" + encoder, "--coreai-w8-v3-decoder=pal8", "--coreai-w8-v3-prewarm=once"])
}
reject(valid + ["--coreai-w8-v3-encoder=fp8", "--coreai-w8-v3-prewarm=once"])
reject(valid + ["--coreai-w8-v3-decoder=pal6", "--coreai-w8-v3-prewarm=once"])
print("PASS: real Swift decoder policy default/once/rejection behavior")
'''.replace('precondition(try ', 'precondition(try! '))
            binary = Path(directory) / "test-policy"
            subprocess.run(["swiftc", str(policy), str(main), "-o", str(binary)], check=True, timeout=40)
            subprocess.run([str(binary)], check=True, timeout=10)


if __name__ == "__main__":
    unittest.main()
