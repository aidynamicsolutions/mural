#!/usr/bin/env python3
"""Read-only admission of the historical PAL6/PAL6 pair. Never export or deploy.

Requires both original encoder manifests and their unchanged source/AOT bundles.
A fresh device cache/ABI/numerical gate is mandatory even after static admission.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from prepare_pal6_decoder_trial import (REFERENCE_PIN, CANDIDATE_PIN, FP8_PIN,
    inspect_support, compare_supports, read_json, sha)

START = "374a7b3abecc87c9f5b78959f3ab1e48084e18ae"
COMBINED = "--coreai-w8-v3-combined=pal6-pal6"
ENCODERS = {
    "fp8": {"manifest": FP8_PIN,
        "entrypoint": "mural_v3_encoder_fp8_packed_6ac300f97511fb8879a6",
        "aot_fingerprint": "c5c7d3264c7256fc50c37e4e4a3471ec69c278397f1887cca65b96a6ee796c65",
        "aot_bytes": 640_483_375, "width": 40},
    "pal6": {"manifest": "b3437340b110c14349cd3f12ae0955adb8254fdc277e263907eaa3d96e651966",
        "entrypoint": "mural_v3_encoder_pal6_packed_a520a05387bc6baf4af3",
        "recipe_sha256": "a520a05387bc6baf4af3b8bc87bc001ab2d6fe05bd7e69dc221ef57faf4ebf25",
        "source_fingerprint": "d21cb37056202c34b18591609a10120de675a5dcf708925a7d03435892ccca7a",
        "source_bytes": 483_765_816,
        "source_native": "0624c87450b8bb98f615cac759a46f3796f570c95fe171d8a29e6a7167e91348",
        "aot_fingerprint": "661fedd52988829fd1f1fe7df35eebab80990a6fdfc0f69118d62edf06fb1812",
        "aot_bytes": 1_273_967_904,
        "aot_native": "fabe774c6ce699e317945479355d434e3a4af47610459875d53f9f0b3f0a3b0b",
        "width": 56},
}
FROZEN_WEIGHTS = "264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a"


def verify_encoder(path: Path, precision: str, root: Path | None = None) -> dict:
    pin = ENCODERS[precision]
    if sha(path) != pin["manifest"]:
        raise ValueError(f"Not the historical {precision} manifest; no repinning/rebuild")
    from w8_runtime_identity import audit_reports, bundle_record, validate_spec
    report = read_json(path)
    # Pinned originals may be copied to a new root; never rewrite their paths.
    audit_reports([report], rehash=False, require_triple=False)
    spec = report["identity"]
    validate_spec(spec)
    if (spec["kind"] != "encoder" or spec["format"] != precision or
        spec["transport"] != "packed" or spec["entrypoint"] != pin["entrypoint"] or
        spec["input_shape"] != [1, 80, 3000] or spec["hidden_shape"] != [1, 1500, 1280] or
        spec["challenge_shape"] != [1, pin["width"]]):
        raise ValueError("Wrong historical encoder ABI/identity")
    if precision == "pal6" and spec["recipe_sha256"] != pin["recipe_sha256"]:
        raise ValueError("Wrong historical PAL6 recipe")
    c = report["control"]
    if (c["architecture"] != "h18p" or c["compute"] != "gpu" or
        c["source_weights"] != FROZEN_WEIGHTS or c["kind"] != "encoder" or c["transport"] != "packed"):
        raise ValueError("Wrong source/device/compute control")
    artifacts = {}
    for field in ("source", "aot"):
        expected = report[field]
        original = Path(expected["path"])
        actual_path = (root / ("aot" if field == "aot" else "") / original.name) if root else original
        actual = bundle_record(actual_path)  # Reads bytes; rejects symlinks and hash ambiguity.
        if {k: v for k, v in actual.items() if k != "path"} != {k: v for k, v in expected.items() if k != "path"}:
            raise ValueError(f"Changed {precision} {field}; retain originals and investigate")
        for key, value in (("fingerprint", pin.get(field + "_fingerprint")), ("bytes", pin.get(field + "_bytes"))):
            if value is not None and actual[key] != value:
                raise ValueError(f"Wrong historical {precision} {field} {key}")
        native = actual["native_hashes"][0]["native_bytes_hex"]
        if field + "_native" in pin and native != pin[field + "_native"]:
            raise ValueError(f"Wrong historical PAL6 {field} compiler identity")
        artifacts[field] = actual
    return {"manifest_sha256": pin["manifest"], "identity": spec, "control": c, **artifacts}


def storage(reference, candidate, pal8, pal6):
    a = reference["aot"]["bytes"] + pal8["decoder_bytes"]
    b = candidate["aot"]["bytes"] + pal6["decoder_bytes"]
    intermediate = reference["aot"]["bytes"] + pal6["decoder_bytes"]
    return {"scope": "Core AI AOT + used TextDecoder only; excludes equal shared files, unused Core ML encoder, source assets and caches",
            "fp8_pal8_bytes": a, "fp8_pal6_bytes": intermediate, "pal6_pal6_bytes": b,
            "combined_minus_safe_bytes": b-a, "combined_minus_safe_percent": 100*(b/a-1),
            "combined_minus_fp8_pal6_bytes": b-intermediate,
            "physical_footprint_or_speed": "NOT inferred from storage"}


def native_keys(record):
    return {record[field]["native_hashes"][0]["native_bytes_hex"] for field in ("source", "aot")}


def admit(fp8, encoder6, pal8, decoder6):
    for name in ("source_weights", "source_configuration", "kind", "transport", "architecture", "compute", "min_deployment"):
        if fp8["control"].get(name) != encoder6["control"].get(name) or name not in fp8["control"]:
            raise ValueError(f"Encoder control mismatch: {name}")
    if native_keys(fp8) & native_keys(encoder6):
        raise ValueError("Cross-precision compiler identity collision")
    supports = compare_supports(pal8, decoder6)
    supports["ignored_component_reason"] = "Both trials supply Core AI hidden states; neither loads support AudioEncoder.mlmodelc"
    # compare_supports intentionally excludes the unused Core ML encoder.
    return {"schema": "mural-combined-pal6-admission-v1", "status": "static-only-not-device-qualified",
        "encoders": {"fp8": fp8, "pal6": encoder6},
        "supports": {"pal8": pal8, "pal6": decoder6}, "support_comparison": supports,
        "storage": storage(fp8, encoder6, pal8, decoder6),
        "native_current_os_abi_cache_quality": "NOT TESTED",
        "selection": "PAL6 encoder + PAL6 decoder; not FP8/PAL8 promotion"}


def inspect_aot(record):
    from w8_runtime_identity import check_contract
    command = ["xcrun", "coreai-build", "inspect", record["aot"]["path"], "--storage", "--compute", "--ops", "--json"]
    result = subprocess.run(command, check=True, text=True, capture_output=True)
    data = json.loads(result.stdout)
    check_contract(data, record["identity"])
    return {"command": command, "inspection": data, "stderr": result.stderr,
            "scope": "Mac compiler inspection, NOT execution on the current iPhone OS"}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--fp8-manifest", type=Path, required=True)
    p.add_argument("--pal6-manifest", type=Path, required=True)
    p.add_argument("--fp8-root", type=Path)
    p.add_argument("--pal6-root", type=Path)
    p.add_argument("--pal8-support", type=Path, required=True)
    p.add_argument("--pal6-support", type=Path, required=True)
    p.add_argument("--output-dir", type=Path, required=True)
    p.add_argument("--inspect-aot", action="store_true")
    args = p.parse_args()
    try:
        if args.output_dir.exists():
            raise ValueError("Evidence directory already exists; never overwrite/resume")
        # Check this before hashing or writing. No output inside source inputs.
        protected = [args.fp8_manifest.parent, args.pal6_manifest.parent, args.pal8_support, args.pal6_support]
        protected += [r for r in (args.fp8_root, args.pal6_root) if r]
        for root in protected:
            if args.output_dir.resolve().is_relative_to(root.resolve()):
                raise ValueError("Evidence output is inside a protected input")
        fp8 = verify_encoder(args.fp8_manifest, "fp8", args.fp8_root)
        pal6 = verify_encoder(args.pal6_manifest, "pal6", args.pal6_root)
        for encoder in (fp8, pal6):
            for field in ("source", "aot"):
                if args.output_dir.resolve().is_relative_to(Path(encoder[field]["path"]).resolve()):
                    raise ValueError("Evidence output is inside a protected bundle")
        result = admit(fp8, pal6, inspect_support(args.pal8_support, REFERENCE_PIN), inspect_support(args.pal6_support, CANDIDATE_PIN))
        if args.inspect_aot:
            result["aot_inspection"] = {"fp8": inspect_aot(fp8), "pal6": inspect_aot(pal6)}
        args.output_dir.mkdir(parents=True, exist_ok=False)
        (args.output_dir / "admission.json").write_text(json.dumps(result, indent=2, allow_nan=False)+"\n")
        print(json.dumps(result["storage"], indent=2))
        print("Static admission only. Next: current-OS native two-turn gate. No export, deployment, cache deletion or promotion occurred.")
    except (ValueError, OSError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        p.exit(1, f"Combined admission blocked: {error}\n")

if __name__ == "__main__":
    main()
