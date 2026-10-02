#!/usr/bin/env python3
"""Resolve, fetch, inspect/package, and arm ONE optional community Breeze PAL4 trial.

No conversion, model inference, app install, public catalog write, or default change.
Network is used ONLY by resolve/fetch; those commands need huggingface_hub.
Every stage uses new paths and refuses overwrite. Native evidence is required to arm.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import tempfile

REPO = "weiren119/Breeze-ASR-25-coreml-4bit-palette"
BASE_MODEL = "MediaTek-Research/Breeze-ASR-25"
BASE_REVISION = "cffe7ccb404d025296a00758d0a33468bec3a9d0"
BASE_MANIFEST = "64021fb776ee2ef4cf02c05b2a9dafde0e0700e9bf7d967b4bc5302558b5fdb4"
BUNDLES = ("MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc")
REMOTE_SUPPORT = ("README.md", "config.json", "generation_config.json", "LICENSE", "LICENSE.txt", "NOTICE")
REQUIRED = ("coremldata.bin", "metadata.json", "model.mil", "weights/weight.bin")
SUPPORT = ("config.json", "generation_config.json", "preprocessor_config.json", "tokenizer.json", "tokenizer_config.json")
TOPOLOGY = {"model_type": "whisper", "num_mel_bins": 80, "d_model": 1280,
            "encoder_layers": 32, "decoder_layers": 32, "vocab_size": 51865}
MAX_BYTES = 2_500_000_000  # reviewed download/storage bound, NOT a runtime memory budget


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def unique(pairs):
    result = {}
    for k, v in pairs:
        require(k not in result, f"Duplicate JSON key: {k}")
        result[k] = v
    return result


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique)


def write(path: Path, data) -> None:
    with path.open("x", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
        f.write("\n")


def sha(path: Path, algorithm="sha256", git_blob=False) -> str:
    h = hashlib.new(algorithm)
    if git_blob:
        h.update(f"blob {path.stat().st_size}\0".encode())
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def valid_path(relative: str) -> bool:
    return (isinstance(relative, str) and bool(relative) and "\\" not in relative
            and not PurePosixPath(relative).is_absolute()
            and all(x not in ("", ".", "..") for x in relative.split("/")))


def local(root: Path, relative: str) -> Path:
    require(valid_path(relative), "Unsafe inventory path")
    require(root.is_dir() and not root.is_symlink(), "Missing or symlinked root")
    p = root
    for part in relative.split("/"):
        p /= part
        require(not p.is_symlink(), "Symlinks are forbidden in staged artifacts")
    require(p.is_file(), f"Missing file: {relative}")
    return p


def entry(path: Path) -> dict:
    return {"bytes": path.stat().st_size, "sha256": sha(path)}


def verify(root: Path, inventory: dict) -> None:
    require(isinstance(inventory, dict) and bool(inventory), "Empty inventory")
    for rel, e in inventory.items():
        p = local(root, rel)
        require(type(e.get("bytes")) is int and e["bytes"] >= 0, f"Invalid size: {rel}")
        require(re.fullmatch(r"[0-9a-f]{64}", e.get("sha256", "")) is not None, f"Invalid hash: {rel}")
        require(p.stat().st_size == e["bytes"] and sha(p) == e["sha256"], f"Size/hash mismatch: {rel}")


def check_lock(lock: dict) -> None:
    require(lock.get("schema") == "mural.breeze-hf-lock.v1" and lock.get("repo") == REPO, "Wrong source lock")
    require(re.fullmatch(r"[0-9a-f]{40}", lock.get("revision", "")) is not None, "Immutable HF revision required")
    files = lock.get("files", {})
    require(0 < len(files) <= 100, "Unexpected source inventory size")
    for rel, e in files.items():
        require(valid_path(rel), "Unsafe source path")
        require(rel.split("/")[0] in BUNDLES or rel in REMOTE_SUPPORT, "Unexpected source file")
        require(type(e.get("bytes")) is int and 0 <= e["bytes"] <= MAX_BYTES, "Invalid source byte count")
        if "sha256" in e:
            require(re.fullmatch(r"[0-9a-f]{64}", e["sha256"]) is not None, "Invalid LFS hash")
        else:
            require(re.fullmatch(r"[0-9a-f]{40}", e.get("git_blob_sha1", "")) is not None, "Missing source content hash")
    require(sum(e["bytes"] for e in files.values()) <= MAX_BYTES, "Candidate exceeds reviewed download bound")
    for b in BUNDLES:
        require(all(f"{b}/{p}" in files for p in REQUIRED), f"Incomplete {b}")


def resolve(revision: str, output: Path) -> dict:
    from huggingface_hub import HfApi
    require(not output.exists(), "Lock output exists")
    # Public requests only; no token, remote code execution or model inference.
    info = HfApi(token=False).model_info(REPO, revision=revision, files_metadata=True)
    require(re.fullmatch(r"[0-9a-f]{40}", info.sha or "") is not None, "HF did not resolve an immutable revision")
    frozen = HfApi(token=False).model_info(REPO, revision=info.sha, files_metadata=True)
    require(frozen.sha == info.sha, "HF immutable revision mismatch")
    files = {}
    for item in frozen.siblings:
        rel = item.rfilename
        if rel.split("/")[0] not in BUNDLES and rel not in REMOTE_SUPPORT:
            continue
        require(item.size is not None, f"Missing remote size: {rel}")
        e = {"bytes": item.size}
        if item.lfs:
            e["sha256"] = item.lfs.sha256
        else:
            e["git_blob_sha1"] = item.blob_id
        files[rel] = e
    lock = {"schema": "mural.breeze-hf-lock.v1", "repo": REPO, "revision": info.sha,
            "files": files, "license_claim": "apache-2.0; review actual notices",
            "lineage": "Publisher claims Breeze-ASR-25; exact pre-quantization checkpoint not independently established"}
    check_lock(lock)
    write(output, lock)
    return {"lock_sha256": sha(output), "source_bytes": sum(e["bytes"] for e in files.values()), "revision": info.sha}


def fetch(lock_path: Path, lock_sha256: str, output: Path) -> dict:
    from huggingface_hub import hf_hub_download
    require(sha(lock_path) == lock_sha256, "Source lock pin mismatch")
    lock = read(lock_path); check_lock(lock)
    require(not output.exists(), "Fetch output exists; preserve it")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".breeze-download-", dir=output.parent) as tmp:
        stage = Path(tmp) / "snapshot"; stage.mkdir()
        for rel, e in lock["files"].items():
            # Hub cache symlinks are materialized into regular files before verification.
            downloaded = Path(hf_hub_download(repo_id=REPO, revision=lock["revision"], filename=rel, token=False))
            dest = stage / rel; dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(downloaded, dest)
            require(dest.stat().st_size == e["bytes"], f"Download size mismatch: {rel}")
            key = "sha256" if "sha256" in e else "git_blob_sha1"
            digest = sha(dest) if key == "sha256" else sha(dest, "sha1", git_blob=True)
            require(digest == e[key], f"Download content mismatch: {rel}")
        write(stage / "source-lock.json", lock)
        require(not output.exists(), "Fetch destination appeared")
        stage.rename(output)
    return {"snapshot": str(output), "source_bytes": sum(e["bytes"] for e in lock["files"].values()),
            "network_bytes": None, "note": "Source bytes are not measured wire transfer; Hub may reuse its cache."}


def metadata(root: Path, bundle: str) -> dict:
    value = read(local(root, f"{bundle}/metadata.json"))
    if isinstance(value, list):
        require(len(value) == 1, f"Unexpected metadata functions: {bundle}")
        value = value[0]
    require(isinstance(value, dict), "Invalid compiled metadata")
    return value


def signature(meta: dict, field: str) -> dict:
    rows = meta.get(field)
    require(isinstance(rows, list) and bool(rows), f"Missing {field}")
    result = {}
    for row in rows:
        require(row.get("name") not in result and isinstance(row.get("name"), str), "Duplicate/invalid tensor name")
        shape = row.get("shape")
        if isinstance(shape, str):
            shape = json.loads(shape)
        require(isinstance(shape, list) and bool(shape), "Static tensor shape required for automatic qualification")
        result[row["name"]] = {"shape": shape, "dataType": row.get("dataType"),
                               "type": row.get("type"), "isOptional": str(row.get("isOptional", "0")),
                               "hasShapeFlexibility": str(row.get("hasShapeFlexibility", "0"))}
    return result


def inspect_package(baseline: Path, snapshot: Path, lock_path: Path, output: Path) -> dict:
    require(not output.exists(), "Package output exists; preserve it")
    lock = read(lock_path); check_lock(lock)
    # Verify all pinned downloaded files without trusting a snapshot-created manifest.
    for rel, e in lock["files"].items():
        p = local(snapshot, rel)
        digest = sha(p) if "sha256" in e else sha(p, "sha1", git_blob=True)
        require(p.stat().st_size == e["bytes"] and digest == e.get("sha256", e.get("git_blob_sha1")), f"Source drift: {rel}")
    base_manifest_path = local(baseline, "manifest.json")
    require(sha(base_manifest_path) == BASE_MANIFEST, "Baseline is not the independently pinned production PAL8")
    base = read(base_manifest_path)
    require(base.get("revision") == BASE_REVISION and base.get("precision") == "pal8", "Wrong baseline contract")
    verify(baseline, base["files"])
    require(all(n in base["files"] for n in SUPPORT), "Baseline tokenizer/support missing")
    config = read(baseline / "config.json")
    require(all(config.get(k) == v for k, v in TOPOLOGY.items()), "Wrong baseline topology")
    if "config.json" in lock["files"]:
        remote = read(snapshot / "config.json")
        require(all(remote.get(k) == v for k, v in TOPOLOGY.items()), "Publisher config is incompatible")
    inspection = {}
    for b in BUNDLES:
        original, candidate = metadata(baseline, b), metadata(snapshot, b)
        for field in ("inputSchema", "outputSchema"):
            require(signature(original, field) == signature(candidate, field), f"Tensor/cache contract differs: {b}/{field}; native adapter review required")
        precision = str(candidate.get("storagePrecision", ""))
        mil = local(snapshot, f"{b}/model.mil").read_text(encoding="utf-8")
        lut_count = len(re.findall(r"constexpr_?lut_?to_?dense", mil, re.I))
        if b != BUNDLES[0]:
            require(re.search(r"Palettized\s*\(4\s*bits\)", precision, re.I) is not None, f"No PAL4 metadata declaration: {b}")
            require(lut_count > 0, f"No visible LUT-to-dense ops: {b}")
        inspection[b] = {"declared_storage_precision": precision, "lut_ops_in_mil": lut_count,
                         "io_matches_baseline": True,
                         "independent_bitpacking_and_native_validation": "REQUIRES_LOCAL_REVIEW"}
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".breeze-pal4-", dir=output.parent) as tmp:
        stage = Path(tmp) / "package"; stage.mkdir()
        # Keep baseline lexical BPE, decoding config and notices byte-identical.
        for rel in base["files"]:
            if rel.split("/")[0] in BUNDLES:
                continue
            src = local(baseline, rel); dest = stage / rel
            dest.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(src, dest)
        for rel in lock["files"]:
            if rel.split("/")[0] in BUNDLES:
                dest = stage / rel; dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(local(snapshot, rel), dest)
        for name in ("README.md", "LICENSE", "LICENSE.txt", "NOTICE"):
            if name in lock["files"]:
                shutil.copyfile(snapshot / name, stage / ("community-export-" + name))
        inventory = {p.relative_to(stage).as_posix(): entry(p) for p in sorted(stage.rglob("*")) if p.is_file()}
        manifest = {"schema": "mural.breeze-coreml.trial.v1", "model": BASE_MODEL,
                    "revision": lock["revision"], "precision": "pal4", "files": inventory,
                    "export_repository": REPO, "export_lock_sha256": sha(lock_path),
                    "support_revision": BASE_REVISION, "support_manifest_sha256": BASE_MANIFEST,
                    "lineage_caveat": lock["lineage"], "qualification": "unqualified-community-export"}
        write(stage / "manifest.json", manifest)
        digest = sha(stage / "manifest.json")
        identity = f"breeze-asr25-weiren-pal4-{lock['revision'][:12]}-{digest[:12]}"
        audit = {"schema": "mural.breeze-pal4-audit.v1", "identity": identity,
                 "manifest_sha256": digest, "revision": lock["revision"], "file_count": len(inventory),
                 "baseline_payload_bytes": sum(e["bytes"] for e in base["files"].values()),
                 "candidate_payload_bytes": sum(e["bytes"] for e in inventory.values()),
                 "per_bundle_bytes": {b: sum(e["bytes"] for n, e in inventory.items() if n.startswith(b + "/")) for b in BUNDLES},
                 "metadata_inspection": inspection, "runtime_ram_bytes": None, "phone_results": None}
        write(stage / "audit.json", audit)
        require(not output.exists(), "Package destination appeared")
        stage.rename(output)
    return audit


def arm(package: Path, review_path: Path, output: Path) -> dict:
    require(not output.exists(), "Pin output exists; do not overwrite a reviewed pin")
    audit_path = local(package, "audit.json")
    audit = read(audit_path); review = read(review_path)
    require(audit.get("schema") == "mural.breeze-pal4-audit.v1", "Wrong audit schema")
    require(review.get("schema") == "mural.breeze-pal4-review.v1" and review.get("audit_sha256") == sha(audit_path), "Review does not bind this audit")
    for field in ("approved_for_device_trial", "io_and_cache_contract_reviewed", "pal4_bitpacking_reviewed",
                  "license_and_lineage_caveat_reviewed", "native_mac_load_and_transcribe_passed"):
        require(review.get(field) is True, f"Required review is incomplete: {field}")
    require(isinstance(review.get("reviewer"), str) and bool(review["reviewer"].strip()), "Missing reviewer")
    # Evidence must exist and be independently preserved; booleans alone are insufficient.
    evidence = local(review_path.parent, review.get("native_evidence_file", ""))
    require(evidence.stat().st_size > 0 and sha(evidence) == review.get("native_evidence_sha256"), "Missing/changed native Mac evidence")
    manifest_path = local(package, "manifest.json")
    require(sha(manifest_path) == audit.get("manifest_sha256"), "Packaged manifest changed")
    m = read(manifest_path); verify(package, m["files"])
    require(m.get("schema") == "mural.breeze-coreml.trial.v1" and m.get("precision") == "pal4", "Wrong candidate schema/precision")
    require(m.get("export_repository") == REPO and m.get("support_manifest_sha256") == BASE_MANIFEST, "Wrong candidate provenance")
    revision = m.get("revision", "")
    require(re.fullmatch(r"[0-9a-f]{40}", revision) is not None and revision == audit.get("revision"), "Invalid candidate revision")
    require(audit.get("file_count") == len(m["files"]) and len(m["files"]) >= 17, "Invalid file count")
    expected_id = f"breeze-asr25-weiren-pal4-{revision[:12]}-{audit['manifest_sha256'][:12]}"
    require(audit.get("identity") == expected_id, "Candidate directory identity mismatch")
    source = ("// Locally reviewed community-export pin; not a production promotion.\n"
              f"// Review SHA256: {sha(review_path)}\n"
              "enum BreezePAL4TrialPin {\n"
              f'    static let identity = "{expected_id}"\n'
              f'    static let manifestSHA256 = "{audit["manifest_sha256"]}"\n'
              f'    static let revision = "{revision}"\n'
              f'    static let fileCount = {len(m["files"])}\n' + "}\n")
    with output.open("x", encoding="utf-8") as f:
        f.write(source)
    return {"pin": str(output), "identity": expected_id,
            "next": "Review/copy this pin into App/BreezePAL4TrialPin.swift; regenerate and native-build the trial only."}


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="command", required=True)
    r = sub.add_parser("resolve"); r.add_argument("--revision", default="main"); r.add_argument("--output", required=True, type=Path)
    f = sub.add_parser("fetch"); f.add_argument("--lock", required=True, type=Path); f.add_argument("--lock-sha256", required=True); f.add_argument("--output", required=True, type=Path)
    i = sub.add_parser("package"); i.add_argument("--baseline", required=True, type=Path); i.add_argument("--snapshot", required=True, type=Path); i.add_argument("--lock", required=True, type=Path); i.add_argument("--output", required=True, type=Path)
    a = sub.add_parser("arm"); a.add_argument("--package", required=True, type=Path); a.add_argument("--review", required=True, type=Path); a.add_argument("--output", required=True, type=Path)
    args = p.parse_args()
    try:
        os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")
        if args.command == "resolve": result = resolve(args.revision, args.output)
        elif args.command == "fetch": result = fetch(args.lock, args.lock_sha256, args.output)
        elif args.command == "package": result = inspect_package(args.baseline, args.snapshot, args.lock, args.output)
        else: result = arm(args.package, args.review, args.output)
        print(json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False))
    except (OSError, ValueError, ImportError, KeyError, TypeError) as e:
        p.exit(2, f"error: {e}\n")


if __name__ == "__main__":
    main()
