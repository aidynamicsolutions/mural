#!/usr/bin/env python3
"""Static release gate and size report. Not a substitute for clean-iPhone evidence.

Run from the repository root against the exact archive/export being tested.
Reports archive logical bytes and IPA bytes, NOT App Store thinned download size.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re


def measure(root: Path) -> int:
    return sum(p.stat().st_size for p in root.rglob("*") if p.is_file() and not p.is_symlink())


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--archive", type=Path, required=True)
    p.add_argument("--ipa", type=Path)
    p.add_argument("--package", action="append", type=Path, default=[], help="A generated package.json; pass once for each mode being considered for release")
    args = p.parse_args()
    catalog = Path("Core/SpeechPackageCatalog.swift").read_text()
    blocked = []
    if re.search(r"entries\s*:\s*\[ReviewedSpeechPackage\]\s*=\s*\[\s*\]", catalog):
        blocked.append("No reviewed published package catalog")
    apps = list((args.archive / "Products/Applications").glob("*.app"))
    if len(apps) != 1:
        raise SystemExit("Expected one app in an existing .xcarchive")
    weight_suffixes = {".mlmodelc", ".mlpackage", ".mlmodel", ".aimodel", ".aimodelc", ".safetensors", ".onnx"}
    bundled = [str(f.relative_to(apps[0])) for f in apps[0].rglob("*") if f.suffix in weight_suffixes]
    if bundled:
        blocked.append("Model artifacts found in app binary: review and remove ASR weights; do not waive silently")
    packages = []
    for file in args.package:
        data = file.read_bytes(); manifest = json.loads(data)
        pin = hashlib.sha256(data).hexdigest()
        if pin not in catalog:
            blocked.append(f"Package {manifest['id']} is not pinned in the source catalog")
        packages.append({"id": manifest["id"], "pair": manifest["pair"], "manifest_sha256": pin,
            "download_bytes": sum(x["bytes"] for x in manifest["files"]),
            "installed_package_bytes": len(data) + sum(x["bytes"] for x in manifest["files"]),
            "native_preparation_reserve_bytes": manifest["specializationReserveBytes"]})
    if {x["pair"] for x in packages} != {"vi-en", "zh-TW-en"}:
        blocked.append("Both local modes need separately pinned package measurements before both are releasable")
    report = {"archive_logical_bytes": measure(args.archive), "app_logical_bytes": measure(apps[0]),
        "ipa_file_bytes": args.ipa.stat().st_size if args.ipa else None,
        "app_store_thinned_download_bytes": None, "bundled_model_candidates": bundled,
        "packages": packages, "blocked": blocked,
        "unmeasured_here": ["App Store thinned download", "physical peak installation space", "installed footprint including Apple caches", "clean-install and post-update execution"],
        "qualification": "static check only; physical evidence still required even with no static blockers"}
    print(json.dumps(report, indent=2))
    if blocked:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
