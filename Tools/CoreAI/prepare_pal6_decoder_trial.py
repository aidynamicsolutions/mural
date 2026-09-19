#!/usr/bin/env python3
"""Recover the PINNED historical PAL6 decoder, not an old whole-pair result.

Read-only admission of existing assets. Produces an exclusive evidence directory
and a reviewable runtime patch. Never converts, installs, changes pins, deletes
caches, or applies the patch. Native ABI/corpus/device gates are still mandatory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil

REFERENCE_PIN = "430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336"
CANDIDATE_PIN = "13f9bbd0d08bf0b6a111f8415ddffad158f8d1fb4e4014c17585066e37fd23bb"
FP8_PIN = "73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13"
IDENTITY = "phowhisper-cs-pal6-g16-v1"
DECODER = "TextDecoder.mlmodelc/"
UNUSED_ENCODER = "AudioEncoder.mlmodelc/"


def sha(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Not a regular non-symlink file: {path}")
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def read_json(path: Path):
    return json.loads(path.read_text(), object_pairs_hook=unique_object,
                      parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))


def safe_file(root: Path, name: str) -> Path:
    if (not isinstance(name, str) or not name or "\\" in name or "\x00" in name
            or PurePosixPath(name).is_absolute() or
            any(p in {"", ".", ".."} for p in name.split("/"))):
        raise ValueError(f"Unsafe manifest path: {name!r}")
    path = root
    for part in name.split("/"):
        path = path / part
        if path.is_symlink():
            raise ValueError(f"Symlink in manifest path: {name}")
    if not path.is_file():
        raise ValueError(f"Missing regular manifest file: {name}")
    return path


def inspect_support(root: Path, expected_pin: str) -> dict:
    if root.is_symlink() or not root.is_dir():
        raise ValueError(f"Missing/nonregular support root: {root}")
    manifest = root / "manifest.json"
    if sha(manifest) != expected_pin:
        raise ValueError(f"Historical support manifest is not pinned: {root}")
    data = read_json(manifest)
    files = data.get("files")
    if not isinstance(files, dict) or not files:
        raise ValueError("Expected a nonempty flat manifest.files inventory")
    inventory = {}
    for name, record in files.items():
        if (not isinstance(record, dict) or type(record.get("bytes")) is not int
                or record["bytes"] < 0 or not isinstance(record.get("sha256"), str)
                or not re.fullmatch(r"[0-9a-f]{64}", record["sha256"])):
            raise ValueError(f"Malformed manifest row: {name}")
        path = safe_file(root, name)
        if path.stat().st_size != record["bytes"] or sha(path) != record["sha256"]:
            raise ValueError(f"Changed/truncated manifest file: {name}")
        inventory[name] = {"bytes": record["bytes"], "sha256": record["sha256"]}
    decoder_files = {n: r for n, r in inventory.items() if n.startswith(DECODER)}
    if not decoder_files or not any(n.startswith(DECODER + "weights/") for n in decoder_files):
        raise ValueError("No inventoried compiled decoder/weights")
    extras = []
    for p in root.rglob("*"):
        if p.is_symlink():
            raise ValueError(f"Symlink in support directory: {p}")
        if p.is_file() and p.relative_to(root).as_posix() not in {*inventory, "manifest.json"}:
            extras.append({"path": p.relative_to(root).as_posix(), "bytes": p.stat().st_size})
    # Extras are NOT removed or claimed to be verified. Only manifest-listed
    # originals are copied into a new staging directory on explicit request.
    digest = hashlib.sha256(json.dumps(decoder_files, sort_keys=True,
                            separators=(",", ":")).encode()).hexdigest()
    return {"root": str(root.resolve()), "manifest_sha256": expected_pin,
            "files": inventory, "decoder_inventory_sha256": digest,
            "decoder_bytes": sum(r["bytes"] for r in decoder_files.values()),
            "support_manifest_bytes": sum(r["bytes"] for r in inventory.values()),
            "uninventoried_extras_not_staged": extras}


def compare_supports(reference: dict, candidate: dict) -> dict:
    # The compiled Core ML AudioEncoder is unused: the actual encoder is the
    # independently pinned FP8 Core AI artifact. No other support file may vary.
    def common(report):
        return {n: r for n, r in report["files"].items()
                if not n.startswith((DECODER, UNUSED_ENCODER))}
    left, right = common(reference), common(candidate)
    changed = sorted(k for k in left.keys() | right.keys() if left.get(k) != right.get(k))
    required = {"generation_config.json"}
    if (not required <= left.keys() or
            not any(k.startswith("MelSpectrogram.mlmodelc/") for k in left) or
            not any("tokenizer" in k.lower() for k in left)):
        raise ValueError("Missing frontend/tokenizer/generation support inventory")
    if changed:
        raise ValueError(f"Non-decoder speech variables differ: {changed}")
    if reference["decoder_inventory_sha256"] == candidate["decoder_inventory_sha256"]:
        raise ValueError("PAL6 decoder is identical to control; no precision experiment")
    return {"unchanged_common_files": sorted(left),
            "changed_components": ["TextDecoder.mlmodelc"],
            "ignored_component_reason": "AudioEncoder.mlmodelc is not loaded by staged FP8 encoding",
            "decoder_storage_delta_bytes": candidate["decoder_bytes"] - reference["decoder_bytes"],
            "runtime_memory_or_latency_improvement": "NOT MEASURED"}


def verify_fp8(path: Path) -> dict:
    if sha(path) != FP8_PIN:
        raise ValueError("Not the retained packed-v3 FP8 manifest")
    from w8_runtime_identity import audit_reports
    report = read_json(path)
    audit_reports([report], require_triple=False)
    spec = report["identity"]
    if spec["kind"] != "encoder" or spec["format"] != "fp8" or spec["transport"] != "packed":
        raise ValueError("Not the fixed packed FP8 encoder")
    return {"manifest_sha256": FP8_PIN, "identity": spec,
            "aot": report["aot"], "source": report["source"]}


def stage_support(report: dict, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=False)
    root = Path(report["root"])
    for name in report["files"]:
        source = safe_file(root, name)
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with source.open("rb") as src, target.open("xb") as dst:
            shutil.copyfileobj(src, dst, length=1_048_576)
    with (root / "manifest.json").open("rb") as src, (destination / "manifest.json").open("xb") as dst:
        shutil.copyfileobj(src, dst)
    inspect_support(destination, report["manifest_sha256"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference-support", type=Path, required=True)
    parser.add_argument("--historical-pal6-support", type=Path, required=True)
    parser.add_argument("--fp8-manifest", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--stage-support", action="store_true")
    args = parser.parse_args()
    try:
        if args.output_dir.exists():
            raise ValueError("Use a new output directory; no overwrite/resume")
        reference = inspect_support(args.reference_support, REFERENCE_PIN)
        candidate = inspect_support(args.historical_pal6_support, CANDIDATE_PIN)
        comparison = compare_supports(reference, candidate)
        fp8 = verify_fp8(args.fp8_manifest)
        from decoder_trial_patch import patch_repository
        patch, source_hashes = patch_repository(args.repo_root)
        protected = [args.reference_support, args.historical_pal6_support,
                     Path(fp8['source']['path']), Path(fp8['aot']['path'])]
        for root in protected:
            if args.output_dir.resolve().is_relative_to(root.resolve()):
                raise ValueError("Output must not be inside an accepted model artifact")
        args.output_dir.mkdir(parents=True, exist_ok=False)
        if args.stage_support:
            stage_support(candidate, args.output_dir / IDENTITY)
        receipt = {"schema": "mural-pal6-decoder-admission-v1", "status": "static-only",
                   "reference": reference, "candidate": candidate, "comparison": comparison,
                   "fixed_encoder": fp8, "source_hashes_before_patch": source_hashes,
                   "phone_abi_accuracy_speed_memory": "NOT TESTED",
                   "historical_full_pair_result_is_not_decoder_qualification": True}
        (args.output_dir / "admission.json").write_text(json.dumps(receipt, indent=2) + "\n")
        (args.output_dir / "runtime.patch").write_text(patch)
        print("Static admission only. Review runtime.patch, git apply --check, apply, test/build.")
        print("Do not select prewarm=once until the isolated decoder-precision comparison finishes.")
    except (ValueError, OSError, KeyError, TypeError) as exc:
        parser.exit(1, f"Admission failed: {exc}\n")


if __name__ == "__main__":
    main()
