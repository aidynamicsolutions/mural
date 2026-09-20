import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from evaluate import read_json
from prepare_breeze import BUNDLES, BUNDLE_FILES, REQUIRED_CONFIG, SUPPORT, package
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


class IntegrationTests(unittest.TestCase):
    # Actual source contracts, not native scheduling or speech-quality evidence.
    def setUp(self):
        root = Path(__file__).resolve().parents[2]
        self.engine = (root / "App/LocalConversationEngine.swift").read_text()
        self.actor = (root / "App/BreezeEnglishRecognizer.swift").read_text()
        self.view = (root / "App/RootView.swift").read_text()

    def test_talk_keeps_phowhisper_and_trimming(self):
        prepare = self.engine.split("func prepareConversation()", 1)[1].split("func recordConversationTurn", 1)[0]
        self.assertIn("selectASR(.phoWhisper)", prepare)
        self.assertIn("text = try await whisper.transcribe(analysis.samples)", self.engine)
        self.assertIn("text = try await breeze.transcribe(turnSamples)", self.engine)
        self.assertNotIn(".analyze(samples", self.actor)

    def test_breeze_uses_existing_owner_and_cancellation(self):
        self.assertIn("parakeet == nil && breeze == nil", self.engine)
        self.assertIn("parakeet != nil || breeze != nil", self.engine)
        self.assertIn("parakeet = nil; breeze = nil", self.engine)
        self.assertIn("parakeet = parakeet, breeze = breeze", self.engine)
        self.assertIn("breeze: breeze, limitSeconds", self.engine)
        self.assertIn("defer { self.asrTask = nil }", self.engine)
        self.assertIn("guard self.generation == token, !Task.isCancelled", self.engine)
        self.assertIn("guard !busy, let kit", self.actor)

    def test_memory_warning_remains_latched(self):
        self.assertIn("static var enabled: Bool { true }", self.engine)
        self.assertIn("self.stagedMemoryWarning = true\n                        self.stop()", self.engine)
        self.assertEqual(self.engine.count("stagedMemoryWarning = false"), 1)
        self.assertIn("!stagedMemoryWarning && asrTask == nil", self.engine)

    def test_assets_fail_closed_and_use_breeze_tokenizer(self):
        self.assertIn("guard flags.count == 1", self.actor)
        self.assertIn("guard digest(data) == expected", self.actor)
        self.assertIn("AutoTokenizerWrapper.from(modelFolder: directory)", self.actor)
        self.assertIn("load: false, download: false", self.actor)
        self.assertIn("task: .transcribe, sampleLength: 220, detectLanguage: true", self.actor)
        self.assertIn("breeze_vad mode=", self.actor)

    def test_probe_does_not_offer_download_repair(self):
        self.assertIn("audio.asrModel != .phoWhisper, audio.asrModel != .breeze", self.view)
        self.assertIn("Taiwan Mandarin and English", self.view)
        self.assertIn("ASRModel.allCases", self.view)

    def test_reference_is_transcribe_auto(self):
        options = generation_options()
        self.assertEqual(options["task"], "transcribe")
        self.assertIsNone(options["language"])
        self.assertFalse(options["do_sample"])
        self.assertFalse(options["return_timestamps"])


if __name__ == "__main__":
    unittest.main()
