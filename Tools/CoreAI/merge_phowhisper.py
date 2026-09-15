#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "torch>=2.7,<3",
#   "transformers==4.57.3",
#   "peft>=0.17,<1",
#   "accelerate>=1.0",
#   "safetensors>=0.4",
# ]
# ///
"""Merge Mural's pinned PhoWhisper Vietnamese-English LoRA into its Large-v2 base.

Prefer an already-frozen merged checkpoint from the existing Mural benchmark
evidence. Use this script only when that exact merged source is unavailable.
"""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

import torch
from peft import PeftModel
from transformers import AutoModelForSpeechSeq2Seq, AutoProcessor

DEFAULT_BASE = "vinai/PhoWhisper-large"
DEFAULT_BASE_REVISION = "b9136a44b5f2ca664bd0b8f74baecf1715f6eeeb"
DEFAULT_ADAPTER = "rinhoooo/phowhisper-large-vien-cs-asr"
DEFAULT_ADAPTER_REVISION = "a98f55e0f42b2c4f1e71b3348a2b917fac0a7328"


def source_kwargs(source: str, revision: str | None, local_files_only: bool) -> dict:
    path = Path(source).expanduser()
    if path.exists():
        return {"pretrained_model_name_or_path": str(path.resolve()), "local_files_only": True}
    kwargs = {
        "pretrained_model_name_or_path": source,
        "local_files_only": local_files_only,
    }
    if revision:
        kwargs["revision"] = revision
    return kwargs


def validate_config(config) -> None:
    checks = {
        "model_type": getattr(config, "model_type", None),
        "num_mel_bins": getattr(config, "num_mel_bins", None),
        "d_model": getattr(config, "d_model", None),
        "encoder_layers": getattr(config, "encoder_layers", None),
        "decoder_layers": getattr(config, "decoder_layers", None),
        "vocab_size": getattr(config, "vocab_size", None),
    }
    expected = {
        "model_type": "whisper",
        "num_mel_bins": 80,
        "d_model": 1280,
        "encoder_layers": 32,
        "decoder_layers": 32,
        "vocab_size": 51865,
    }
    bad = {k: (checks[k], expected[k]) for k in expected if checks[k] != expected[k]}
    if bad:
        raise RuntimeError(f"Unexpected PhoWhisper/Large-v2 config: {bad}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default=DEFAULT_BASE)
    parser.add_argument("--base-revision", default=DEFAULT_BASE_REVISION)
    parser.add_argument("--adapter", default=DEFAULT_ADAPTER)
    parser.add_argument("--adapter-revision", default=DEFAULT_ADAPTER_REVISION)
    parser.add_argument("--output", required=True, help="Destination Hugging Face model directory")
    parser.add_argument("--local-files-only", action="store_true",
                        help="Fail instead of downloading missing Hugging Face files")
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()

    output = Path(args.output).expanduser().resolve()
    if output.exists():
        if not args.overwrite:
            raise FileExistsError(f"{output} exists; pass --overwrite to replace it")
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)

    base_kwargs = source_kwargs(args.base, args.base_revision, args.local_files_only)
    base = AutoModelForSpeechSeq2Seq.from_pretrained(
        **base_kwargs,
        torch_dtype=torch.float16,
        low_cpu_mem_usage=True,
        use_safetensors=True,
    )
    validate_config(base.config)

    adapter_path = Path(args.adapter).expanduser()
    adapter_source = str(adapter_path.resolve()) if adapter_path.exists() else args.adapter
    adapter_kwargs = {"local_files_only": True} if adapter_path.exists() else {
        "revision": args.adapter_revision,
        "local_files_only": args.local_files_only,
    }
    peft_model = PeftModel.from_pretrained(base, adapter_source, **adapter_kwargs)
    merged = peft_model.merge_and_unload()
    merged.eval()
    validate_config(merged.config)

    merged.save_pretrained(output, safe_serialization=True, max_shard_size="4GB")
    if getattr(merged, "generation_config", None) is not None:
        merged.generation_config.save_pretrained(output)

    processor_kwargs = source_kwargs(args.base, args.base_revision, args.local_files_only)
    processor = AutoProcessor.from_pretrained(**processor_kwargs)
    processor.save_pretrained(output)

    feature_size = getattr(processor.feature_extractor, "feature_size", None)
    if feature_size != 80:
        raise RuntimeError(f"Expected 80 mel bins from PhoWhisper processor, got {feature_size}")

    manifest = {
        "purpose": "Mural Core AI source freeze",
        "base": args.base,
        "base_revision": args.base_revision,
        "adapter": args.adapter,
        "adapter_revision": args.adapter_revision,
        "dtype": "float16",
        "expected_model": "phowhisper-cs-fp16-v1",
        "config": {
            "num_mel_bins": merged.config.num_mel_bins,
            "d_model": merged.config.d_model,
            "encoder_layers": merged.config.encoder_layers,
            "decoder_layers": merged.config.decoder_layers,
            "vocab_size": merged.config.vocab_size,
        },
        "files": {
            p.name: p.stat().st_size
            for p in sorted(output.iterdir())
            if p.is_file()
        },
    }
    (output / "mural_source_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"Merged source written to {output}")
    print("Run the frozen Mural ASR corpus against this source before Core AI export.")


if __name__ == "__main__":
    main()
