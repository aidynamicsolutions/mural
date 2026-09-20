import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from evaluate import read_json
from prepare_breeze import BUNDLES, BUNDLE_FILES, REQUIRED_CONFIG, SUPPORT, package
from install_breeze_probe import CHANGES, git_blob, transform
from run_reference import generation_options


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"; self.source.mkdir()
        self.compiled = self.root / "compiled"; self.compiled.mkdir()
        self.output = self.root / "candidate"
        for name in SUPPORT:
            (self.source / name).write_text("{}")
        (self.source / "config.json").write_text(json.dumps(REQUIRED_CONFIG))
        (self.source / "preprocessor_config.json").write_text(json.dumps({"sampling_rate": 16000, "feature_size": 80, "chunk_length": 30}))
        (self.source / "generation_config.json").write_text(json.dumps({"suppress_tokens": [1, 50358], "lang_to_id": {"<|zh|>": 50260, "<|en|>": 50259}}))
        (self.source / "model.safetensors").write_bytes(b"mock-weights-not-a-model")
        for name in BUNDLES:
            for relative in BUNDLE_FILES:
                path = self.compiled / f"{name}.mlmodelc" / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"mock-coreml-not-a-model")

    def run_package(self):
        return package(self.source, self.compiled, "a" * 40, self.output)

    def test_inventory_and_independent_digest(self):
        digest = self.run_package()
        data = (self.output / "manifest.json").read_bytes()
        self.assertEqual(digest, hashlib.sha256(data).hexdigest())
        manifest = json.loads(data)
        self.assertIn("TextDecoder.mlmodelc/weights/weight.bin", manifest["files"])
        self.assertEqual(manifest["qualification"], "unqualified-phone-candidate")
        self.assertFalse((self.output / "model.safetensors").exists())

    def test_existing_output_is_preserved(self):
        self.run_package()
        with self.assertRaises(FileExistsError):
            self.run_package()

    def test_wrong_topology_rejected(self):
        config = dict(REQUIRED_CONFIG, num_mel_bins=128)
        (self.source / "config.json").write_text(json.dumps(config))
        with self.assertRaises(ValueError):
            self.run_package()
        self.assertFalse(self.output.exists())

    def test_missing_decoder_rejected(self):
        (self.compiled / "TextDecoder.mlmodelc/weights/weight.bin").unlink()
        with self.assertRaises(ValueError):
            self.run_package()

    def test_compiled_symlink_rejected(self):
        (self.compiled / "AudioEncoder.mlmodelc/link").symlink_to(self.source / "model.safetensors")
        with self.assertRaises(ValueError):
            self.run_package()

    def test_unpinned_revision_rejected(self):
        with self.assertRaises(ValueError):
            package(self.source, self.compiled, "main", self.output)

    def test_missing_source_weights_rejected(self):
        (self.source / "model.safetensors").unlink()
        with self.assertRaises(ValueError):
            self.run_package()

    def test_bad_generation_token_rejected(self):
        data = read_json(self.source / "generation_config.json")
        data["suppress_tokens"] = [51865]
        (self.source / "generation_config.json").write_text(json.dumps(data))
        with self.assertRaises(ValueError):
            self.run_package()


class IntegrationPreparationTests(unittest.TestCase):
    # These verify transformations on the retrieved anchors, NOT the complete
    # 91 KB app, SDK type-checking, model correctness, or physical-phone behavior.
    def setUp(self):
        self.anchors = "\n// boundary\n".join(before for before, _ in CHANGES)

    def test_all_anchor_replacements(self):
        result = transform(self.anchors)
        self.assertIn("breeze: breeze, limitSeconds", result)
        self.assertIn("text = try await breeze.transcribe(turnSamples)", result)
        self.assertIn("self.breeze = recognizer", result)

    def test_missing_anchor_fails(self):
        with self.assertRaises(ValueError):
            transform("unrelated source")

    def test_duplicated_anchor_fails(self):
        with self.assertRaises(ValueError):
            transform(self.anchors + CHANGES[0][0])

    def test_second_application_fails(self):
        with self.assertRaises(ValueError):
            transform(transform(self.anchors))

    def test_git_blob_digest(self):
        self.assertEqual(git_blob(b""), "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391")

    def test_reference_is_transcribe_auto(self):
        options = generation_options()
        self.assertEqual(options["task"], "transcribe")
        self.assertIsNone(options["language"])
        self.assertFalse(options["do_sample"])
        self.assertFalse(options["return_timestamps"])


if __name__ == "__main__":
    unittest.main()
