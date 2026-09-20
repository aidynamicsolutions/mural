#!/usr/bin/env python3
"""Package an already exported/compiled, locally reviewed PAL8 Breeze candidate.

This does NOT convert models or prove that weights are PAL8. The Mac agent must
inspect the conversion before packaging. The source revision is caller-supplied;
file hashes record bytes, not an independent attestation of their publisher.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile

from evaluate import read_json, sha256

IDENTITY = "breeze-asr25-pal8-v1"
MODEL = "MediaTek-Research/Breeze-ASR-25"
REQUIRED_CONFIG = {"model_type": "whisper", "num_mel_bins": 80, "d_model": 1280,
                   "encoder_layers": 32, "decoder_layers": 32, "vocab_size": 51865}
SUPPORT = ("config.json", "generation_config.json", "preprocessor_config.json", "tokenizer.json", "tokenizer_config.json")
BUNDLES = ("MelSpectrogram", "AudioEncoder", "TextDecoder")
BUNDLE_FILES = ("coremldata.bin", "metadata.json", "model.mil", "weights/weight.bin")


def validate_source(source: Path) -> None:
    config = read_json(source / "config.json")
    if any(config.get(key) != value for key, value in REQUIRED_CONFIG.items()):
        raise ValueError("Source is not the required Whisper-large-v2 contract")
    frontend = read_json(source / "preprocessor_config.json")
    if (frontend.get("sampling_rate"), frontend.get("feature_size"), frontend.get("chunk_length")) != (16000, 80, 30):
        raise ValueError("Source frontend must be 16 kHz, 80 mel bins, 30 seconds")
    generation = read_json(source / "generation_config.json")
    suppressed = generation.get("suppress_tokens")
    if not isinstance(suppressed, list) or not suppressed or any(type(x) is not int or not 0 <= x < 51865 for x in suppressed):
        raise ValueError("Invalid suppression tokens")
    if generation.get("lang_to_id", {}).get("<|zh|>") != 50260 or generation.get("lang_to_id", {}).get("<|en|>") != 50259:
        raise ValueError("Wrong language token contract")
    for name in SUPPORT:
        if not (source / name).is_file():
            raise ValueError(f"Missing source support: {name}")


def package(source: Path, compiled: Path, revision: str, output: Path) -> str:
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Supply the full pinned upstream revision, not main or a short hash")
    if output.exists():
        raise FileExistsError("Output exists; preserve it and use a new directory")
    validate_source(source)
    weights = sorted(source.glob("*.safetensors"))
    if not weights:
        raise ValueError("Keep the pinned source safetensors with its support files for provenance")
    for name in BUNDLES:
        bundle = compiled / f"{name}.mlmodelc"
        if bundle.is_symlink() or not bundle.is_dir():
            raise ValueError(f"Missing compiled bundle: {name}")
        for path in bundle.rglob("*"):
            if path.is_symlink():
                raise ValueError("Compiled bundle contains a symbolic link")
        for relative in BUNDLE_FILES:
            if not (bundle / relative).is_file():
                raise ValueError(f"Incomplete compiled bundle: {name}/{relative}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".breeze-package-", dir=output.parent) as temporary:
        stage = Path(temporary) / IDENTITY
        stage.mkdir()
        # Include the entire local tokenizer, not a stock Whisper or PhoWhisper substitute.
        support = set(SUPPORT) | {path.name for path in source.glob("*.json")}
        support |= {name for name in ("vocab.json", "merges.txt", "normalizer.json", "README.md", "LICENSE", "LICENSE.txt", "NOTICE") if (source / name).is_file()}
        # Weight shard indexes are provenance, not tokenizer assets needed at inference.
        support = {name for name in support if not name.endswith(".index.json")}
        for name in sorted(support):
            shutil.copyfile(source / name, stage / name)
        for name in BUNDLES:
            shutil.copytree(compiled / f"{name}.mlmodelc", stage / f"{name}.mlmodelc")
        files = {str(path.relative_to(stage)): {"bytes": path.stat().st_size, "sha256": sha256(path)}
                 for path in sorted(stage.rglob("*")) if path.is_file()}
        source_files = {path.name: {"bytes": path.stat().st_size, "sha256": sha256(path)} for path in weights}
        manifest = {"schema": "mural.breeze-coreml.v1", "model": MODEL, "revision": revision,
                    "precision": "pal8", "source_weights": source_files, "files": files,
                    "qualification": "unqualified-phone-candidate", "revision_verification": "caller-pinned snapshot; inspect local provenance"}
        data = (json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
        (stage / "manifest.json").write_bytes(data)
        # Rename a newly created bundle only; never mutate accepted artifacts in place.
        if output.exists():
            raise FileExistsError("Output appeared while packaging")
        stage.rename(output)
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--compiled", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        digest = package(args.source, args.compiled, args.revision, args.output)
        print(f"Candidate: {args.output}")
        print(f"Launch argument: --breeze-manifest-sha256={digest}")
        print("Native shape/precision checks and iPhone qualification are still required.")
    except (OSError, ValueError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
