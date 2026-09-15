#!/usr/bin/env python3
# Copyright 2026 Apple Inc.
#
# Portions of this file follow the Core AI export pattern from
# apple/coreai-models/models/whisper/export.py and are covered by the
# BSD-3-Clause license in APPLE_COREAI_MODELS_LICENSE.txt.
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
"""Export Mural's exact merged PhoWhisper FP16 model as split Core AI assets.

The encoder is run once per turn. The parity decoder intentionally recomputes
its prefix each token; KV-cache optimization is a later gate after transcript
parity is proven.
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


EXPECTED = {
    "model_type": "whisper",
    "num_mel_bins": 80,
    "d_model": 1280,
    "encoder_layers": 32,
    "decoder_layers": 32,
    "vocab_size": 51865,
}


class EncoderModule(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.encoder = model.model.encoder

    def forward(self, input_features):
        return self.encoder(
            input_features=input_features,
            return_dict=True,
        ).last_hidden_state


class DecoderModule(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.decoder = model.model.decoder
        self.proj_out = model.proj_out

    def forward(self, decoder_input_ids, encoder_hidden_states):
        hidden = self.decoder(
            input_ids=decoder_input_ids,
            encoder_hidden_states=encoder_hidden_states,
            use_cache=False,
            return_dict=True,
        ).last_hidden_state
        return self.proj_out(hidden)


def directory_size(path: Path) -> int:
    return sum(p.stat().st_size for p in path.rglob("*") if p.is_file())


def validate_model(model, processor) -> None:
    config = model.config
    actual = {key: getattr(config, key, None) for key in EXPECTED}
    bad = {key: (actual[key], expected) for key, expected in EXPECTED.items()
           if actual[key] != expected}
    if bad:
        raise RuntimeError(
            "Refusing to export a model that is not the accepted PhoWhisper/Large-v2 shape: "
            + repr(bad)
        )
    feature_size = getattr(processor.feature_extractor, "feature_size", None)
    if feature_size != 80:
        raise RuntimeError(f"Expected an 80-mel processor, got {feature_size}")


def deterministic_features(processor, dtype):
    t = np.arange(16_000 * 5, dtype=np.float32) / 16_000.0
    audio = (0.02 * np.sin(2 * np.pi * 440.0 * t)).astype(np.float32)
    feature = processor.feature_extractor(
        audio, sampling_rate=16_000, return_tensors="pt"
    )["input_features"].to(dtype)
    if list(feature.shape) != [1, 80, 3000]:
        raise RuntimeError(f"Expected [1, 80, 3000], got {list(feature.shape)}")
    return feature


def asset_metadata(component: str) -> AIModelAssetMetadata:
    result = AIModelAssetMetadata()
    result.author = "Mural contributors; model lineage VinAI/OpenAI"
    result.license = "See source model and adapter licenses"
    result.model_description = (
        "Mural phowhisper-cs-fp16-v1 "
        f"{component}: PhoWhisper Large-v2 lineage with the Vietnamese-English "
        "code-switch LoRA merged. Weights are unchanged by this Core AI migration."
    )
    result.creation_date = int(time.time())
    return result


def save_program(program, path: Path, component: str, overwrite: bool) -> None:
    if path.exists():
        if not overwrite:
            raise FileExistsError(f"{path} exists; pass --overwrite")
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()
    program.save_asset(path, asset_metadata(component))


def convert(exported, input_names, output_names, optimize: bool):
    exported = exported.run_decompositions(get_decomp_table())
    converter = TorchConverter(mode=TorchConverter.Mode.RELEASE).add_exported_program(
        exported_program=exported,
        input_names=input_names,
        output_names=output_names,
    )
    program = converter.to_coreai()
    if optimize:
        program.optimize()
    return program


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--output-dir", default=".build/coreai/split-export")
    parser.add_argument("--name", default="phowhisper-cs-fp16-v1")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--skip-optimize", action="store_true",
                        help="Diagnostic only. Normal exports should optimize.")
    args = parser.parse_args()

    model_dir = Path(args.model_dir).expanduser().resolve()
    if not model_dir.exists():
        raise FileNotFoundError(model_dir)
    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    print("[1/7] Loading frozen merged FP16 source...")
    model = transformers.AutoModelForSpeechSeq2Seq.from_pretrained(
        str(model_dir),
        torch_dtype=torch.float16,
        use_safetensors=True,
        local_files_only=True,
        low_cpu_mem_usage=True,
    )
    model.eval()
    processor = transformers.AutoProcessor.from_pretrained(
        str(model_dir), local_files_only=True
    )
    validate_model(model, processor)
    features = deterministic_features(processor, torch.float16)

    encoder = EncoderModule(model).eval()
    decoder = DecoderModule(model).eval()

    print("[2/7] Verifying eager encoder/decoder contracts...")
    prefix = torch.tensor([[50258, 50259, 50359, 50363]], dtype=torch.int32)
    with torch.inference_mode():
        hidden = encoder(features)
        logits = decoder(prefix, hidden)
    if list(hidden.shape) != [1, 1500, 1280]:
        raise RuntimeError(f"Unexpected encoder shape: {list(hidden.shape)}")
    if list(logits.shape) != [1, 4, 51865]:
        raise RuntimeError(f"Unexpected decoder shape: {list(logits.shape)}")
    if not torch.isfinite(hidden).all() or not torch.isfinite(logits).all():
        raise RuntimeError("Non-finite eager outputs")

    print("[3/7] Exporting encoder graph...")
    with torch.autocast(device_type="cpu", dtype=torch.float16):
        encoder_exported = torch.export.export(
            encoder,
            args=(),
            kwargs={"input_features": features},
            dynamic_shapes={"input_features": {}},
        )

    print("[4/7] Converting encoder to Core AI...")
    encoder_program = convert(
        encoder_exported,
        input_names=["input_features"],
        output_names=["encoder_hidden_states"],
        optimize=not args.skip_optimize,
    )
    encoder_path = output_dir / f"{args.name}.encoder.aimodel"
    save_program(encoder_program, encoder_path, "encoder", args.overwrite)

    print("[5/7] Exporting decoder graph with dynamic prefix length...")
    hidden_example = hidden.detach()
    dynamic_seq = torch.export.Dim("dec_seq_len", min=1, max=448)
    with torch.autocast(device_type="cpu", dtype=torch.float16):
        decoder_exported = torch.export.export(
            decoder,
            args=(),
            kwargs={
                "decoder_input_ids": prefix,
                "encoder_hidden_states": hidden_example,
            },
            dynamic_shapes={
                "decoder_input_ids": {1: dynamic_seq},
                "encoder_hidden_states": {},
            },
        )

    print("[6/7] Converting decoder to Core AI...")
    decoder_program = convert(
        decoder_exported,
        input_names=["decoder_input_ids", "encoder_hidden_states"],
        output_names=["logits"],
        optimize=not args.skip_optimize,
    )
    decoder_path = output_dir / f"{args.name}.decoder.aimodel"
    save_program(decoder_program, decoder_path, "decoder", args.overwrite)

    print("[7/7] Writing export report...")
    top = torch.topk(logits[0, -1].float(), k=5)
    report = {
        "source_dir": str(model_dir),
        "dtype": "float16",
        "input_features_shape": [1, 80, 3000],
        "encoder_output_shape": [1, 1500, 1280],
        "decoder_prefix_example": [50258, 50259, 50359, 50363],
        "decoder_output_shape": [1, 4, 51865],
        "reference_last_row_top5_ids": top.indices.tolist(),
        "reference_last_row_top5_logits": top.values.tolist(),
        "encoder_asset": str(encoder_path),
        "encoder_bytes": directory_size(encoder_path),
        "decoder_asset": str(decoder_path),
        "decoder_bytes": directory_size(decoder_path),
        "total_bytes": directory_size(encoder_path) + directory_size(decoder_path),
        "optimized": not args.skip_optimize,
    }
    report_path = output_dir / f"{args.name}.split-export.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                           encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    print("Next: AOT compile both assets, stage the matching architecture pair, "
          "then launch Mural with --coreai-asr-probe.")


if __name__ == "__main__":
    main()
