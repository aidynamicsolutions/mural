#!/usr/bin/env python3
"""Compare bounded phone decoder calls to the frozen FP16 PyTorch decoder.

Use the existing split-export Python environment. This reuses the phone's encoder
checkpoint, not a different frontend. No transcription or parity tolerance is
invented here: report raw differences and missing outputs, not a corpus pass.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import platform
import time
from pathlib import Path

import numpy as np

WEIGHTS_SHA256 = "264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a"
PREFIXES = {1: [50258], 4: [50258, 50278, 50359, 50363]}


def sha256(path):
    with Path(path).open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def summary(row):
    if row.ndim != 1 or row.size < 2 or not np.isfinite(row).all():
        raise ValueError("Expected a finite logits row")
    ids = np.argsort(-row, kind="stable")[:5]
    return {"topIDs": ids.tolist(), "topLogits": row[ids].tolist(),
            "winnerMargin": float(row[ids[0]] - row[ids[1]])}


def compare(reference, actual):
    if reference.shape != actual.shape:
        raise ValueError("Logit shapes differ")
    ref_top, actual_top = summary(reference), summary(actual)
    delta = actual.astype(np.float64) - reference.astype(np.float64)
    return {"reference": ref_top, "actual": actual_top,
            "sameWinner": ref_top["topIDs"][0] == actual_top["topIDs"][0],
            "sameTop5Order": ref_top["topIDs"] == actual_top["topIDs"],
            "bitExact": reference.tobytes() == actual.tobytes(),
            "maxAbsoluteError": float(np.abs(delta).max()),
            "meanAbsoluteError": float(np.abs(delta).mean()),
            "rootMeanSquareError": float(np.sqrt(np.mean(delta * delta)))}


def self_test():
    row = np.array([1, 4, 4, -2], dtype="<f4")
    assert summary(row)["topIDs"] == [1, 2, 0, 3]
    assert compare(row, row)["bitExact"]
    assert compare(row, row + 1)["maxAbsoluteError"] == 1
    for invalid in (row[:-1], np.array([1, np.nan, 4, -2]),
                    np.array([1, np.inf, 4, -2])):
        try:
            compare(row, invalid)
        except ValueError:
            pass
        else:
            raise AssertionError("Accepted invalid logits")
    print("PASS: finite rows, shape validation, deterministic ties, raw error metrics")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path)
    parser.add_argument("--checkpoint", type=Path, help="001.wav.fp16; adjacent .json required")
    parser.add_argument("--run-dir", type=Path, action="append", default=[])
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if not all((args.model_dir, args.checkpoint, args.output_dir)) or not args.run_dir:
        parser.error("model-dir, checkpoint, output-dir and at least one run-dir are required")

    import torch
    import transformers
    from export_phowhisper_split_coreai import DecoderModule, EXPECTED

    metadata = json.loads(args.checkpoint.with_suffix(".json").read_text())
    tensor_hash = sha256(args.checkpoint)
    if tensor_hash != metadata["tensorSHA256"]:
        raise ValueError("Encoder checkpoint SHA-256 differs")
    hidden = np.fromfile(args.checkpoint, dtype="<f2")
    if hidden.size != 1500 * 1280 or not np.isfinite(hidden).all():
        raise ValueError("Invalid FP16 encoder checkpoint")
    if sha256(args.model_dir / "model.safetensors") != WEIGHTS_SHA256:
        raise ValueError("Not the frozen accepted weights")
    args.output_dir.mkdir(parents=True, exist_ok=False)
    torch.set_num_threads(4)
    model = transformers.AutoModelForSpeechSeq2Seq.from_pretrained(
        str(args.model_dir), dtype=torch.float16, use_safetensors=True,
        local_files_only=True, low_cpu_mem_usage=True).eval()
    if any(getattr(model.config, k, None) != v for k, v in EXPECTED.items()):
        raise ValueError("Not the accepted PhoWhisper architecture")
    hidden = torch.from_numpy(hidden.reshape(1, 1500, 1280))
    decoder = DecoderModule(model).eval()
    resolved = model.config._attn_implementation
    report = {"weightsSHA256": WEIGHTS_SHA256, "tensorSHA256": tensor_hash,
              "checkpoint": metadata, "device": "cpu", "dtype": "float16",
              "torchThreads": torch.get_num_threads(), "platform": platform.platform(),
              "python": platform.python_version(), "resolvedExportAttention": resolved,
              "packages": {p: importlib.metadata.version(p) for p in
                           ("torch", "transformers", "numpy", "safetensors", "coreai-core", "coreai-torch")},
              "references": {}, "calls": []}
    references = {}
    # The export left attention implicit; the accepted Python benchmark used eager.
    for attention in dict.fromkeys((resolved, "eager")):
        model.set_attn_implementation(attention)
        if model.model.decoder.config._attn_implementation != attention:
            raise ValueError("Decoder did not select the requested attention implementation")
        for length, tokens in PREFIXES.items():
            start = time.monotonic()
            with torch.inference_mode():
                logits = decoder(torch.tensor([tokens], dtype=torch.int32), hidden)
            seconds = time.monotonic() - start
            if list(logits.shape) != [1, length, 51865] or not torch.isfinite(logits).all():
                raise ValueError("Invalid raw reference logits")
            row = logits[0, -1].float().numpy().astype("<f4")
            key = f"{attention}-{length}"
            row.tofile(args.output_dir / f"{key}.logits.f32")
            references[key] = row
            report["references"][key] = {"tokens": tokens, "seconds": seconds,
                                         "allRowsFinite": True, **summary(row)}
            print(key, report["references"][key], flush=True)
    if resolved != "eager":
        report["attentionComparison"] = {str(n): compare(references[f"eager-{n}"], references[f"{resolved}-{n}"])
                                         for n in PREFIXES}

    for directory in args.run_dir:
        events = [json.loads(line) for line in (directory / "events.jsonl").read_text().splitlines()]
        run_id = json.loads((directory / "report.json").read_text())["runID"]
        if any(e["runID"] != run_id for e in events) or not any(
                e["stage"] == "checkpoint-verified" and e["tensorSHA256"] == tensor_hash for e in events):
            raise ValueError(f"Run/checkpoint identity differs: {directory}")
        outputs = {e["callIndex"]: e for e in events if e["stage"] == "decoder-after"}
        for before in (e for e in events if e["stage"] == "decoder-before"):
            length = before["prefixLength"]
            if PREFIXES.get(length) != before["tokens"]:
                raise ValueError("Not a supported diagnostic prefix")
            call = {"runID": run_id, "directory": str(directory), "callIndex": before["callIndex"],
                    "tokens": before["tokens"], "outputAvailable": before["callIndex"] in outputs}
            if call["outputAvailable"]:
                after = outputs[before["callIndex"]]
                path = directory / after["lastRowFile"]
                row = np.fromfile(path, dtype="<f4")
                if row.shape != (51865,) or path.stat().st_size != 51865 * 4 or after["tokens"] != before["tokens"]:
                    raise ValueError("Invalid phone row or token identity")
                call["logitsSHA256"] = sha256(path)
                call["comparisons"] = {key: compare(ref, row) for key, ref in references.items()
                                       if key.endswith(f"-{length}")}
            report["calls"].append(call)
    (args.output_dir / "comparison.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    print(args.output_dir / "comparison.json")


if __name__ == "__main__":
    main()
