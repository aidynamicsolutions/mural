"""Host-only admission/API contracts, written before implementation.

Failure matrix: wrong/duplicate keys, missing or changed hashes/files, symlinks,
wrong family/runtime/provider, draft pin, wrong CLI identity, silent AED fallback,
unsupported runtime, long audio, and raw transcript changes. No ASR is executed.
"""
from contextlib import contextmanager
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace, ModuleType
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import firered_ctc_candidate as candidate


def digest(data): return hashlib.sha256(data).hexdigest()


class CandidateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.models = self.root / 'model'; self.models.mkdir()
        self.pinpath = self.root / 'pin.json'
        payloads = {'model.int8.onnx': b'host-fixture-not-onnx', 'tokens.txt': b'<blank> 0\n'}
        for name, data in payloads.items(): (self.models / name).write_bytes(data)
        self.pin = {**candidate.FIXED_PIN, 'archive_sha256': '1' * 64,
                    'artifacts': {name: {'bytes': len(data), 'sha256': digest(data)} for name, data in payloads.items()}}

    def write_pin(self):
        data = json.dumps(self.pin, sort_keys=True).encode()
        self.pinpath.write_bytes(data)
        return digest(data)

    def verify(self):
        return candidate.verify_candidate(self.models, self.pinpath, self.write_pin())

    def test_verified_exact_two_file_identity(self):
        report = self.verify()
        self.assertEqual(report['artifacts'], self.pin['artifacts'])
        self.assertEqual(report['candidate_pin_sha256'], digest(self.pinpath.read_bytes()))
        self.assertIs(report['iphone_qualified'], False)

    def test_changed_pin_refused_before_any_model_use(self):
        expected = self.write_pin(); self.pinpath.write_bytes(self.pinpath.read_bytes() + b' ')
        with self.assertRaises(ValueError): candidate.verify_candidate(self.models, self.pinpath, expected)

    def test_missing_changed_or_extra_artifact_refused(self):
        for alteration in ('missing', 'bytes', 'extra'):
            with self.subTest(alteration=alteration):
                original = (self.models / 'tokens.txt').read_bytes()
                if alteration == 'missing': (self.models / 'tokens.txt').unlink()
                elif alteration == 'bytes': (self.models / 'tokens.txt').write_bytes(b'changed')
                else: (self.models / 'decoder.int8.onnx').write_bytes(b'unexpected')
                with self.assertRaises(ValueError): self.verify()
                (self.models / 'tokens.txt').write_bytes(original)
                (self.models / 'decoder.int8.onnx').unlink(missing_ok=True)

    def test_bad_pin_fields_refused(self):
        original = json.loads(json.dumps(self.pin))
        for key, value in [('model_type', 'fire-red-asr-2'), ('reviewed_for', 'pending'),
                           ('sherpa_version', '1.13.9'), ('ort_version', '1.28.1'),
                           ('archive_sha256', None), ('provider', 'coreml'),
                           ('num_threads', 2), ('unknown', True)]:
            with self.subTest(key=key):
                self.pin = json.loads(json.dumps(original)); self.pin[key] = value
                with self.assertRaises(ValueError): self.verify()

    def test_bool_size_and_path_traversal_refused(self):
        self.pin['artifacts']['tokens.txt']['bytes'] = True
        with self.assertRaises(ValueError): self.verify()
        self.pin['artifacts']['../escape'] = self.pin['artifacts'].pop('tokens.txt')
        with self.assertRaises(ValueError): self.verify()

    def test_symlinked_file_root_and_pin_refused(self):
        original = self.models / 'tokens.txt'
        real = self.root / 'real-tokens'; original.rename(real); original.symlink_to(real)
        with self.assertRaises(ValueError): self.verify()
        original.unlink(); real.rename(original)
        link = self.root / 'link'; link.symlink_to(self.models, target_is_directory=True)
        pinsha = self.write_pin()
        with self.assertRaises(ValueError): candidate.verify_candidate(link, self.pinpath, pinsha)
        pinlink = self.root / 'pinlink'; pinlink.symlink_to(self.pinpath)
        with self.assertRaises(ValueError): candidate.verify_candidate(self.models, pinlink, pinsha)

    def test_duplicate_json_key_refused(self):
        data = json.dumps(self.pin)[:-1] + ', "model_type":"fire-red-asr-2-ctc"}'
        self.pinpath.write_text(data)
        with self.assertRaises(ValueError):
            candidate.verify_candidate(self.models, self.pinpath, digest(data.encode()))

    def test_native_factory_is_ctc_cpu_one_thread_greedy_and_raw(self):
        calls = []
        text = '  原始 Yes！  '
        class Samples:
            def __truediv__(self, _): return self
        np = ModuleType('numpy'); np.float32 = 'float32'; np.asarray = lambda *a, **k: Samples()
        stream = SimpleNamespace(result=SimpleNamespace(text=text), accept_waveform=lambda *a: calls.append(a))
        recognizer = SimpleNamespace(create_stream=lambda: stream, decode_stream=lambda _: None)
        def factory(**kwargs): calls.append(kwargs); return recognizer
        sherpa = ModuleType('sherpa_onnx')
        sherpa.OfflineRecognizer = SimpleNamespace(from_fire_red_asr_ctc=factory)
        with patch.dict(sys.modules, {'numpy': np, 'sherpa_onnx': sherpa}), patch.object(candidate, 'version', return_value='1.13.8'):
            decode, metadata = candidate.load_ctc(self.models)
            self.assertEqual(decode([1, 2, 3]), text)
            for samples in ([], [0] * 480001):
                with self.assertRaises(ValueError): decode(samples)
        self.assertEqual(calls[0], {'model': str(self.models / 'model.int8.onnx'),
            'tokens': str(self.models / 'tokens.txt'), 'num_threads': 1,
            'provider': 'cpu', 'decoding_method': 'greedy_search', 'debug': False})
        self.assertEqual(metadata['ort_linkage_validation'], 'requires_local_build_receipt')

    def test_wrong_runtime_refused_without_native_construction(self):
        with patch.object(candidate, 'version', return_value='0.0.0'):
            with self.assertRaises(ValueError): candidate.load_ctc(self.models)


class ReplayIntegrationTests(unittest.TestCase):
    @contextmanager
    def runner(self):
        # Only existing dependencies are stubbed; test actual changed CLI/main logic.
        evaluate = ModuleType('evaluate')
        for name in ('audio_path', 'corpus', 'pcm16', 'sha256', 'validate_audio', 'write_json'):
            setattr(evaluate, name, lambda *a, **k: None)
        breeze = ModuleType('prepare_breeze'); breeze.validate_source = lambda _: None
        with patch.dict(sys.modules, {'evaluate': evaluate, 'prepare_breeze': breeze}):
            spec = importlib.util.spec_from_file_location('reviewed_reference', ROOT / 'run_reference.py')
            module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
            yield module

    def test_original_aed_path_not_replaced(self):
        with self.runner() as r:
            import inspect
            self.assertIn('from_fire_red_asr(', inspect.getsource(r.load_firered))
            self.assertNotIn('ctc', inspect.getsource(r.load_firered))

    def test_new_mode_requires_independent_pin_no_fake_revision_or_non_cpu(self):
        with self.runner() as r, tempfile.TemporaryDirectory() as td:
            base = ['run_reference.py', 'firered-ctc-onnx', 'corpus', 'audio', '--model-dir', 'model', '--output', td + '/out']
            for extra in ([], ['--revision', 'a' * 40], ['--device', 'mps']):
                with self.subTest(extra=extra), patch.object(sys, 'argv', base + extra):
                    with self.assertRaises(SystemExit) as error: r.main()
                    self.assertEqual(error.exception.code, 2)
            self.assertFalse((Path(td) / 'out').exists())

    def test_existing_modes_still_require_revision_and_reject_candidate_flags(self):
        with self.runner() as r, tempfile.TemporaryDirectory() as td:
            for backend in ('breeze', 'firered-onnx'):
                base = ['run_reference.py', backend, 'corpus', 'audio', '--model-dir', 'model', '--output', td + '/out']
                for extra in ([], ['--revision', 'a' * 40, '--candidate-pin', 'pin']):
                    with self.subTest(backend=backend, extra=extra), patch.object(sys, 'argv', base + extra):
                        with self.assertRaises(SystemExit) as error: r.main()
                        self.assertEqual(error.exception.code, 2)

if __name__ == '__main__': unittest.main()
