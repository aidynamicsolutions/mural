#!/usr/bin/env python3
"""Build an immutable, weight-only ASR distribution directory from reviewed exports.

Does not upload, change application sources, re-export models, or delete inputs.
The printed outer-manifest digest must be reviewed and pinned in SpeechPackageCatalog.
Serve the output at --public-base, anonymously over HTTPS with exact HTTP Range support.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
from urllib.parse import urlparse

BREEZE_REVISION = "cffe7ccb404d025296a00758d0a33468bec3a9d0"
BREEZE_PIN = "64021fb776ee2ef4cf02c05b2a9dafde0e0700e9bf7d967b4bc5302558b5fdb4"
PHO_SUPPORT_PIN = "430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336"
PHO_ENCODER_PIN = "73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13"
CHUNK = 4 * 1024 * 1024

def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")

def sha(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Not a regular file: {path}")
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()

def safe(path: str) -> None:
    if len(path.encode()) > 512 or any(p in ("", ".", "..") or len(p.encode()) > 255 or not re.fullmatch(r"[A-Za-z0-9_.-]+", p) for p in path.split("/")):
        raise ValueError(f"Unsafe path: {path}")

def inventory(root: Path, prefix: str) -> list[dict]:
    if root.is_symlink() or not root.is_dir():
        raise ValueError("Supply a regular reviewed export directory")
    result = []
    for directory, subdirs, names in os.walk(root, followlinks=False):
        for name in subdirs + names:
            path = Path(directory, name)
            if path.is_symlink():
                raise ValueError(f"Symlinks are not distributable: {path}")
        for name in names:
            path = Path(directory, name)
            relative = prefix + "/" + path.relative_to(root).as_posix()
            safe(relative)
            result.append({"path": relative, "bytes": path.stat().st_size, "sha256": sha(path)})
    return sorted(result, key=lambda f: f["path"])

def fingerprint(path: Path) -> str:
    if path.is_symlink():
        raise ValueError("Encoder fingerprint rejects symlinks")
    if path.is_file():
        return sha(path)
    if not path.is_dir():
        raise ValueError("Encoder artifact is missing")
    return hashlib.sha256(canonical({p.name: fingerprint(p) for p in sorted(path.iterdir())})).hexdigest()

def no_duplicates(pairs: list[tuple]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result

def pinned_json(root: Path, pin: str) -> dict:
    manifest = root / "manifest.json"
    if manifest.stat().st_size > 1024 * 1024 or sha(manifest) != pin:
        raise ValueError(f"Reviewed manifest pin mismatch in {root}")
    return json.loads(manifest.read_bytes(), object_pairs_hook=no_duplicates)

def verify_support(root: Path, breeze: bool) -> None:
    value = pinned_json(root, BREEZE_PIN if breeze else PHO_SUPPORT_PIN)
    files = value["files"]
    if breeze and (value["revision"] != BREEZE_REVISION or value["model"] != "MediaTek-Research/Breeze-ASR-25" or value["precision"] != "pal8" or len(files) != 27):
        raise ValueError("Wrong Breeze artifact identity")
    for path, expected in files.items():
        safe(path)
        actual = root / path
        if actual.stat().st_size != expected["bytes"] or sha(actual) != expected["sha256"]:
            raise ValueError(f"Support file mismatch: {path}")
    known = set(files) | {"manifest.json"}
    actual = {f["path"].removeprefix("support/") for f in inventory(root, "support")}
    if actual != known:
        raise ValueError("Export has unreviewed extra files or missing inventoried files")

def verify_encoder(root: Path) -> None:
    value = pinned_json(root, PHO_ENCODER_PIN)
    identity = value["identity"]
    if value["schema"] != "mural-w8-runtime-identity-v3" or value["status"] != "aot-static-only" or identity["format"] != "fp8" or identity["transport"] != "packed" or identity["kind"] != "encoder":
        raise ValueError("Wrong staged encoder identity")
    for role in ("source", "aot"):
        item = value[role]
        path = root / ("aot" if role == "aot" else "") / Path(item["path"]).name
        size = sum(f["bytes"] for f in inventory(path, "asset")) if path.is_dir() else path.stat().st_size
        if size != item["bytes"] or ("fingerprint" in item and fingerprint(path) != item["fingerprint"]):
            raise ValueError(f"Encoder {role} verification failed")

def public_url(value: str) -> str:
    url = urlparse(value)
    if url.scheme != "https" or url.port not in (None, 443) or not url.hostname or url.username or url.password or url.query or url.fragment or url.hostname in ("localhost", "127.0.0.1", "::1"):
        raise argparse.ArgumentTypeError("Use an anonymous public HTTPS directory, without credentials/query/fragment")
    return value.rstrip("/") + "/"

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("breeze", "phowhisper"), required=True)
    parser.add_argument("--id", required=True, help="Unique immutable package version ID")
    parser.add_argument("--support", type=Path, required=True)
    parser.add_argument("--encoder", type=Path)
    parser.add_argument("--revision", required=True, help="Reviewed 40-hex model/source revision")
    parser.add_argument("--specialization-reserve-bytes", type=int, required=True, help="Measured native preparation headroom, not an estimate hidden from the user")
    parser.add_argument("--public-base", type=public_url, required=True, help="Future immutable directory; this script does not upload")
    parser.add_argument("--redirect-host", action="append", default=[], help="Explicit reviewed CDN redirect hostname")
    parser.add_argument("--output", type=Path, required=True, help="New directory outside the input exports")
    args = parser.parse_args()
    safe(args.id)
    if len(args.id) > 80 or "/" in args.id or not re.fullmatch(r"[0-9a-f]{40}", args.revision):
        parser.error("Invalid package ID or revision")
    if not 0 < args.specialization_reserve_bytes <= 100_000_000_000:
        parser.error("Supply a positive measured preparation reserve")
    breeze = args.mode == "breeze"
    if breeze and (args.revision != BREEZE_REVISION or args.encoder is not None):
        parser.error("Breeze requires its exact pinned revision and no PhoWhisper encoder")
    if not breeze and args.encoder is None:
        parser.error("PhoWhisper requires the verified packed FP8 encoder export")
    if args.output.exists():
        parser.error("Output already exists; choose a new path. Nothing was replaced.")
    for source in [args.support] + ([] if breeze else [args.encoder]):
        if source.resolve() in args.output.resolve().parents:
            parser.error("Output must not be inside an input export")
    verify_support(args.support, breeze)
    if not breeze:
        verify_encoder(args.encoder)
    rows = inventory(args.support, "support") + ([] if breeze else inventory(args.encoder, "encoder"))
    rows.sort(key=lambda f: f["path"])
    if len({f["path"].lower() for f in rows}) != len(rows):
        parser.error("Case-insensitive file collision")
    total = sum(f["bytes"] for f in rows)
    if total > 50_000_000_000 or len(rows) > 10_000 or any(f["bytes"] > 20_000_000_000 for f in rows):
        parser.error("Package exceeds runtime bounds")
    manifest = {"schema": 1, "id": args.id, "pair": "zh-TW-en" if breeze else "vi-en",
        "backend": "breezeCoreMLPAL8" if breeze else "phoWhisperCoreAIFP8PAL8",
        "revision": args.revision, "hardware": ["iPhone18,3"], "osMajors": [27],
        "computeUnits": {"mel": "cpuAndGPU", "encoder": "cpuAndNeuralEngine" if breeze else "gpuPreferred", "decoder": "cpuAndNeuralEngine"},
        "specializationReserveBytes": args.specialization_reserve_bytes, "files": rows}
    data = canonical(manifest)
    if len(data) > 1024 * 1024:
        parser.error("Manifest exceeds runtime bounds")
    args.output.mkdir(parents=True)
    shutil.copytree(args.support, args.output / "support", symlinks=True)
    if not breeze:
        shutil.copytree(args.encoder, args.output / "encoder", symlinks=True)
    # Verify the copied bytes as well. Inputs may have changed during a long copy.
    for file in rows:
        target = args.output / file["path"]
        if target.stat().st_size != file["bytes"] or sha(target) != file["sha256"]:
            raise ValueError("Export changed during packaging; output is not publishable")
    copied = inventory(args.output / "support", "support") + ([] if breeze else inventory(args.output / "encoder", "encoder"))
    if sorted(copied, key=lambda f: f["path"]) != rows:
        raise ValueError("Export inventory changed during packaging; output is not publishable")
    (args.output / "package.json").write_bytes(data)
    pin = hashlib.sha256(data).hexdigest()
    hosts = sorted({urlparse(args.public_base).hostname, *args.redirect_host})
    if any(not re.fullmatch(r"[a-z0-9.-]+", host) for host in hosts):
        raise ValueError("Invalid reviewed redirect hostname")
    pair = "taiwanMandarinEnglish" if breeze else "vietnameseEnglish"
    print(f'''// Review before adding to SpeechPackageCatalog.entries; newest version first.
ReviewedSpeechPackage(id: {json.dumps(args.id)}, pair: .{pair},
    manifestURL: URL(string: {json.dumps(args.public_base + "package.json")})!,
    filesURL: URL(string: {json.dumps(args.public_base)})!,
    manifestSHA256: "{pin}", allowedHosts: [{", ".join(json.dumps(h) for h in hosts)}]),''')
    print(json.dumps({"download_bytes": total, "installed_package_bytes": total + len(data),
        "transfer_buffer_bound_bytes": CHUNK, "native_preparation_reserve_bytes": args.specialization_reserve_bytes,
        "manifest_sha256": pin, "status": "packaged locally; hosting, runtime validation and clean-install qualification still required"}, indent=2))

if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError) as error:
        raise SystemExit(f"Package refused: {error}") from error
