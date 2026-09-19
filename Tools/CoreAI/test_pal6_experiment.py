#!/usr/bin/env python3
"""Host contracts only: synthetic tensors/IR, real Torch capture, no Apple/device pass."""
from __future__ import annotations

import ast
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import pal6_contract as pal
import w8_runtime_identity as v3
from prepare_pal6_trial import patched_sources, replace_once, PATHS
from compare_pal6_hidden import compare


def source_row(location="linear.weight", shape=None, dtype="f16"):
    shape = shape or [64, 64]
    row = {"location": location, "shape": shape, "dtype": dtype,
           "elements": __import__("math").prod(shape), "consumers": ["coreai.transpose"]}
    row["key"] = pal.tensor_key(row)
    return row


def audits():
    weight = source_row()
    palette = {k: v for k, v in weight.items() if k != "consumers"}
    palette["location"] = "rewritten.lut_to_dense"
    palette["key"] = pal.tensor_key(palette)
    palette.update(indices={"shape": [64, 64], "elements": 4096, "dtype": "ui6"},
                   lut={"shape": [4, 1, 64, 1], "elements": 256, "dtype": "f16"},
                   axis_operand_type="synthetic-axis-type")
    small = source_row("metadata", [1, 56])
    before = {"operations": {"coreai.constant": 2}, "constants": [weight, small], "palettes": []}
    after = {"operations": {"coreai.lut_to_dense": 1}, "constants": [small], "palettes": [palette]}
    return before, after


def reports(root: Path):
    control = {"kind": "encoder", "transport": "packed", "versions": pal.PINS,
               "compiler": "synthetic-not-Apple", "architecture": "h18p", "min_deployment": "27.0",
               "compute": "gpu", "source_weights": pal.FROZEN_WEIGHTS,
               "source_configuration": {"config.json": "synthetic"}}
    ref_recipe = {"kind": "encoder", "format": "fp8", "transport": "packed", "control": control}
    trial_recipe = {**ref_recipe, "format": "pal6", "palettization": copy.deepcopy(pal.SETTINGS),
                    "reference_manifest_sha256": pal.FP8_MANIFEST,
                    "decoder_manifest_sha256": pal.PAL8_MANIFEST, "retained_exceptions": {}}
    before, after = audits()
    reference = {"schema": pal.SCHEMA, "status": "aot-static-only", "recipe": ref_recipe,
                 "control": control, "identity": v3.identity(ref_recipe)}
    candidate = {"schema": pal.SCHEMA, "status": "aot-static-only", "recipe": trial_recipe,
                 "control": control, "identity": pal.identity(trial_recipe),
                 "audit_before": before, "audit_after": after, "coverage": pal.coverage(before, after)}
    for index, report in enumerate((reference, candidate)):
        for field in ("source", "aot"):
            directory = root / f"{index}-{field}"
            directory.mkdir()
            (directory / "function.hash").write_bytes(bytes([index + 1]) * 32)
            (directory / "weights.bin").write_bytes(f"synthetic-{index}-{field}".encode())
            report[field] = v3.bundle_record(directory)
    return reference, candidate


def integration_fixture():
    """Reviewed source anchors, NOT a complete Swift app or native build."""
    source = Path(__file__).with_name("prepare_pal6_trial.py").read_text()
    # Collect literal old anchors from the real patch generator, grouped by path.
    # Runtime tests below also assert the important new guard semantics/contents.
    tree = ast.parse(source)
    function = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "patched_sources")
    fixtures = {}; path = None
    for statement in function.body:
        if isinstance(statement, ast.Assign):
            if any(isinstance(t, ast.Name) and t.id == "path" for t in statement.targets):
                path = ast.literal_eval(statement.value)
                fixtures[path] = ""
            if isinstance(statement.value, ast.Call) and isinstance(statement.value.func, ast.Name) and statement.value.func.id == "replace_once":
                fixtures[path] += ast.literal_eval(statement.value.args[1]) + "\n"
    fixtures["App/W8TinyProbe.swift"] = (
        'static let fullManifestPins: [String: String] = [\n'
        f'"packed:fp8": "{pal.FP8_MANIFEST}",\n'
        '"packed:int8": "unchanged-test-pin",\n' + fixtures["App/W8TinyProbe.swift"] + ']\n')
    return fixtures


class IdentityTests(unittest.TestCase):
    def recipe(self):
        return {"kind": "encoder", "format": "pal6", "transport": "packed", "palettization": pal.SETTINGS}

    def test_pal6_not_fp6_or_int6(self):
        for key, value in (("format", "fp6"), ("format", "int6"), ("kind", "tiny"), ("transport", "split")):
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                pal.identity({**self.recipe(), key: value})

    def test_distinct_width_name_and_digest(self):
        spec = pal.identity(self.recipe())
        v3.validate_spec(spec)
        self.assertEqual(spec["challenge_shape"], [1, 56])
        self.assertNotEqual(spec["entrypoint"], "main")
        for fmt, width in (("fp16", 32), ("fp8", 40), ("int8", 48)):
            other = v3.identity({**self.recipe(), "format": fmt})
            self.assertEqual(other["challenge_shape"], [1, width])
            self.assertNotEqual(other["entrypoint"], spec["entrypoint"])
        changed = self.recipe(); changed["retained_exceptions"] = {"tensor": "explicit test"}
        self.assertNotEqual(pal.identity(changed), spec)

    def test_challenges_exact_and_stale_rejected(self):
        spec = pal.identity(self.recipe())
        for seed in (0, 7, 23, 31):
            nonce = pal.challenge(seed)
            self.assertEqual(nonce, v3.challenge(spec, seed))
            response = v3.expected_response(spec, nonce)
            v3.require_response(spec, nonce, response)
            with self.assertRaises(ValueError):
                v3.require_response(spec, pal.challenge((seed + 1) % 32), response)
        for seed in (-1, 32, True, 0.5):
            with self.assertRaises(ValueError): pal.challenge(seed)

    def test_same_qualified_wrapper_is_reused(self):
        self.assertIs(pal.build_wrapper, v3.build_wrapper)
        self.assertIs(pal.unpack_host, v3.unpack_host)
        self.assertIs(pal.check_contract, v3.check_contract)

    @unittest.skipUnless(importlib.util.find_spec("torch"), "Torch not installed; run in the export environment")
    def test_real_torch_capture_and_full_shape(self):
        import torch
        torch.set_num_threads(1)
        class SyntheticEncoder(torch.nn.Module):
            def forward(self, input_features):
                return input_features[:, :, :1].reshape(1, 1, 80).repeat(1, 1500, 16)
        spec = pal.identity(self.recipe())
        body = SyntheticEncoder().eval()
        wrapped = pal.build_wrapper(body, spec)
        sample = torch.zeros(1, 80, 3000, dtype=torch.float16)
        inputs = {"input_features": sample, "identity_challenge": torch.tensor([pal.challenge(0)]).half()}
        exported = torch.export.export(wrapped, args=(), kwargs=inputs)
        v3.validate_capture(exported, spec)
        for sample in (sample, torch.ones_like(sample)):
            for seed in (0, 7, 23):
                nonce = pal.challenge(seed)
                packet = exported.module()(input_features=sample, identity_challenge=torch.tensor([nonce]).half())
                torch.testing.assert_close(pal.unpack_host(packet, spec, nonce), body(sample), rtol=0, atol=0)
        with self.assertRaises(ValueError): pal.unpack_host(packet, spec, pal.challenge(2))
        with self.assertRaises(ValueError): pal.unpack_host(packet[:, :-1], spec, nonce)
        with self.assertRaises(ValueError): pal.unpack_host(packet.float(), spec, nonce)
        packet[0, 0] = float("nan")
        with self.assertRaises(ValueError): pal.unpack_host(packet, spec, nonce)

    def test_w8_trio_audit_does_not_require_pal6(self):
        with tempfile.TemporaryDirectory() as directory:
            reference, _ = reports(Path(directory))
            trio = []
            for index, fmt in enumerate(("fp16", "fp8", "int8")):
                row = copy.deepcopy(reference)
                row["recipe"]["format"] = fmt
                row["identity"] = v3.identity(row["recipe"])
                row["aot"]["native_hashes"][0]["native_bytes_hex"] = f"{index + 1:02x}" * 32
                trio.append(row)
            self.assertEqual(v3.audit_reports(trio, rehash=False)["status"], "static-trio-separated")


class CoverageTests(unittest.TestCase):
    def test_logical_bytes_not_memory(self):
        result = pal.coverage(*audits())
        self.assertEqual(result["compressed_elements"], 4096)
        self.assertEqual(result["source_precision_bytes_represented"], 8192)
        self.assertEqual(result["logical_index_bytes"], 3072)
        self.assertEqual(result["logical_lut_bytes"], 512)
        self.assertIn("not serialized/AOT", result["byte_scope"])
        self.assertEqual(len(result["below_threshold"]), 1)

    def test_small_vectors_are_reported_without_blocking_compression(self):
        before, after = audits(); vector = source_row("layer_norm", [1280])
        before["constants"].append(vector); after["constants"].append(vector)
        result = pal.coverage(before, after)
        self.assertEqual(len(result["retained"]), 1)
        self.assertIn("Small rank-1", result["retained"][0]["reason"])

    def test_unexplained_skip_rejected(self):
        before, after = audits()
        before["constants"].append(source_row("second"))
        after["constants"].append(source_row("second"))
        with self.assertRaises(ValueError): pal.coverage(before, after)

    def test_explicit_retained_reason_and_stale_exception(self):
        before, after = audits()
        retained = source_row("incompatible-group", [3, 1280])
        retained["consumers"] = ["coreai.decomposable.broadcasting_add"]
        retained["key"] = pal.tensor_key(retained)
        before["constants"].append(retained); after["constants"].append(retained)
        result = pal.coverage(before, after, {retained["key"]: "Reviewed unsupported grouped-channel layout; kept FP16"})
        self.assertEqual(len(result["retained"]), 1)
        with self.assertRaises(ValueError): pal.coverage(*audits(), {retained["key"]: "Stale exception must not pass"})

    def test_disappeared_tensor_rejected(self):
        before, after = audits(); before["constants"].append(source_row("missing"))
        with self.assertRaises(ValueError): pal.coverage(before, after)

    def test_duplicate_source_locations_rejected(self):
        before, after = audits(); before["constants"].append(before["constants"][0])
        with self.assertRaises(ValueError): pal.coverage(before, after)

    def test_wrong_index_lut_group_or_vector_contract(self):
        for section, field, value in (("indices", "dtype", "ui8"), ("indices", "elements", 4095),
                                      ("lut", "dtype", "f32"), ("lut", "shape", [4, 32, 2]),
                                      ("lut", "elements", 128)):
            before, after = audits(); after["palettes"][0][section][field] = value
            with self.subTest(section=section, field=field), self.assertRaises(ValueError):
                pal.coverage(before, after)

    def test_unknown_or_duplicate_palettes_rejected(self):
        for changed in ("duplicate", "unknown"):
            before, after = audits()
            if changed == "duplicate": after["palettes"].append(after["palettes"][0])
            else: after["palettes"][0]["key"] = "unknown"
            with self.assertRaises(ValueError): pal.coverage(before, after)

    def test_dense_duplicate_and_joint_quantization_rejected(self):
        before, after = audits(); after["constants"].append(before["constants"][0])
        with self.assertRaises(ValueError): pal.coverage(before, after)
        before, after = audits(); after["operations"]["coreai.blockwise_shift_scale"] = 1
        with self.assertRaises(ValueError): pal.coverage(before, after)
        before, after = audits(); before["operations"]["coreai.blockwise_shift_scale"] = 1
        with self.assertRaises(ValueError): pal.coverage(before, after)


class PairTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.reference, self.candidate = reports(Path(self.directory.name))

    def test_real_file_rehash_and_static_pair(self):
        pal.validate_pair(self.reference, self.candidate)

    def test_changed_source_and_aot_bytes_rejected(self):
        for field in ("source", "aot"):
            path = Path(self.candidate[field]["path"]) / "weights.bin"
            original = path.read_bytes(); path.write_bytes(b"changed")
            with self.assertRaises(ValueError): pal.validate_pair(self.reference, self.candidate)
            path.write_bytes(original)

    def test_source_and_aot_collisions_rejected(self):
        for field in ("source", "aot"):
            candidate = copy.deepcopy(self.candidate)
            candidate[field] = self.reference[field]
            with self.assertRaises(ValueError): pal.validate_pair(self.reference, candidate)

    def test_control_drift_rejected_even_with_new_valid_identity(self):
        for field in pal.CONTROL_FIELDS:
            candidate = copy.deepcopy(self.candidate)
            candidate["control"][field] = "different"
            candidate["identity"] = pal.identity(candidate["recipe"])
            with self.subTest(field=field), self.assertRaises(ValueError):
                pal.validate_pair(self.reference, candidate)

    def test_false_coverage_and_changed_recipe_rejected(self):
        for mutation in ("coverage", "decoder", "failed", "identity"):
            candidate = copy.deepcopy(self.candidate)
            if mutation == "coverage": candidate["coverage"]["compressed_elements"] += 1
            elif mutation == "decoder": candidate["recipe"]["decoder_manifest_sha256"] = "changed"
            elif mutation == "failed": candidate["status"] = "failed"
            else: candidate["identity"]["entrypoint"] = "main"
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                pal.validate_pair(self.reference, candidate)

    def test_manifest_and_symlink_rejection(self):
        path = Path(self.directory.name) / "manifest.json"
        path.write_text('{}')
        self.assertEqual(pal.read_pinned(path, pal.sha256(path)), {})
        with self.assertRaises(ValueError): pal.read_pinned(path, pal.FP8_MANIFEST)
        link = path.with_name('link'); link.symlink_to(path)
        with self.assertRaises(ValueError): pal.sha256(link)


class IntegrationTests(unittest.TestCase):
    def test_preserve_champion_and_add_only_real_candidate_pin(self):
        before = integration_fixture(); after = patched_sources(before, "a" * 64)
        self.assertEqual(set(after), set(PATHS))
        self.assertIn(f'"packed:fp8": "{pal.FP8_MANIFEST}"', after["App/W8TinyProbe.swift"])
        self.assertIn('"packed:int8": "unchanged-test-pin"', after["App/W8TinyProbe.swift"])
        self.assertIn('"packed:pal6": "' + "a" * 64, after["App/W8TinyProbe.swift"])
        self.assertNotIn('"packed:pal6"', before["App/W8TinyProbe.swift"])

    def test_paired_decoder_and_sequential_owner_guards(self):
        after = patched_sources(integration_fixture(), "b" * 64)
        self.assertIn('guard format != "pal6" || decoder == "pal8"', after["App/LocalConversationEngine.swift"])
        self.assertIn('v3.format != "pal6" || ["staged-gpu", "staged-gpu-encode"].contains(mode)', after["App/MuralApp.swift"])
        self.assertIn('selection.v3?.format != "pal6"', after["App/MuralApp.swift"])

    def test_native_and_full_timing_scopes_are_separate(self):
        after = patched_sources(integration_fixture(), "b" * 64)["App/MuralApp.swift"]
        self.assertIn('"nativeSeconds": nativeSeconds', after)
        self.assertIn('"validationCopySeconds"', after)
        self.assertIn('"staged-asr-full-complete"', after)
        self.assertIn('not-UI-send', after)
        self.assertIn('report.turns.append(turn)', after)

    def test_swift_packet_limit_matches_new_width(self):
        after = patched_sources(integration_fixture(), "b" * 64)["Tools/CoreAI/W8IdentityVerifier.swift"]
        self.assertIn('"pal6": 56', after)
        self.assertEqual(after.count("1_920_056"), 2)
        self.assertNotIn("1_920_048", after)

    def test_source_drift_duplicate_anchor_and_existing_pal6_fail_closed(self):
        with self.assertRaises(ValueError): replace_once("aa", "a", "b")
        with self.assertRaises(ValueError): replace_once("a", "b", "c")
        sources = integration_fixture(); sources["App/W8TinyProbe.swift"] += '\n"packed:pal6": "old"'
        with self.assertRaises(ValueError): patched_sources(sources, "a" * 64)
        with self.assertRaises(ValueError): patched_sources(integration_fixture(), "not-a-pin")
        with self.assertRaises(ValueError): patched_sources(integration_fixture(), pal.FP8_MANIFEST)


@unittest.skipUnless(importlib.util.find_spec("numpy"), "NumPy not installed; use export environment")
class HiddenComparisonTests(unittest.TestCase):
    def setUp(self):
        import numpy as np
        self.directory = tempfile.TemporaryDirectory(); self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.values = np.ones(1_920_000, dtype="<f2")

    def descriptor(self, name, *, mel="c" * 64, artifact="d" * 64, values=None):
        tensor = self.root / (name + '.fp16')
        (self.values if values is None else values).tofile(tensor)
        data = {"path": tensor.name, "sha256": pal.sha256(tensor), "mel_sha256": mel,
                "artifact_fingerprint": artifact, "shape": [1, 1500, 1280], "dtype": "float16-le"}
        path = self.root / (name + '.json'); path.write_text(json.dumps(data)); return path

    def test_exact_repeat_and_diagnostic_not_quality_pass(self):
        reference = self.descriptor('ref'); candidate = self.descriptor('trial'); repeat = self.descriptor('repeat')
        result = compare(reference, candidate, repeat)
        self.assertEqual(result["max_abs_error"], 0)
        self.assertEqual(result["cosine_similarity"], 1)
        self.assertTrue(result["repeatability"]["bit_exact"])
        self.assertIn('not-speech', result["status"])

    def test_mel_and_repeat_identity_mismatch_rejected(self):
        reference = self.descriptor('ref'); candidate = self.descriptor('trial', mel='a' * 64)
        with self.assertRaises(ValueError): compare(reference, candidate)
        candidate = self.descriptor('trial2'); repeat = self.descriptor('repeat', artifact='a' * 64)
        with self.assertRaises(ValueError): compare(reference, candidate, repeat)

    def test_numerical_delta_and_zero_norm(self):
        import numpy as np
        reference = self.descriptor('ref'); candidate = self.descriptor('trial', values=self.values * 2)
        result = compare(reference, candidate)
        self.assertEqual(result["max_abs_error"], 1)
        self.assertEqual(result["mean_abs_error"], 1)
        zero = self.descriptor('zero', values=np.zeros_like(self.values))
        self.assertIsNone(compare(reference, zero)["cosine_similarity"])

    def test_nonfinite_and_truncated_output_rejected(self):
        values = self.values.copy(); values[0] = float('nan')
        reference = self.descriptor('ref'); candidate = self.descriptor('bad', values=values)
        with self.assertRaises(ValueError): compare(reference, candidate)
        candidate = self.descriptor('short', values=self.values[:100])
        with self.assertRaises(ValueError): compare(reference, candidate)


if __name__ == '__main__':
    unittest.main()
