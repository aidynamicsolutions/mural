#!/usr/bin/env python3
"""Fail-closed identity checks for the W8 v2 experiment (no Apple imports).

This audits compiler outputs; it never manufactures or edits a native hash.
Static separation is necessary, not proof of native cache/resource isolation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
from typing import Any

SCHEMA = "mural-w8-identity-v2"
MARKER_WIDTHS = {"fp16": 16, "fp8": 8, "int8": 9}
# The checkpoint did not specify whether this was native bytes or file SHA-256.
# Check both representations but label them separately in each manifest.
BLOCKED_V1_HASH = "14b1d7cc210fb36aee5c885ff13c8256e0daa8e9c9e66d3e75d4f6fee7de0f8f"


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def file_hash(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Expected regular, non-symlink file: {path}")
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def fingerprint(path: Path) -> str:
    """All files, including hidden files, are covered by the new v2 manifest."""
    if path.is_symlink():
        raise ValueError(f"Symlink not allowed: {path}")
    if path.is_file():
        return file_hash(path)
    if not path.is_dir():
        raise ValueError(f"Missing asset: {path}")
    return hashlib.sha256(canonical({p.name: fingerprint(p)
                                    for p in sorted(path.iterdir())})).hexdigest()


def identity(recipe: dict[str, Any]) -> dict[str, Any]:
    kind, precision = recipe.get("kind"), recipe.get("format")
    if kind not in {"tiny", "encoder"} or precision not in MARKER_WIDTHS:
        raise ValueError("Identity requires kind=tiny/encoder and format=fp16/fp8/int8")
    digest = hashlib.sha256(canonical({"schema": SCHEMA, "recipe": recipe})).hexdigest()
    width = MARKER_WIDTHS[precision]
    # Repeating SHA-256 words is not additional entropy. Width is a deliberate,
    # observable ABI distinction; values provide a second diagnostic check.
    words = list(struct.unpack("<8i", bytes.fromhex(digest)))
    return {"schema": SCHEMA, "recipe_sha256": digest,
            "entrypoint": f"mural_{kind}_{precision}_{digest[:20]}",
            "marker_output": f"mural_identity_{precision}",
            "marker_dtype": "int32", "marker_shape": [width],
            "marker_values": [words[i % len(words)] for i in range(width)]}


def check_marker(spec: dict[str, Any], function_name: str, values: list[int]) -> None:
    if function_name != spec["entrypoint"]:
        raise ValueError("Wrong named entrypoint; never fall back to main")
    if len(values) != spec["marker_shape"][0] or any(type(v) is not int for v in values):
        raise ValueError("Wrong marker shape or scalar representation")
    if values != spec["marker_values"]:
        raise ValueError("Wrong model marker; reject hidden states before decoding")


def native_hashes(bundle: Path) -> list[dict[str, Any]]:
    if bundle.is_symlink() or not bundle.is_dir():
        raise ValueError(f"Expected a directory bundle: {bundle}")
    paths = sorted(bundle.glob("*.hash"))
    if len(paths) != 1:
        raise ValueError(f"Expected one root function hash, found {len(paths)} in {bundle}")
    rows = []
    for path in paths:
        sha = file_hash(path)
        if not 0 < path.stat().st_size <= 4096:
            raise ValueError(f"Unexpected compiler hash size: {path}")
        raw = path.read_bytes()
        text = raw.strip()
        # Normalize only known representations. Do not assume a hash algorithm.
        native_hex = (text.decode("ascii").lower() if re.fullmatch(rb"[0-9a-fA-F]{64}", text)
                      else raw.hex())
        rows.append({"file": path.name, "file_sha256": sha, "bytes": len(raw),
                     "native_bytes_hex": native_hex})
    return rows


def bundle_record(path: Path) -> dict[str, Any]:
    return {"path": str(path.resolve()), "fingerprint": fingerprint(path),
            "bytes": sum(p.stat().st_size for p in path.rglob("*") if p.is_file()),
            "native_hashes": native_hashes(path)}


def verify_pair(manifests: list[dict[str, Any]], *, rehash: bool = True) -> dict[str, Any]:
    """Require pair/triple separation. Rehash deployment artifacts, not just JSON."""
    if len(manifests) < 2:
        raise ValueError("At least two independently compiled candidates are required")
    seen_keys: dict[str, str] = {}
    seen_names: set[str] = set()
    seen_formats: set[str] = set()
    controls: set[str] = set()
    kinds: set[str] = set()
    rows = []
    for report in manifests:
        if report.get("schema") != SCHEMA or report.get("status") != "aot-static-only":
            raise ValueError("Candidate lacks a completed v2 static/AOT manifest")
        recipe = report["recipe"]
        if recipe.get("control") != report["control"]:
            raise ValueError("Recipe and control provenance disagree")
        expected = identity(recipe)
        if report["identity"] != expected:
            raise ValueError("Recipe and identity do not match")
        name = expected["entrypoint"]
        if name in seen_names or recipe["format"] in seen_formats:
            raise ValueError("Duplicate entrypoint/format in candidate comparison")
        seen_names.add(name)
        seen_formats.add(recipe["format"])
        kinds.add(recipe["kind"])
        controls.add(hashlib.sha256(canonical(report["control"])).hexdigest())
        asset = report["aot"]
        if rehash and bundle_record(Path(asset["path"])) != asset:
            raise ValueError(f"AOT artifact changed after manifest: {name}")
        hashes = asset["native_hashes"]
        if len(hashes) != 1:
            raise ValueError("Ambiguous native function hash inventory")
        row = hashes[0]
        key = row["native_bytes_hex"]
        if BLOCKED_V1_HASH in {key, row["file_sha256"]}:
            raise ValueError(f"Known aliased v1 identity: {name}")
        if key in seen_keys:
            raise ValueError(f"Native identity collision: {seen_keys[key]} and {name}")
        seen_keys[key] = name
        rows.append({"entrypoint": name, "format": recipe["format"],
                     "aot_fingerprint": asset["fingerprint"], "native_hash": row})
    if len(controls) != 1 or len(kinds) != 1:
        raise ValueError("Mismatched source/exporter/toolchain controls")
    if not {"fp8", "int8"}.issubset(seen_formats):
        raise ValueError("The collision check requires both FP8 and INT8")
    return {"schema": SCHEMA, "status": "static-separation-only",
            "device_cache_isolation": "NOT TESTED", "candidates": rows}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifests", nargs="+", type=Path)
    args = parser.parse_args()
    try:
        result = verify_pair([json.loads(p.read_text()) for p in args.manifests])
    except (ValueError, KeyError, OSError, TypeError) as error:
        parser.exit(1, f"BLOCKED: {error}\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
