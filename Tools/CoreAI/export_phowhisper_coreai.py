#!/usr/bin/env python3
# Copyright 2026 Apple Inc.
#
# This file is adapted from apple/coreai-models/models/whisper/export.py.
# Use of the adapted portions is governed by the BSD-3-Clause license copied
# next to this script in APPLE_COREAI_MODELS_LICENSE.txt.
#
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "coreai-core==1.0.0b2",
#   "coreai-torch==0.4.1",
#   "transformers==4.57.3",
#   "torch>=2.7,<3",
#   "safetensors>=0.4",
# ]
# ///
"""Export the exact merged Mural PhoWhisper FP16 model to a Core AI .aimodel.

This is intentionally a parity/load-time spike. It keeps the accepted model
weights and Large-v2 80-mel frontend. It does not switch Mural to Large-v3.
"""

from __future__ import annotations

import argparse
import json
import shutil
import time
from pathlib import Path

import numpy as np
import torch
import transformers
from coreai.runtime import AIModelAssetMetadata
from coreai_torch import TorchConverter, get_decomp_table


class WhisperModule(torch.nn.Module):
    def __init__(self, model_dir: Path, dtype: torch.dtype):
        super().__init__()
        self.model = transformers.AutoModelForSpeechSeq2Seq.from_pretrained(
            str(model_dir),
            torch_dtype=dtype,
            use_safetensors=True,
            local_files_only=True,
            low_cpu_mem_usage=True,
        )
        self.model.eval()

    def forward(self, input_features, decoder_input_ids):
        return self.model(
            input_features=input_features,
            decoder_input_ids=decoder_input_ids,
        ).logits


def directory_size(path: Path) -> int:
    return sum(p.stat().st_size for p in path.rglob("*") if p.is_file())


def validate_model(model, processor) -> None:
    config = model.model.config
    expected = {
        "model_type": "whisper",
        "num_mel_bins": 80,
        "d_model": 1280,
        "encoder_layers": 32,
        "decoder_layers": 32,
        "vocab_size": 51865,
    }
    actual = {key: getattr(config, key, None) for key in expected}
    bad = {key: (actual[key], expected[key]) for key in expected if actual[key] != expected[key]}
    if bad:
        raise RuntimeError(
            "Refusing to export a model that is not the expected PhoWhisper/Large-v2 shape: "
            + repr(bad)
        )
    feature_size = getattr(processor.feature_extractor, "feature_size", None)
    if feature_size != 80:
        raise RuntimeError(f"Expected an 80-mel processor, got {feature_size}")


def reference_inputs(model_dir: Path, dtype: torch.dtype):
    processor = transformers.AutoProcessor.from_pretrained(
        str(model_dir), local_files_only=True
    )
    # Deterministic 5 s signal. Whisper pads/trims the feature tensor to 30 s.
    t = np.arange(16_000 * 5, dtype=np.float32) / 16_000.0
    dummy_audio = (0.02 * np.sin(2 * np.pi * 440.0 * t)).astype(np.float32)
    feature = processor.feature_extractor(
        dummy_audio, sampling_rate=16_000, return_tensors="pt"
    )
    input_features = feature["input_features"].to(dtype)
    if list(input_features.shape) != [1, 80, 3000]:
        raise RuntimeError(
            f"Expected PhoWhisper [1, 80, 3000] input features, got {list(input_features.shape)}"
        )

    # PhoWhisper/Large-v2 control tokens currently accepted by Mural:
    # <|startoftranscript|>, <|en|>, <|transcribe|>, <|notimestamps|>.
    decoder_input_ids = torch.tensor(
        [[50258, 50259, 50359, 50363]], dtype=torch.int32
    )
    return processor, {
        "input_features": input_features,
        "decoder_input_ids": decoder_input_ids,
    }


def metadata() -> AIModelAssetMetadata:
    result = AIModelAssetMetadata()
    result.author = "Mural contributors; model lineage VinAI/OpenAI"
    result.license = "See source model and adapter licenses"
    result.model_description = (
        "Mural phowhisper-cs-fp16-v1: PhoWhisper Large-v2 lineage with the "
        "Vietnamese-English code-switch LoRA merged, exported without changing weights."
    )
    result.creation_date = int(time.time())
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", required=True,
                        help="Local frozen merged Hugging Face checkpoint")
    parser.add_argument("--output-dir", default=".build/coreai/export")
    parser.add_argument("--name", default="phowhisper-cs-fp16-v1")
    parser.add_argument("--dtype", choices=["float16", "float32"], default="float16")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--include-debug-info", action="store_true")
    parser.add_argument("--skip-optimize", action="store_true",
                        help="Diagnostic escape hatch only; normal export should optimize")
    args = parser.parse_args()

    model_dir = Path(args.model_dir).expanduser().resolve()
    if not model_dir.exists():
        raise FileNotFoundError(model_dir)
    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    model_path = output_dir / f"{args.name}.aimodel"

    if model_path.exists():
        if not args.overwrite:
            raise FileExistsError(f"{model_path} exists; pass --overwrite to replace it")
        if model_path.is_dir():
            shutil.rmtree(model_path)
        else:
            model_path.unlink()

    dtype = torch.float16 if args.dtype == "float16" else torch.float32
    print("[1/6] Loading frozen PhoWhisper source...")
    wrapped = WhisperModule(model_dir, dtype)
    processor, example = reference_inputs(model_dir, dtype)
    validate_model(wrapped, processor)

    print("[2/6] Verifying eager output shape...")
    with torch.inference_mode():
        eager = wrapped(**example)
    if eager.ndim != 3 or eager.shape[0] != 1 or eager.shape[-1] != 51865:
        raise RuntimeError(f"Unexpected eager logits shape: {list(eager.shape)}")
    if not torch.isfinite(eager).all():
        raise RuntimeError("Non-finite eager logits")

    dynamic_shapes = {
        "input_features": {},
        "decoder_input_ids": {
            1: torch.export.Dim("dec_seq_len", min=1, max=448)
        },
    }
    print("[3/6] torch.export with decompositions...")
    with torch.autocast(device_type="cpu", dtype=dtype):
        exported = torch.export.export(
            wrapped,
            args=(),
            kwargs=example,
            dynamic_shapes=dynamic_shapes,
        )
    exported = exported.run_decompositions(get_decomp_table())

    mode = TorchConverter.Mode.DEBUG if args.include_debug_info else TorchConverter.Mode.RELEASE
    print("[4/6] Converting to Core AI...")
    converter = TorchConverter(mode=mode).add_exported_program(
        exported_program=exported,
        input_names=["input_features", "decoder_input_ids"],
        output_names=["logits"],
    )
    program = converter.to_coreai()

    if not args.skip_optimize:
        print("[5/6] Optimizing Core AI program...")
        program.optimize()
    else:
        print("[5/6] Optimization skipped by explicit diagnostic flag.")

    print(f"[6/6] Saving {model_path}...")
    program.save_asset(model_path, metadata())

    report = {
        "model_name": args.name,
        "dtype": args.dtype,
        "source_dir": str(model_dir),
        "input_features_shape": [1, 80, 3000],
        "decoder_example": [50258, 50259, 50359, 50363],
        "vocab_size": 51865,
        "output_asset": str(model_path),
        "output_bytes": directory_size(model_path),
        "optimized": not args.skip_optimize,
        "debug_info": args.include_debug_info,
    }
    report_path = output_dir / f"{args.name}.export.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    print("Next: run compile_aot.sh, then use Mural's --coreai-load-probe device gate.")


if __name__ == "__main__":
    main()
