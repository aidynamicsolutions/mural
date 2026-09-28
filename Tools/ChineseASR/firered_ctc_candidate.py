"""Host-only CTC candidate admission for the existing Chinese ASR replayer.

This never downloads, converts, activates, or changes Mural's AED package. A local
reviewer must inspect the real graph and freeze the two-file pin before replay.
A reviewed manifest is an input trust boundary, not a claim of upstream signing.
"""
from __future__ import annotations
import hashlib
from importlib.metadata import version
import json
import os
from pathlib import Path
import re
import stat

FIXED_PIN = {
    'schema': 'mural.firered-ctc.research-pin.v1',
    'reviewed_for': 'host_comparison_only',
    'model_type': 'fire-red-asr-2-ctc',
    'source_url': 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-fire-red-asr2-ctc-zh_en-int8-2026-02-25.tar.bz2',
    'sherpa_revision': 'a5b4a944c5186a68bcdc0ac3011e4c541781ac84',
    'sherpa_version': '1.13.8',
    'ort_version': '1.28.2',
    'provider': 'cpu',
    'num_threads': 1,
    'decoding_method': 'greedy_search',
}
NAMES = {'model.int8.onnx', 'tokens.txt'}


def _digest(value) -> bool:
    return isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) is not None


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate JSON key in candidate pin')
        result[key] = value
    return result


def _regular(path: Path):
    # Use a private frozen host staging directory; no concurrent file writers.
    if any(part.is_symlink() for part in (path, *path.parents)):
        raise ValueError('Candidate path must not contain symbolic links')
    try:
        info = path.stat()
    except FileNotFoundError as error:
        raise ValueError('Missing candidate file') from error
    if not stat.S_ISREG(info.st_mode):
        raise ValueError('Candidate file must be regular')
    return info


def verify_candidate(directory: Path, pin_path: Path, expected_pin_sha256: str) -> dict:
    """Verify a separately reviewed pin and exact assets BEFORE importing a runtime.

    Does not inspect ONNX semantics or attest the export producer. Those are local
    review prerequisites documented in firered-smaller-model-review.md.
    """
    if not _digest(expected_pin_sha256):
        raise ValueError('Supply the independently reviewed pin SHA-256')
    if _regular(pin_path).st_size > 65536:
        raise ValueError('Candidate pin exceeds 64 KiB metadata bound')
    data = pin_path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected_pin_sha256:
        raise ValueError('Candidate pin hash mismatch')
    pin = json.loads(data, object_pairs_hook=_unique)
    if not isinstance(pin, dict) or set(pin) != set(FIXED_PIN) | {'archive_sha256', 'artifacts'}:
        raise ValueError('Unexpected candidate pin schema')
    if any(type(pin[k]) is not type(v) or pin[k] != v for k, v in FIXED_PIN.items()):
        raise ValueError('Candidate family, runtime, or reviewed configuration mismatch')
    if not _digest(pin['archive_sha256']):
        raise ValueError('Archive identity has not been frozen')
    artifacts = pin['artifacts']
    if not isinstance(artifacts, dict) or set(artifacts) != NAMES:
        raise ValueError('CTC requires exactly model.int8.onnx and its own tokens.txt')
    if (not directory.is_dir() or any(p.is_symlink() for p in (directory, *directory.parents))
            or {p.name for p in directory.iterdir()} != NAMES):
        raise ValueError('Use a separate frozen two-file CTC staging directory; preserve AED')
    for name in sorted(NAMES):
        expected = artifacts[name]
        if (not isinstance(expected, dict) or set(expected) != {'bytes', 'sha256'}
                or type(expected['bytes']) is not int or expected['bytes'] <= 0
                or not _digest(expected['sha256'])):
            raise ValueError('Invalid candidate artifact identity')
        path = directory / name
        before = _regular(path)
        if before.st_size != expected['bytes']:
            raise ValueError(f'{name}: wrong byte count')
        h = hashlib.sha256()
        with path.open('rb') as handle:
            opened = os.fstat(handle.fileno())
            if (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
                raise ValueError('Candidate changed during verification')
            while chunk := handle.read(1048576):
                h.update(chunk)
            after = os.fstat(handle.fileno())
        if ((before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns)
                or h.hexdigest() != expected['sha256']):
            raise ValueError(f'{name}: changed file or SHA-256 mismatch')
    return {'candidate_pin_sha256': expected_pin_sha256, 'candidate_pin': pin,
            'artifacts': artifacts, 'iphone_qualified': False,
            'identity_note': 'Artifact hashes identify this candidate; no export-producer attestation is claimed.'}


def load_ctc(directory: Path):
    """Called by run_reference only after pin verification; no AED fallback.

    The version check cannot prove linked ORT provenance. The retained source-built
    environment and its actual native-linkage receipt are a separate required gate.
    """
    installed_version = version('sherpa-onnx')
    if installed_version != FIXED_PIN['sherpa_version']:
        raise ValueError('Use the retained reviewed sherpa-onnx 1.13.8 host environment')
    import numpy as np
    import sherpa_onnx
    factory = getattr(sherpa_onnx.OfflineRecognizer, 'from_fire_red_asr_ctc', None)
    if not callable(factory):
        raise ValueError('This runtime lacks the required CTC API; no fallback')
    recognizer = factory(model=str(directory / 'model.int8.onnx'),
        tokens=str(directory / 'tokens.txt'), num_threads=1,
        provider='cpu', decoding_method='greedy_search', debug=False)

    def decode(samples):
        if not 0 < len(samples) <= 480000:
            raise ValueError('CTC comparison requires 0 < audio <= 30 seconds at 16 kHz')
        # pcm16() in the existing replayer validates PCM16 input. Preserve its scaling.
        stream = recognizer.create_stream()
        stream.accept_waveform(16000, np.asarray(samples, dtype=np.float32) / 32768.0)
        recognizer.decode_stream(stream)
        return stream.result.text  # Never normalize, translate or repair the transcript.

    return decode, {'sherpa-onnx': installed_version,
        'api': 'OfflineRecognizer.from_fire_red_asr_ctc', 'provider': 'cpu',
        'num_threads': 1, 'decoding_method': 'greedy_search',
        'ort_linkage_validation': 'requires_local_build_receipt',
        'note': 'CTC-only research, not AED parity, memory qualification, or an iPhone result.'}
