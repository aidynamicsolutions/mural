import json
from pathlib import Path
import tempfile
import unittest
import wave

from evaluate import audio_path, corpus, edits, evaluate, pcm16, tokens, validate_audio, write_json


def clip(identity="tw01", reference="我要 coffee。", group="zh-en"):
    return {"id": identity, "wav": f"{identity}.wav", "speaker": "speaker-a", "locale": "zh-TW", "group": group, "reference": reference}


def predictions(*items):
    return {"schema": "mural.chinese-asr.predictions.v1", "predictions": list(items)}


class EvaluationTests(unittest.TestCase):
    def test_mixed_tokens(self):
        self.assertEqual(tokens("我要 COFFEE，please!"), ["我", "要", "coffee", "please"])

    def test_script_not_converted(self):
        self.assertNotEqual(tokens("軟體"), tokens("软件"))

    def test_punctuation_does_not_join_words(self):
        self.assertEqual(tokens("ice-cream, please"), ["ice", "cream", "please"])

    def test_apostrophes(self):
        self.assertEqual(tokens("I’m ready; don't wait."), ["i'm", "ready", "don't", "wait"])

    def test_nfc(self):
        self.assertEqual(tokens("caf\u0065\u0301"), tokens("café"))

    def test_supplementary_han(self):
        self.assertEqual(tokens("𠮷野 coffee"), ["𠮷", "野", "coffee"])

    def test_edit_distance(self):
        self.assertEqual(edits(["a", "b"], ["a", "c", "d"]), 2)
        self.assertEqual(edits(["a"], []), 1)
        self.assertEqual(edits([], ["a"]), 1)

    def test_empty_prediction_is_deletions(self):
        result = evaluate([clip()], predictions({"id": "tw01", "text": ""}))
        self.assertEqual(result["totals"]["mer"], 1)

    def test_missing_prediction_fails(self):
        with self.assertRaises(ValueError):
            evaluate([clip()], predictions())

    def test_extra_prediction_fails(self):
        with self.assertRaises(ValueError):
            evaluate([clip()], predictions({"id": "tw01", "text": ""}, {"id": "other", "text": ""}))

    def test_duplicate_prediction_fails(self):
        with self.assertRaises(ValueError):
            evaluate([clip()], predictions({"id": "tw01", "text": ""}, {"id": "tw01", "text": ""}))

    def test_failed_inference_not_scored(self):
        with self.assertRaises(ValueError):
            evaluate([clip()], predictions({"id": "tw01", "text": "", "error": "native failure"}))

    def test_incomplete_run_rejected_even_with_all_rows(self):
        data = predictions({"id": "tw01", "text": "我要 coffee"})
        data["complete"] = False
        with self.assertRaises(ValueError):
            evaluate([clip()], data)

    def test_failed_run_rejected_even_with_all_rows(self):
        data = predictions({"id": "tw01", "text": "我要 coffee"})
        data["failure"] = "runtime failed during cleanup"
        with self.assertRaises(ValueError):
            evaluate([clip()], data)

    def test_translated_english_is_an_error(self):
        result = evaluate([clip()], predictions({"id": "tw01", "text": "我要咖啡"}))
        self.assertGreater(result["totals"]["mer"], 0)

    def test_silence_kept_separate(self):
        rows = [clip(), clip("quiet", "", "silence")]
        result = evaluate(rows, predictions({"id": "tw01", "text": "我要 coffee"}, {"id": "quiet", "text": "..."}))
        self.assertEqual(result["totals"]["mer"], 0)
        self.assertEqual(result["totals"]["silence_nonempty"], 1)

    def test_all_silence_has_no_mer(self):
        result = evaluate([clip("quiet", "", "silence")], predictions({"id": "quiet", "text": ""}))
        self.assertIsNone(result["totals"]["mer"])

    def test_score_hides_text_by_default(self):
        result = evaluate([clip()], predictions({"id": "tw01", "text": "我要 coffee"}))
        self.assertNotIn("reference", result["clips"][0])
        self.assertNotIn("hypothesis", result["clips"][0])

    def test_invalid_measurements(self):
        for value in (float("nan"), float("inf"), -1, True, "1"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                evaluate([clip()], predictions({"id": "tw01", "text": "", "decode_seconds": value}))

    def test_group_aggregation_is_token_weighted(self):
        rows = [clip("one", "好", "zh"), clip("two", "今天很好", "zh")]
        result = evaluate(rows, predictions({"id": "one", "text": ""}, {"id": "two", "text": "今天很好"}))
        self.assertEqual(result["totals"]["mer"], 0.2)


class FileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def manifest(self, rows):
        path = self.root / "corpus.json"
        path.write_text(json.dumps({"schema": "mural.chinese-asr.corpus.v1", "clips": rows}), encoding="utf-8")
        return path

    def wav(self, rate=16000, channels=1, width=2, count=1600):
        path = self.root / "tw01.wav"
        with wave.open(str(path), "wb") as handle:
            handle.setnchannels(channels); handle.setsampwidth(width); handle.setframerate(rate)
            handle.writeframes(b"\0" * count * width * channels)
        return path

    def test_valid_audio(self):
        self.wav()
        report = validate_audio(corpus(self.manifest([clip()])), self.root)
        self.assertEqual(report["clip_count"], 1)
        self.assertAlmostEqual(report["audio_seconds"], 0.1)
        self.assertEqual(len(report["clips"][0]["sha256"]), 64)

    def test_audio_format_rejections(self):
        for kwargs in ({"rate": 8000}, {"channels": 2}, {"width": 1}, {"count": 0}, {"count": 480001}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                pcm16(self.wav(**kwargs))

    def test_boundary_30_seconds(self):
        self.assertEqual(pcm16(self.wav(count=480000))[1], 30)

    def test_truncated_audio(self):
        path = self.wav()
        path.write_bytes(path.read_bytes()[:-2])
        with self.assertRaises(ValueError):
            pcm16(path)

    def test_duplicate_ids(self):
        with self.assertRaises(ValueError):
            corpus(self.manifest([clip(), clip()]))

    def test_path_traversal_rejected(self):
        for name in ("../x.wav", "/x.wav", "a/../x.wav", "a\\x.wav", "a//x.wav"):
            row = clip(); row["wav"] = name
            with self.subTest(name=name), self.assertRaises(ValueError):
                corpus(self.manifest([row]))

    def test_symlink_escape_rejected(self):
        with tempfile.TemporaryDirectory() as other:
            outside = Path(other) / "outside.wav"; outside.write_bytes(b"private")
            (self.root / "link.wav").symlink_to(outside)
            with self.assertRaises(ValueError):
                audio_path(self.root, "link.wav")

    def test_no_overwrite(self):
        path = self.root / "result.json"
        write_json(path, {"original": True})
        with self.assertRaises(FileExistsError):
            write_json(path, {"original": False})
        self.assertEqual(json.loads(path.read_text()), {"original": True})

    def test_duplicate_json_keys_rejected(self):
        path = self.root / "bad.json"
        path.write_text('{"schema": "a", "schema": "b"}')
        with self.assertRaises(ValueError):
            corpus(path)

    def test_no_empty_speech_reference(self):
        for reference in ("", "...", "   "):
            with self.subTest(reference=reference), self.assertRaises(ValueError):
                corpus(self.manifest([clip(reference=reference)]))

    def test_required_speaker_locale(self):
        for key, value in (("speaker", ""), ("locale", "zh"), ("group", "unknown")):
            row = clip(); row[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                corpus(self.manifest([row]))


if __name__ == "__main__":
    unittest.main()
