#!/usr/bin/env python3
"""W8 v3: runtime-dependent FP16 identity transport and read-only artifact audit.

No Apple dependencies. The challenge/response is an execution diagnostic, not
cryptographic attestation of every weight. Native numerical comparisons remain
mandatory. A successful static audit is NOT a device pass.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
from typing import Any

SCHEMA = "mural-w8-runtime-identity-v3"
# PAL6 has a distinct packet width; existing W8 recipes/identities are unchanged.
WIDTHS = {"fp16": 32, "fp8": 40, "int8": 48, "pal6": 56, "pal4": 64}
BLOCKED_V1 = "14b1d7cc210fb36aee5c885ff13c8256e0daa8e9c9e66d3e75d4f6fee7de0f8f"


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":"), allow_nan=False).encode()


def file_hash(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Expected a regular non-symlink file: {path}")
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def fingerprint(path: Path) -> str:
    if path.is_symlink():
        raise ValueError(f"Symlink in artifact: {path}")
    if path.is_file():
        return file_hash(path)
    if not path.is_dir():
        raise ValueError(f"Missing artifact: {path}")
    return hashlib.sha256(canonical({p.name: fingerprint(p)
                                    for p in sorted(path.iterdir())})).hexdigest()


def bundle_record(path: Path) -> dict[str, Any]:
    digest = fingerprint(path)  # Reject symlinks, including hidden ones, first.
    if not path.is_dir():
        raise ValueError("Expected a directory model bundle")
    hashes = sorted(path.glob("*.hash"))
    if len(hashes) != 1:
        raise ValueError(f"Expected one root function hash: {path}")
    hash_path = hashes[0]
    if not 0 < hash_path.stat().st_size <= 4096:
        raise ValueError("Unexpected compiler hash length")
    raw = hash_path.read_bytes()
    text = raw.strip()
    native = text.decode("ascii").lower() if re.fullmatch(rb"[0-9a-fA-F]{64}", text) else raw.hex()
    return {"path": str(path.resolve()), "fingerprint": digest,
            "bytes": sum(p.stat().st_size for p in path.rglob("*") if p.is_file()),
            "native_hashes": [{"file": hash_path.name, "file_sha256": file_hash(hash_path),
                               "bytes": len(raw), "native_bytes_hex": native}]}


def identity(recipe: dict[str, Any]) -> dict[str, Any]:
    kind, fmt, transport = recipe.get("kind"), recipe.get("format"), recipe.get("transport")
    if kind not in {"tiny", "encoder"} or fmt not in WIDTHS or transport not in {"packed", "split"}:
        raise ValueError("Invalid v3 kind/format/transport")
    digest = hashlib.sha256(canonical({"schema": SCHEMA, "recipe": recipe})).hexdigest()
    width = WIDTHS[fmt]
    # All 32 digest bytes are represented. Repetition is shape separation, not
    # extra entropy. Small integers and challenge+byte <=286 are exact in FP16.
    values = list(bytes.fromhex(digest))
    return {"schema": SCHEMA, "recipe_sha256": digest, "kind": kind,
            "format": fmt, "transport": transport,
            "entrypoint": f"mural_v3_{kind}_{fmt}_{transport}_{digest[:20]}",
            "challenge_input": "identity_challenge", "challenge_shape": [1, width],
            "response_output": "identity_response", "packed_output": "encoded_packet",
            "marker_dtype": "float16", "marker_values": [values[i % 32] for i in range(width)],
            "input_shape": [1, 64] if kind == "tiny" else [1, 80, 3000],
            "hidden_shape": [1, 64] if kind == "tiny" else [1, 1500, 1280]}


def validate_spec(spec: dict[str, Any]) -> None:
    fmt, kind, transport = spec.get("format"), spec.get("kind"), spec.get("transport")
    digest = spec.get("recipe_sha256", "")
    if fmt not in WIDTHS or kind not in {"tiny", "encoder"} or transport not in {"packed", "split"}:
        raise ValueError("Invalid v3 format/kind/transport")
    if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("Invalid recipe digest")
    values = list(bytes.fromhex(digest))
    expected = {"schema": SCHEMA, "recipe_sha256": digest, "kind": kind, "format": fmt,
                "transport": transport, "entrypoint": f"mural_v3_{kind}_{fmt}_{transport}_{digest[:20]}",
                "challenge_input": "identity_challenge", "challenge_shape": [1, WIDTHS[fmt]],
                "response_output": "identity_response", "packed_output": "encoded_packet",
                "marker_dtype": "float16", "marker_values": [values[i % 32] for i in range(WIDTHS[fmt])],
                "input_shape": [1, 64] if kind == "tiny" else [1, 80, 3000],
                "hidden_shape": [1, 64] if kind == "tiny" else [1, 1500, 1280]}
    if spec != expected:
        raise ValueError("Identity ABI or marker does not match its digest")


def challenge(spec: dict[str, Any], seed: int) -> list[int]:
    validate_spec(spec)
    if type(seed) is not int or not 0 <= seed <= 31:
        raise ValueError("Challenge seed must be an integer in 0...31")
    return [(seed + i * 13) % 32 for i in range(spec["challenge_shape"][1])]


def expected_response(spec: dict[str, Any], nonce: list[float]) -> list[float]:
    validate_spec(spec)
    if len(nonce) != len(spec["marker_values"]) or any(
            isinstance(n, bool) or not isinstance(n, (float, int)) or not math.isfinite(n)
            or n != int(n) or not 0 <= n <= 31 for n in nonce):
        raise ValueError("Invalid runtime challenge")
    return [float(n + m) for n, m in zip(nonce, spec["marker_values"])]


def require_response(spec: dict[str, Any], nonce: list[float], actual: list[float]) -> None:
    expected = expected_response(spec, nonce)
    if len(actual) != len(expected) or any(not math.isfinite(v) for v in actual) or actual != expected:
        raise ValueError("Wrong/stale runtime identity response; no hidden states accepted")


def build_wrapper(body: Any, spec: dict[str, Any]) -> Any:
    import torch
    validate_spec(spec)
    packed = spec["transport"] == "packed"

    class RuntimeEncoder(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.body = body
            self.register_buffer("identity_bytes", torch.tensor(
                [spec["marker_values"]], dtype=torch.float16))

        def forward(self, input_features, identity_challenge):
            hidden = self.body(input_features)
            response = identity_challenge + self.identity_bytes
            if packed:
                # One computed FP16 return, not a standalone constant Int32 return.
                # No arithmetic on the original hidden branch; packing adds a copy.
                return torch.cat((hidden.reshape(1, -1), response), dim=1)
            return hidden, response

    return RuntimeEncoder().eval()


def unpack_host(output: Any, spec: dict[str, Any], nonce: list[float]) -> Any:
    import torch
    validate_spec(spec)
    hidden_count = math.prod(spec["hidden_shape"])
    if spec["transport"] == "packed":
        if not isinstance(output, torch.Tensor) or list(output.shape) != [1, hidden_count + len(nonce)]:
            raise ValueError("Wrong packet shape")
        hidden = output[:, :hidden_count].reshape(spec["hidden_shape"])
        response = output[:, hidden_count:]
    else:
        if not isinstance(output, tuple) or len(output) != 2:
            raise ValueError("Wrong split return")
        hidden, response = output
    if list(hidden.shape) != spec["hidden_shape"] or list(response.shape) != spec["challenge_shape"]:
        raise ValueError("Wrong hidden/response shape")
    if hidden.dtype != torch.float16 or response.dtype != torch.float16 or not torch.isfinite(hidden).all():
        raise ValueError("Invalid hidden/response type or values")
    require_response(spec, nonce, response.flatten().float().tolist())
    return hidden


def validate_capture(exported: Any, spec: dict[str, Any]) -> None:
    """Both inputs must survive capture; do not accidentally bake in the nonce."""
    user_inputs = [s.arg.name for s in exported.graph_signature.input_specs if s.kind.name == "USER_INPUT"]
    if user_inputs != ["input_features", "identity_challenge"]:
        raise ValueError(f"Runtime inputs were specialized away: {user_inputs}")


def check_contract(summary: dict[str, Any], spec: dict[str, Any]) -> None:
    validate_spec(spec)
    def array(shape):
        return f"NDArray (Float16, {' × '.join(map(str, shape))})"
    expected_inputs = {"input_features": array(spec["input_shape"]),
                       spec["challenge_input"]: array(spec["challenge_shape"])}
    expected_outputs = ({spec["packed_output"]: array([1, math.prod(spec["hidden_shape"]) + len(spec["marker_values"])])}
                        if spec["transport"] == "packed" else
                        {"encoder_hidden_states": array(spec["hidden_shape"]),
                         spec["response_output"]: array(spec["challenge_shape"])})
    funcs = summary["summary"]["functions"]
    if len(funcs) != 1 or funcs[0]["name"] != spec["entrypoint"]:
        raise ValueError("Compiler dropped/changed the named function")
    for key, expected in (("inputs", expected_inputs), ("outputs", expected_outputs)):
        rows = funcs[0][key]
        if len(rows) != len(expected) or {r["name"]: r["type"] for r in rows} != expected:
            raise ValueError(f"Compiler changed v3 {key}: {rows}")


def audit_reports(reports: list[dict[str, Any]], *, rehash: bool = True,
                  require_triple: bool = True) -> dict[str, Any]:
    if not reports:
        raise ValueError("No manifests")
    controls, formats, native_keys = set(), set(), set()
    for report in reports:
        if report.get("schema") != SCHEMA or report.get("status") != "aot-static-only":
            raise ValueError("Incomplete or old-schema artifact")
        spec = identity(report["recipe"])
        if (report.get("identity") != spec or report["recipe"]["control"] != report["control"]
                or report["control"].get("kind") != spec["kind"]
                or report["control"].get("transport") != spec["transport"]):
            raise ValueError("Inconsistent provenance")
        if spec["format"] in formats:
            raise ValueError("Duplicate candidate format")
        formats.add(spec["format"])
        controls.add(hashlib.sha256(canonical(report["control"])).hexdigest())
        for field in ("source", "aot"):
            asset = report[field]
            if rehash and bundle_record(Path(asset["path"])) != asset:
                raise ValueError(f"Changed {field} artifact")
        rows = report["aot"]["native_hashes"]
        if len(rows) != 1:
            raise ValueError("Ambiguous native function hash")
        row = rows[0]
        key = row["native_bytes_hex"]
        if not isinstance(key, str) or not re.fullmatch(r"[0-9a-f]+", key) or len(key) % 2:
            raise ValueError("Invalid native identity representation")
        if BLOCKED_V1 in {key, row["file_sha256"]} or key in native_keys:
            raise ValueError("Unsafe/colliding AOT identity")
        native_keys.add(key)
    if len(controls) != 1:
        raise ValueError("Mismatched source/toolchain/transport controls")
    if require_triple and formats != {"fp16", "fp8", "int8"}:
        raise ValueError("Isolation audit requires the FP16/FP8/INT8 trio")
    return {"schema": SCHEMA, "status": "static-trio-separated" if require_triple else "static-candidate-only",
            "device_isolation": "NOT TESTED", "formats": sorted(formats)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifests", nargs="+", type=Path)
    parser.add_argument("--candidate-only", action="store_true", help="Allow initial FP16 probe; NOT an isolation pass")
    parser.add_argument("--print-swift-pins", action="store_true")
    args = parser.parse_args()
    try:
        reports = [json.loads(p.read_text()) for p in args.manifests]
        result = audit_reports(reports, require_triple=not args.candidate_only)
        print(json.dumps(result, indent=2))
        if args.print_swift_pins:
            for path, report in zip(args.manifests, reports):
                spec = report["identity"]
                print(f'"{spec["transport"]}:{spec["format"]}": "{file_hash(path)}",')
    except (ValueError, KeyError, OSError, TypeError) as error:
        parser.exit(1, f"Audit failed: {error}\n")


if __name__ == "__main__":
    main()
