#!/usr/bin/env python3
"""Compare saved native encoder tensors tied to the SAME saved mel input.

Each JSON descriptor contains path, sha256, mel_sha256, artifact_fingerprint,
shape=[1,1500,1280], dtype='float16-le'. Paths are relative to the descriptor.
Only use decoder-ready hidden tensors AFTER the native v3 challenge gate.
No diagnostic cosine/error threshold is a speech-accuracy acceptance gate.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re

from pal6_contract import sha256


def read_tensor(descriptor: Path):
    import numpy as np
    record = json.loads(descriptor.read_text())
    for field in ("sha256", "mel_sha256", "artifact_fingerprint"):
        if not isinstance(record.get(field), str) or not re.fullmatch(r"[0-9a-f]{64}", record[field]):
            raise ValueError(f"Missing/invalid {field}: {descriptor}")
    if record.get("shape") != [1, 1500, 1280] or record.get("dtype") != "float16-le":
        raise ValueError(f"Wrong encoder tensor contract: {descriptor}")
    path = descriptor.parent / record["path"]
    if path.stat().st_size != 1_920_000 * 2 or sha256(path) != record["sha256"]:
        raise ValueError(f"Wrong tensor bytes/digest: {path}")
    values = np.fromfile(path, dtype="<f2").astype(np.float64)
    if not np.isfinite(values).all():
        raise ValueError(f"Non-finite native hidden output: {path}")
    return record, values


def compare(reference: Path, candidate: Path, repeat: Path | None = None) -> dict:
    import numpy as np
    ref, a = read_tensor(reference)
    trial, b = read_tensor(candidate)
    if ref["mel_sha256"] != trial["mel_sha256"]:
        raise ValueError("Different mel tensors: encoder comparison is confounded")
    repeatability = None
    if repeat:
        repeated, c = read_tensor(repeat)
        if (repeated["mel_sha256"], repeated["artifact_fingerprint"]) != (
                trial["mel_sha256"], trial["artifact_fingerprint"]):
            raise ValueError("Repeat is not the same candidate and mel tensor")
        repeatability = {"bit_exact": repeated["sha256"] == trial["sha256"],
                         "max_abs_error": float(np.max(np.abs(c - b)))}
    delta = np.abs(a - b)
    norm = float(np.linalg.norm(a) * np.linalg.norm(b))
    return {"status": "diagnostic-only-not-speech-qualification", "finite": True,
            "shape": [1, 1500, 1280], "mel_sha256": ref["mel_sha256"],
            "reference": ref, "candidate": trial,
            "max_abs_error": float(delta.max()), "mean_abs_error": float(delta.mean()),
            "cosine_similarity": float(np.clip(np.dot(a, b) / norm, -1, 1)) if norm else None,
            "bit_exact": ref["sha256"] == trial["sha256"], "repeatability": repeatability,
            "warning": "Transcript/corpus and live bilingual acceptance are separate gates"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--repeat", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = compare(args.reference, args.candidate, args.repeat)
    # Exclusive write: never replace reference evidence.
    with args.output.open("x") as stream:
        stream.write(json.dumps(result, indent=2, allow_nan=False) + "\n")
    print(result["status"])


if __name__ == "__main__":
    main()
