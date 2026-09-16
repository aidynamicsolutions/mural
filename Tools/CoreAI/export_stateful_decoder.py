#!/usr/bin/env python3
"""Bounded, self-cache-only PhoWhisper proof. Use the existing export environment."""
from __future__ import annotations

import argparse
import importlib.metadata
import json
from pathlib import Path

import numpy as np
import torch
import transformers
from transformers.cache_utils import DynamicCache, EncoderDecoderCache, StaticCache

from compare_decoder_logits import WEIGHTS_SHA256, compare, sha256
from export_phowhisper_split_coreai import DecoderModule, EXPECTED, save_program

CAPACITY = 224
# Declared before candidate execution: diagnostic numerical gate, not corpus parity.
# 0.125 is eight FP16 ULPs at logit magnitude 16; exact winners are also required.
MAX_ABSOLUTE_ERROR = 0.125


class StatefulDecoder(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.decoder = model.model.decoder
        self.proj_out = model.proj_out
        self.cache = StaticCache(config=model.config, max_cache_len=CAPACITY)
        heads = model.config.decoder_attention_heads
        for i, layer in enumerate(self.cache.layers):
            layer.lazy_initialization(torch.zeros(1, heads, 1, model.config.d_model // heads,
                                                  dtype=torch.float16))
            self.register_buffer(f"key_{i}", layer.keys)
            self.register_buffer(f"value_{i}", layer.values)

    def reset(self):
        for buffer in self.buffers():
            buffer.zero_()

    def forward(self, decoder_input_ids, encoder_hidden_states, cache_position, attention_mask):
        # ponytail: cross projections repeat per step; cache them only after this bounded proof.
        # Rebind through registered attributes so export lifts buffers, not Python-object constants.
        for i, layer in enumerate(self.cache.layers):
            layer.keys = getattr(self, f"key_{i}")
            layer.values = getattr(self, f"value_{i}")
        cache = EncoderDecoderCache(self.cache, DynamicCache())
        hidden = self.decoder(
            input_ids=decoder_input_ids, encoder_hidden_states=encoder_hidden_states,
            cache_position=cache_position, position_ids=cache_position.unsqueeze(0),
            attention_mask=attention_mask, past_key_values=cache,
            use_cache=True, return_dict=True,
        ).last_hidden_state
        return self.proj_out(hidden)


def inputs_for(token, position, hidden):
    if not 0 <= token < 51865 or not 0 <= position < CAPACITY:
        raise ValueError("Token or cache position out of bounds")
    mask = torch.full((1, 1, 1, CAPACITY), torch.finfo(torch.float16).min,
                      dtype=torch.float16)
    mask[..., :position + 1] = 0
    return dict(decoder_input_ids=torch.tensor([[token]], dtype=torch.int32),
                encoder_hidden_states=hidden,
                cache_position=torch.tensor([position], dtype=torch.int64),
                attention_mask=mask)


def row_of(logits):
    if logits.ndim != 3 or logits.shape[0] != 1 or logits.shape[-1] != 51865 or not torch.isfinite(logits).all():
        raise ValueError("Invalid logits")
    return logits[0, -1].detach().float().numpy().astype("<f4")


def require_match(reference, actual):
    result = compare(reference, actual)
    if not result["sameWinner"] or result["maxAbsoluteError"] > MAX_ABSOLUTE_ERROR:
        raise ValueError(f"Prediction/numerical gate failed: {result}")
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--model-dir", type=Path, required=True)
    p.add_argument("--checkpoint", type=Path, required=True)
    p.add_argument("--output-dir", type=Path, required=True)
    p.add_argument("--export", action="store_true")
    args = p.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=False)
    report = {"status": "started", "capacity": CAPACITY,
              "gate": {"sameWinner": True, "maxAbsoluteError": MAX_ABSOLUTE_ERROR,
                       "resetReplayBitExact": True},
              "crossProjectionCache": False,
              "packages": {n: importlib.metadata.version(n) for n in
                           ("torch", "transformers", "coreai-torch", "coreai-core", "numpy")},
              "comparisons": []}
    def save():
        (args.output_dir / "report.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    save()
    try:
        if sha256(args.model_dir / "model.safetensors") != WEIGHTS_SHA256:
            raise ValueError("Not the frozen accepted weights")
        metadata = json.loads(args.checkpoint.with_suffix(".json").read_text())
        if sha256(args.checkpoint) != metadata["tensorSHA256"]:
            raise ValueError("Checkpoint hash differs")
        values = np.fromfile(args.checkpoint, dtype="<f2")
        if values.size != 1500 * 1280 or not np.isfinite(values).all():
            raise ValueError("Invalid checkpoint")
        hidden = torch.from_numpy(values.reshape(1, 1500, 1280))
        torch.set_num_threads(4)
        model = transformers.AutoModelForSpeechSeq2Seq.from_pretrained(
            str(args.model_dir), dtype=torch.float16, use_safetensors=True,
            local_files_only=True, low_cpu_mem_usage=True).eval().requires_grad_(False)
        if any(getattr(model.config, k, None) != v for k, v in EXPECTED.items()):
            raise ValueError("Unexpected model architecture")
        tokenizer = transformers.AutoTokenizer.from_pretrained(str(args.model_dir), local_files_only=True)
        tokens = [50258, 50278, 50359, 50363] + tokenizer.encode(
            "Yesterday I went to the supermarket.", add_special_tokens=False)[:4]
        report.update(weightsSHA256=WEIGHTS_SHA256, checkpoint=metadata, tokens=tokens,
                      resolvedAttention=model.config._attn_implementation)
        save()
        reference = DecoderModule(model).eval()
        step = StatefulDecoder(model).eval()
        references = {}
        with torch.inference_mode():
            for attention in dict.fromkeys((model.config._attn_implementation, "eager")):
                model.set_attn_implementation(attention)
                step.reset()
                rows = []
                for pos, token in enumerate(tokens):
                    ref = row_of(reference(torch.tensor([tokens[:pos + 1]], dtype=torch.int32), hidden))
                    actual = row_of(step(**inputs_for(token, pos, hidden)))
                    # Save both rows before applying the stop gate, including a failing pair.
                    ref.tofile(args.output_dir / f"{attention}-{pos}.reference.f32")
                    actual.tofile(args.output_dir / f"{attention}-{pos}.cached.f32")
                    result = compare(ref, actual)
                    report["comparisons"].append(dict(attention=attention, position=pos,
                                                       tokens=tokens[:pos + 1], **result))
                    save()
                    require_match(ref, actual)
                    rows.append(actual)
                    print(attention, pos, result, flush=True)
                # Same allocated buffers, reset and replay: no stale sequence survives.
                step.reset()
                for pos, token in enumerate(tokens):
                    replay = row_of(step(**inputs_for(token, pos, hidden)))
                    if replay.tobytes() != rows[pos].tobytes():
                        raise ValueError("Reset/replay differs")
                references[attention] = rows
        model.set_attn_implementation(report["resolvedAttention"])
        step.reset()
        report["resetReplayBitExact"] = True
        report["status"] = "pytorch-passed"
        save()
        if not args.export:
            return
        from coreai_torch import TorchConverter, get_decomp_table
        inputs = inputs_for(tokens[0], 0, hidden)
        with torch.no_grad():
            exported = torch.export.export(step, (), kwargs=inputs)
            (args.output_dir / "raw-graph-signature.txt").write_text(str(exported.graph_signature))
            exported = exported.run_decompositions(get_decomp_table())
        signature = exported.graph_signature
        (args.output_dir / "graph-signature.txt").write_text(str(signature))
        (args.output_dir / "graph.txt").write_text(str(exported.graph))
        states = list(signature.buffers_to_mutate.values())
        expected_states = [name for name, _ in step.named_buffers()]
        if states != expected_states or len(states) != 64:
            raise ValueError(f"Expected exactly 64 lifted mutable self caches, got {states}")
        # The functionalized captured program must preserve state across successive calls too.
        module = exported.module()
        with torch.no_grad():
            for buffer in module.buffers():
                buffer.zero_()
            for pos, token in enumerate(tokens):
                actual = row_of(module(**inputs_for(token, pos, hidden)))
                require_match(references[report["resolvedAttention"]][pos], actual)
            for buffer in module.buffers():
                buffer.zero_()
        report["states"] = states
        report["inputShapes"] = {k: list(v.shape) for k, v in inputs.items()}
        report["exportedStatePersistencePassed"] = True
        save()
        program = TorchConverter(mode=TorchConverter.Mode.RELEASE).add_exported_program(
            exported, input_names=list(inputs), output_names=["logits"], state_names=states).to_coreai()
        program.optimize()
        asset = args.output_dir / "phowhisper-cs-fp16-v1.decoder-stateful.aimodel"
        save_program(program, asset, "decoder-stateful-self-cache-diagnostic", False)
        report.update(status="exported", asset=str(asset))
        save()
    except Exception as error:
        report.update(status="failed", error=str(error))
        save()
        raise


if __name__ == "__main__":
    main()
