#!/usr/bin/env python3
"""Offline W8A16 trial on the frozen encoder. Never modifies source assets.

Install compression-requirements.lock.txt into a separate Python 3.11 venv.
Uses Apple's direct AIProgram route, not PyTorch re-export or native Mac inference.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import importlib.metadata
import inspect
import json
import logging
import math
from pathlib import Path
import subprocess
import warnings

SOURCE_SHA256 = "fd6ea079176fe51b39a81caab1ac0856e59977e2f7e14bad6b81fbd7635c5db6"
WEIGHTS_SHA256 = "264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a"
# Eligibility in pinned coreai-opt 0.2.1, audited without calling private helpers.
CONSUMERS = {"coreai.batch_matmul", "coreai.conv2d",
             "coreai.decomposable.broadcasting_batch_matmul", "coreai.gather_nd",
             "coreai.transpose"}


def fingerprint(path):
    if path.is_symlink():
        raise ValueError(f"Symlink is not an immutable asset: {path}")
    if path.is_file():
        with path.open("rb") as stream:
            return hashlib.file_digest(stream, "sha256").hexdigest()
    children = {p.name: fingerprint(p) for p in sorted(path.iterdir())
                if not p.name.startswith(".")}
    return hashlib.sha256(json.dumps(children, sort_keys=True, ensure_ascii=False,
                                    separators=(",", ":")).encode()).hexdigest()


def inspect_asset(path):
    return json.loads(subprocess.check_output([
        "xcrun", "coreai-build", "inspect", str(path), "--storage", "--compute",
        "--ops", "--json"], text=True))


def check_contract(summary):
    functions = summary["summary"]["functions"]
    expected = [{"name": "main", "inputs": [{"name": "input_features",
                "type": "NDArray (Float16, 1 × 80 × 3000)"}],
                "outputs": [{"name": "encoder_hidden_states",
                "type": "NDArray (Float16, 1 × 1500 × 1280)"}]}]
    if functions != expected:
        raise ValueError(f"Not the fixed FP16 encoder contract: {functions}")


def audit(program):
    root = program.get_graph("main").operation
    while root.parent is not None:
        root = root.parent
    root.verify()
    constants, compressed, operations = [], [], Counter()

    def walk(op):
        operations[op.name] += 1
        if op.name in {"coreai.constant", "coreai.blockwise_shift_scale"}:
            tensor = op.results[0].type
            shape = list(tensor.shape)
            dtype = str(tensor.element_type)
            count = math.prod(shape)
            consumers = sorted({use.owner.name for use in op.results[0].uses})
            row = {"shape": shape, "dtype": dtype, "elements": count,
                   "consumers": consumers, "location": str(op.location)}
            if op.name == "coreai.constant":
                row["eligible"] = (dtype in {"f16", "f32"} and count > 1024
                                   and (set(consumers) <= CONSUMERS or count >= 100_000_000))
                constants.append(row)
            else:
                row["storage_type"] = str(op.operands[0].type)
                compressed.append(row)
        for region in op.regions:
            for block in region.blocks:
                for child in block.operations:
                    walk(child.operation)
    walk(root)
    return {"operations": dict(operations), "constants": constants,
            "compressed_weights": compressed}


def totals(rows):
    return {"tensors": len(rows), "elements": sum(r["elements"] for r in rows),
            "source_precision_bytes": sum(r["elements"] * (2 if r["dtype"] == "f16" else 4)
                                          for r in rows)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--format", required=True, choices=("fp8", "int8"))
    args = parser.parse_args()
    if args.output_dir.exists():
        parser.error("Output directory already exists; no overwrite or resume")
    if args.source.suffix != ".aimodel" or fingerprint(args.source) != SOURCE_SHA256:
        parser.error("Not the frozen uncompressed encoder .aimodel")
    before_inspect = inspect_asset(args.source)
    check_contract(before_inspect)
    versions = {name: importlib.metadata.version(name) for name in
                ("coreai-core", "coreai-torch", "coreai-opt", "numpy", "ml-dtypes", "torch")}
    for name, expected in {"coreai-core": "1.0.0b2", "coreai-torch": "0.4.1",
                           "coreai-opt": "0.2.1"}.items():
        if versions[name] != expected:
            raise ValueError(f"Unqualified {name}: {versions[name]}")
    from coreai.authoring import AIModelAsset
    from coreai_opt.coreai_utils import quantize_weights, DType, CompressionGranularity
    from coreai_opt.coreai_utils.common import QScheme

    args.output_dir.mkdir(parents=True, exist_ok=False)
    records = []
    class Capture(logging.Handler):
        def emit(self, record):
            records.append(self.format(record))
    handler = Capture(level=logging.WARNING)
    logging.getLogger().addHandler(handler)
    report = {"status": "started", "format": args.format, "versions": versions,
              "source": str(args.source.resolve()), "source_fingerprint": SOURCE_SHA256,
              "merged_weights_sha256": WEIGHTS_SHA256,
              "base": "vinai/PhoWhisper-large@b9136a44b5f2ca664bd0b8f74baecf1715f6eeeb",
              "adapter": "rinhoooo/phowhisper-large-vien-cs-asr@a98f55e0f42b2c4f1e71b3348a2b917fac0a7328",
              "license": before_inspect["metadata"]["license"],
              "api_signature": str(inspect.signature(quantize_weights)),
              "configuration": {"qscheme": "symmetric", "granularity": "per_channel",
                                "scale_dtype": None, "weight_num_threshold": 1024,
                                "in_place": False, "activation_quantization": False},
              "host_numerical_execution": "not performed; authoring/static checks only",
              "warnings": records}
    try:
        asset = AIModelAsset.load(args.source)
        program = asset.program
        before = audit(program)
        (args.output_dir / "audit-before.json").write_text(json.dumps(before, indent=2))
        eligible = [r for r in before["constants"] if r["eligible"]]
        report["eligible"] = totals(eligible)
        report["ineligible_float_constants"] = totals([
            r for r in before["constants"] if r["dtype"] in {"f16", "f32"} and not r["eligible"]])
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            compressed = quantize_weights(
                coreai_program=program,
                dtype=DType.FP8_E4M3FN if args.format == "fp8" else DType.INT8,
                qscheme=QScheme.SYMMETRIC, granularity=CompressionGranularity.PER_CHANNEL,
                weight_num_threshold=1024, scale_dtype=None, in_place=False)
            compressed.optimize()
        records.extend(str(w.message) for w in caught)
        after = audit(compressed)
        (args.output_dir / "audit-after.json").write_text(json.dumps(after, indent=2))
        report["compressed"] = totals(after["compressed_weights"])
        report["eligible_remaining_uncompressed"] = totals([
            r for r in after["constants"] if r["eligible"]])
        if not after["compressed_weights"]:
            raise ValueError("No exported compression operations; refuse deployment")
        path = args.output_dir / f"phowhisper-cs-{args.format}-pc-v1.encoder.aimodel"
        metadata = asset.metadata
        metadata.model_description += f" Offline {args.format} per-channel weight compression; FP16 handoff."
        compressed.save_asset(path, metadata)
        exported = inspect_asset(path)
        check_contract(exported)
        reloaded = audit(AIModelAsset.load(path).program)
        if reloaded["compressed_weights"] != after["compressed_weights"]:
            raise ValueError("Saved compression operations differ")
        report.update(status="exported-static-only", output=str(path.resolve()),
                      output_fingerprint=fingerprint(path),
                      exported_bytes=sum(p.stat().st_size for p in path.rglob("*") if p.is_file()),
                      exported_inspection=exported,
                      exported_compression_ops=reloaded["operations"].get("coreai.blockwise_shift_scale", 0))
        if fingerprint(args.source) != SOURCE_SHA256:
            raise ValueError("Source changed during compression")
    except Exception as error:
        report.update(status="failed", error=repr(error))
        raise
    finally:
        logging.getLogger().removeHandler(handler)
        (args.output_dir / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: report[k] for k in ("status", "eligible", "compressed",
                     "eligible_remaining_uncompressed", "exported_bytes")}, indent=2))


if __name__ == "__main__":
    main()
