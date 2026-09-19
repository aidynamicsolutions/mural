#!/usr/bin/env python3
"""Host-only tests. No Core AI/Xcode/iPhone or performance claim."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import tempfile
import unittest

from w8_identity import (BLOCKED_V1_HASH, SCHEMA, bundle_record, canonical,
                         check_marker, fingerprint, identity, native_hashes, verify_pair)


class IdentityTests(unittest.TestCase):
    def test_recipe_determinism_and_configuration_binding(self):
        a = {"kind": "encoder", "format": "fp8", "scale": None}
        b = {"scale": None, "format": "fp8", "kind": "encoder"}
        self.assertEqual(identity(a), identity(b))
        self.assertNotEqual(identity(a), identity(dict(a, scale="changed")))
        with self.assertRaises(ValueError):
            canonical({"value": float("nan")})

    def test_distinct_abi_and_signed_markers(self):
        specs = [identity({"kind": "tiny", "format": p}) for p in ("fp16", "fp8", "int8")]
        self.assertEqual(len({s["entrypoint"] for s in specs}), 3)
        self.assertEqual([s["marker_shape"] for s in specs], [[16], [8], [9]])
        for spec in specs:
            self.assertTrue(all(-(2**31) <= v < 2**31 for v in spec["marker_values"]))
            check_marker(spec, spec["entrypoint"], spec["marker_values"])
            with self.assertRaises(ValueError):
                check_marker(spec, "main", spec["marker_values"])
            with self.assertRaises(ValueError):
                check_marker(spec, spec["entrypoint"], [0] * len(spec["marker_values"]))
            with self.assertRaises(ValueError):
                check_marker(spec, spec["entrypoint"], spec["marker_values"][:-1])
            with self.assertRaises(ValueError):
                check_marker(spec, spec["entrypoint"], [float(v) for v in spec["marker_values"]])

    def make_report(self, root, precision, key):
        control = {"source": "same", "compiler": "test-only"}
        recipe = {"kind": "tiny", "format": precision, "control": control}
        bundle = root / (precision + ".aimodelc")
        bundle.mkdir()
        (bundle / "main.hash").write_bytes(key)
        (bundle / "weights").write_bytes(precision.encode())
        return {"schema": SCHEMA, "status": "aot-static-only", "recipe": recipe,
                "control": control,
                "identity": identity(recipe), "aot": bundle_record(bundle)}

    def test_separate_pair_then_artifact_mutation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            a = self.make_report(root, "fp8", b"a" * 64)
            b = self.make_report(root, "int8", b"b" * 64)
            result = verify_pair([a, b])
            self.assertEqual(result["status"], "static-separation-only")
            self.assertEqual(result["device_cache_isolation"], "NOT TESTED")
            (Path(a["aot"]["path"]) / "weights").write_text("changed")
            with self.assertRaisesRegex(ValueError, "changed"):
                verify_pair([a, b])

    def test_observed_v1_collision_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            a = self.make_report(root, "fp8", b"c" * 64)
            b = self.make_report(root, "int8", b"c" * 64)
            with self.assertRaisesRegex(ValueError, "collision"):
                verify_pair([a, b])
            # This tests the literal native representation, not an assertion
            # about how the historical report computed its identifier.
            (Path(a["aot"]["path"]) / "main.hash").write_text(BLOCKED_V1_HASH)
            a["aot"] = bundle_record(Path(a["aot"]["path"]))
            with self.assertRaisesRegex(ValueError, "v1"):
                verify_pair([a, b])

    def test_metadata_forgery_and_control_mismatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            a = self.make_report(root, "fp8", b"a" * 64)
            b = self.make_report(root, "int8", b"b" * 64)
            forged = copy.deepcopy(a)
            forged["recipe"]["format"] = "fp16"
            with self.assertRaisesRegex(ValueError, "Recipe"):
                verify_pair([forged, b])
            altered = copy.deepcopy(b)
            altered["control"] = dict(altered["control"], compiler="different")
            with self.assertRaisesRegex(ValueError, "control"):
                verify_pair([a, altered])
            with self.assertRaises(ValueError):
                verify_pair([a])
            with self.assertRaises(ValueError):
                verify_pair([a, a])

    def test_hash_formats_and_hidden_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "main.hash"
            path.write_bytes(bytes.fromhex("de" * 32))
            a = native_hashes(root)[0]
            path.write_text("DE" * 32 + "\n")
            b = native_hashes(root)[0]
            self.assertEqual(a["native_bytes_hex"], b["native_bytes_hex"])
            self.assertNotEqual(a["file_sha256"], b["file_sha256"])
            before = fingerprint(root)
            (root / ".hidden").write_text("also covered")
            self.assertNotEqual(before, fingerprint(root))
            (root / "alias").symlink_to(path)
            with self.assertRaises(ValueError):
                fingerprint(root)

    def test_ambiguous_or_missing_hash_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaises(ValueError):
                native_hashes(root)
            (root / "a.hash").write_bytes(b"a")
            (root / "b.hash").write_bytes(b"b")
            with self.assertRaises(ValueError):
                native_hashes(root)

    def test_compiler_contract(self):
        from rebuild_w8_identity import check_contract
        spec = identity({"kind": "tiny", "format": "fp8"})
        summary = {"summary": {"functions": [{"name": spec["entrypoint"],
            "inputs": [{"name": "input_features", "type": "NDArray (Float16, 1 × 64)"}],
            "outputs": [{"name": "encoder_hidden_states", "type": "NDArray (Float16, 1 × 64)"},
                        {"name": spec["marker_output"], "type": "NDArray (Int32, 8)"}]}]}}
        check_contract(summary, spec, "tiny")
        summary["summary"]["functions"][0]["outputs"].pop()
        with self.assertRaises(ValueError):
            check_contract(summary, spec, "tiny")


class TorchWrapperTests(unittest.TestCase):
    def test_wrapper_and_export_preserve_hidden_output(self):
        try:
            import torch
        except ImportError:
            self.skipTest("Torch absent; static tests still run")
        from rebuild_w8_identity import build_tiny, build_wrapper
        native_reference_outputs = []
        for precision in ("fp16", "fp8", "int8"):
            spec = identity({"kind": "tiny", "format": precision})
            module, vectors = build_tiny(precision)
            wrapper = build_wrapper(module, spec)
            exported = torch.export.export(wrapper, args=(), kwargs={"input_features": vectors[0]},
                                           dynamic_shapes={"input_features": {}})
            for vector in vectors:
                with torch.inference_mode():
                    hidden, marker = exported.module()(input_features=vector)
                    torch.testing.assert_close(hidden, module(vector), rtol=0, atol=0)
                    check_marker(spec, spec["entrypoint"], marker.tolist())
            native_reference_outputs.append(module(vectors[1]).detach().float())
        for a, b in zip(native_reference_outputs, native_reference_outputs[1:]):
            self.assertGreater((a - b).abs().min().item(), 1.0)
        # No quantization/compiler/native execution occurred in this host check.


if __name__ == "__main__":
    unittest.main()
