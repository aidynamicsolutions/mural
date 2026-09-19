"""PAL4 encoder experiment contracts. No Apple or Torch imports at module load.

The v3 packet is unchanged except for a new format/name and a 64-value response.
This module never changes the accepted W8 exporter or its immutable manifests.
"""
from __future__ import annotations

from collections import Counter
import hashlib
import json
import math
from pathlib import Path
from typing import Any

SCHEMA = "mural-w8-runtime-identity-v3"
FROZEN_WEIGHTS = "264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a"
FP8_MANIFEST = "73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13"
PAL8_MANIFEST = "430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336"
PINS = {"coreai-core": "1.0.0b2", "coreai-torch": "0.4.1", "coreai-opt": "0.2.1"}
SETTINGS = {
    "n_bits": 4, "method": "kmeans", "granularity": "per_grouped_channel",
    "group_size": 16, "cluster_dim": 1, "lut_dtype": None,
    "expected_lut_storage": "f16", "enable_per_channel_scale": False,
    "weight_num_threshold": 1024, "num_kmeans_workers": 4,
    "enable_fast_kmeans_mode": False, "rounding_precision": 4,
    "activation_quantization": False, "pruning": False, "training": False,
    "seed": 0, "small_vector_retention_limit": 16_384,
}
WEIGHT_CONSUMERS = {"coreai.transpose", "coreai.conv2d"}
CONTROL_FIELDS = ("kind", "transport", "versions", "compiler", "architecture",
                  "min_deployment", "compute", "source_weights", "source_configuration")


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":"), allow_nan=False).encode()


def sha256(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Expected a regular non-symlink file: {path}")
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_pinned(path: Path, expected: str) -> dict[str, Any]:
    if sha256(path) != expected:
        raise ValueError(f"Manifest does not match the retained build pin: {path}")
    return json.loads(path.read_text())


def identity(recipe: dict[str, Any]) -> dict[str, Any]:
    if (recipe.get("kind"), recipe.get("format"), recipe.get("transport")) != (
            "encoder", "pal4", "packed"):
        raise ValueError("Only an encoder PAL4 packed-v3 experiment is supported")
    from w8_runtime_identity import identity as v3_identity
    return v3_identity(recipe)


# Reuse the qualified transport, including validation-before-handoff, verbatim.
from w8_runtime_identity import build_wrapper, unpack_host, check_contract


def challenge(seed: int) -> list[int]:
    if type(seed) is not int or not 0 <= seed <= 31:
        raise ValueError("Challenge seed must be an integer in 0...31")
    return [(seed + i * 13) % 32 for i in range(64)]


def tensor_key(row: dict[str, Any]) -> str:
    return hashlib.sha256(canonical({k: row[k] for k in ("shape", "dtype", "location")})).hexdigest()


def snapshot(program: Any, entrypoint: str) -> dict[str, Any]:
    """Read public IR operations/types/locations; never modify native hashes.

    Audit every floating constant, not just known matmul consumers. Unclassified
    large constants require an explicit retained-tensor explanation too. A new
    IR spelling or ambiguous location fails closed rather than hiding coverage.
    """
    root = program.get_graph(entrypoint).operation
    while root.parent is not None:
        root = root.parent
    root.verify()
    constants, palettes, ops = [], [], Counter()

    def tensor(value):
        shape = list(value.type.shape)
        if any(type(n) is not int or n <= 0 for n in shape):
            raise ValueError(f"Unexpected constant tensor shape: {shape}")
        return {"shape": shape, "dtype": str(value.type.element_type), "elements": math.prod(shape)}

    def visit(op):
        ops[op.name] += 1
        if op.name == "coreai.constant" and len(op.results) == 1:
            row = tensor(op.results[0])
            row.update(location=str(op.location), consumers=sorted({u.owner.name for u in op.results[0].uses}))
            row["key"] = tensor_key(row)
            constants.append(row)
        elif op.name == "coreai.lut_to_dense":
            if len(op.operands) != 3 or len(op.results) != 1:
                raise ValueError("Unreviewed lut_to_dense operand/result contract")
            row = tensor(op.results[0])
            row.update(location=str(op.location), indices=tensor(op.operands[0]), lut=tensor(op.operands[1]))
            row["key"] = tensor_key(row)
            # A type string is stable across serialization; an SSA operation
            # rendering can change IDs despite an identical saved graph.
            row["axis_operand_type"] = str(op.operands[2].type)
            palettes.append(row)
        for region in op.regions:
            for block in region.blocks:
                for child in block.operations:
                    visit(child.operation)
    visit(root)
    return {"operations": dict(ops), "constants": constants, "palettes": palettes}


def coverage(before: dict[str, Any], after: dict[str, Any],
             exceptions: dict[str, str] | None = None) -> dict[str, Any]:
    """Exact tensor correspondence, explicit skips, logical bytes (not RAM)."""
    exceptions = exceptions or {}
    threshold = SETTINGS["weight_num_threshold"]
    def validate_row(row, *, keyed=True):
        shape = row["shape"]
        if (any(type(n) is not int or n <= 0 for n in shape)
                or type(row["elements"]) is not int or row["elements"] != math.prod(shape)
                or (keyed and row["key"] != tensor_key(row))):
            raise ValueError("Inconsistent tensor audit shape/count/key")
    for row in before["constants"] + after["constants"] + after["palettes"]:
        validate_row(row)
    for row in after["palettes"]:
        validate_row(row["indices"], keyed=False)
        validate_row(row["lut"], keyed=False)
    candidates = [r for r in before["constants"] if r["dtype"] in {"f16", "f32"} and r["elements"] > threshold]
    small = [r for r in before["constants"] if r["dtype"] in {"f16", "f32"} and r["elements"] <= threshold]
    weight_candidates = [
        r for r in candidates
        if len(r["shape"]) >= 2 and r["consumers"]
        and set(r["consumers"]) <= WEIGHT_CONSUMERS
    ]
    if before["palettes"] or before["operations"].get("coreai.blockwise_shift_scale", 0):
        raise ValueError("Input already compressed; do not palettize FP8 weights")
    if not candidates:
        raise ValueError("No large source constants found")
    if not weight_candidates:
        raise ValueError("No direct matrix weight constants found")
    keys = [r["key"] for r in candidates]
    if len(keys) != len(set(keys)):
        raise ValueError("Ambiguous source tensor locations; improve audit mapping, not the coverage gate")
    by_key = {r["key"]: r for r in candidates}
    palettes = after["palettes"]
    palette_keys = [r["key"] for r in palettes]
    if len(palette_keys) != len(set(palette_keys)):
        raise ValueError("Duplicate compressed tensor audit locations")
    if len(palettes) != len(weight_candidates):
        raise ValueError("PAL4 palette count does not match direct matrix weight constants")
    if after["operations"].get("coreai.blockwise_shift_scale", 0):
        raise ValueError("Unexpected scale/LUT quantization in scalar PAL4 recipe")
    # Core AI rewrites the constants and gives lut_to_dense fresh operation
    # locations, so its result key cannot identify the source constant. The
    # exporter preserves direct matrix-weight traversal order; require the
    # complete ordered shape correspondence instead of guessing by key.
    compressed = []
    compressed_source_keys = []
    for source, row in zip(weight_candidates, palettes):
        indices, lut = row["indices"], row["lut"]
        possible_groups = {n // 16 for n in row["shape"] if n % 16 == 0}
        if (row["shape"] != source["shape"] or indices["shape"] != source["shape"]
                or row["dtype"] != "f16" or indices["dtype"] != "ui4"
                or indices["elements"] != source["elements"] or lut["dtype"] != "f16"
                or lut["shape"][-2:] != [16, 1]
                or lut["elements"] // 16 not in possible_groups
                or lut["elements"] % 16):
            raise ValueError("Ambiguous/unmatched PAL4 source weight mapping")
        compressed_source_keys.append(source["key"])
        compressed.append({**row, "source_key": source["key"],
                           "source_location": source["location"],
                           "source_consumers": source["consumers"],
                           "source_precision_bytes": source["elements"] * 2,
                           "logical_index_bytes": (indices["elements"] * 4 + 7) // 8,
                           "logical_lut_bytes": lut["elements"] * 2})
    compressed_set = set(compressed_source_keys)
    skipped = set(keys) - compressed_set
    # Retained constants also receive fresh locations. Exclude the new LUT
    # constants, then require an exact shape/dtype/consumer multiset before
    # pairing each retained source row with its rewritten dense row.
    def signature(row):
        return (tuple(row["shape"]), row["dtype"], tuple(row["consumers"]))

    retained_sources = [r for r in candidates if r["key"] in skipped]
    retained_after = [
        r for r in after["constants"]
        if r["dtype"] in {"f16", "f32"}
        and r["elements"] > threshold
        and "coreai.lut_to_dense" not in r["consumers"]
    ]
    if Counter(signature(r) for r in retained_sources) != Counter(signature(r) for r in retained_after):
        raise ValueError("Retained source constants changed without an exact dense mapping")
    available = {}
    for row in retained_after:
        available.setdefault(signature(row), []).append(row)
    remaining = {}
    for source in retained_sources:
        rows = available[signature(source)]
        remaining[source["key"]] = rows.pop(0)
    if compressed_set & set(remaining):
        raise ValueError("Compressed weight also retained densely")
    if skipped != set(remaining):
        raise ValueError("Source constants disappeared without a mapped PAL4 replacement")
    # Small affine/normalization vectors are reported, not mistaken for silently
    # skipped matrix weights. Every larger or rank-2+ skip still needs review.
    small_vectors = {key for key in skipped if len(by_key[key]["shape"]) <= 1
                     and by_key[key]["elements"] <= SETTINGS["small_vector_retention_limit"]}
    if set(exceptions) != skipped - small_vectors or any(not isinstance(v, str) or len(v.strip()) < 12 for v in exceptions.values()):
        raise ValueError("Unexplained/stale retained-tensor exceptions; inspect audit-before/after.json and supply exact keys/reasons")
    retained = []
    for key in sorted(skipped):
        source, row = by_key[key], remaining[key]
        retained.append({**row, "source_key": key, "source_location": source["location"],
                         "source_consumers": source["consumers"],
                         "reason": ("Small rank-1 constant retained at source precision; not a matrix-weight exception"
                                    if key in small_vectors else exceptions[key])})
    if not compressed:
        raise ValueError("No tensors were actually palettized")
    return {
        "status": "pass", "eligible_or_review_required": candidates,
        "compressed": compressed, "retained": retained, "below_threshold": small,
        "source_elements": sum(r["elements"] for r in candidates),
        "compressed_elements": sum(r["elements"] for r in compressed),
        "source_precision_bytes_represented": sum(r["source_precision_bytes"] for r in compressed),
        "logical_index_bytes": sum(r["logical_index_bytes"] for r in compressed),
        "logical_lut_bytes": sum(r["logical_lut_bytes"] for r in compressed),
        "retained_precision_bytes": sum(r["elements"] * (2 if r["dtype"] == "f16" else 4) for r in retained),
        "byte_scope": "Logical tensor payload only; not serialized/AOT bytes or measured memory",
    }


def validate_pair(reference: dict[str, Any], candidate: dict[str, Any], *, rehash: bool = True) -> None:
    """Allow new exporter hashes, NEVER silently relax source/runtime controls."""
    from w8_runtime_identity import audit_reports, bundle_record, BLOCKED_V1
    audit_reports([reference], rehash=rehash, require_triple=False)
    if reference["identity"]["format"] != "fp8" or reference["identity"]["kind"] != "encoder":
        raise ValueError("Control is not the retained FP8 full encoder")
    if (candidate.get("schema") != SCHEMA or candidate.get("status") != "aot-static-only"
            or candidate.get("identity") != identity(candidate["recipe"])
            or candidate["recipe"]["control"] != candidate["control"]
            or candidate["recipe"].get("palettization") != SETTINGS
            or candidate["recipe"].get("reference_manifest_sha256") != FP8_MANIFEST
            or candidate["recipe"].get("decoder_manifest_sha256") != PAL8_MANIFEST
            or candidate["control"].get("source_weights") != FROZEN_WEIGHTS
            or candidate.get("coverage", {}).get("status") != "pass"):
        raise ValueError("PAL4 manifest contract/coverage is incomplete")
    recomputed = coverage(candidate["audit_before"], candidate["audit_after"], candidate["recipe"].get("retained_exceptions"))
    if recomputed != candidate["coverage"]:
        raise ValueError("PAL4 coverage summary does not match tensor evidence")
    for field in CONTROL_FIELDS:
        if field not in reference["control"] or candidate["control"].get(field) != reference["control"][field]:
            raise ValueError(f"Unmatched reference control: {field}")
    for field in ("source", "aot"):
        artifact = candidate[field]
        if rehash and bundle_record(Path(artifact["path"])) != artifact:
            raise ValueError(f"Changed PAL4 {field} artifact")
        rows = artifact["native_hashes"]
        if len(rows) != 1:
            raise ValueError("Ambiguous PAL4 compiler identity")
        row = rows[0]
        key = row["native_bytes_hex"]
        if (not key or len(key) % 2 or any(c not in "0123456789abcdef" for c in key)
                or BLOCKED_V1 in {key, row["file_sha256"]}
                or key in {r["native_bytes_hex"] for r in reference[field]["native_hashes"]}
                or artifact["fingerprint"] == reference[field]["fingerprint"]):
            raise ValueError(f"Unsafe/colliding PAL4 {field} identity")
