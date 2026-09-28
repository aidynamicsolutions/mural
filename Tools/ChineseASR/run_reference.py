#!/usr/bin/env python3
"""Replay local WAVs through Breeze/PyTorch or FireRed-AED/sherpa-onnx.

No downloads. Install the reviewed model/runtime in an isolated environment first.
firered-onnx remains the AED encoder+decoder API. firered-ctc-onnx is an
explicit host-only candidate and requires a separately reviewed artifact pin.
Outputs are private local evidence. Runtime/model inference was not run on the
connector host; use the accompanying native qualification plans.
"""
from __future__ import annotations
import argparse
from importlib.metadata import version
from pathlib import Path
import re
import time

from evaluate import audio_path, corpus, pcm16, sha256, validate_audio, write_json
from prepare_breeze import validate_source


def generation_options() -> dict:
    return {"task": "transcribe", "language": None, "return_timestamps": False,
            "do_sample": False, "num_beams": 1, "max_new_tokens": 220}


def load_breeze(directory: Path, device: str):
    import numpy as np
    import torch
    from transformers import WhisperForConditionalGeneration, WhisperProcessor
    validate_source(directory)
    processor = WhisperProcessor.from_pretrained(directory, local_files_only=True)
    model = WhisperForConditionalGeneration.from_pretrained(directory, local_files_only=True, torch_dtype=torch.float32)
    model = model.to(device).eval()
    # The model config has an old English prefix; generation_config is automatic.
    # Be explicit in memory. Do not modify or overwrite the frozen source files.
    model.config.forced_decoder_ids = None
    model.generation_config.forced_decoder_ids = None
    model.generation_config.language = None
    def decode(samples):
        audio = np.asarray(samples, dtype=np.float32) / 32768.0
        features = processor(audio, sampling_rate=16000, return_tensors="pt")
        with torch.inference_mode():
            generated = model.generate(features.input_features.to(device), **generation_options())
        return processor.batch_decode(generated, skip_special_tokens=True)[0]
    return decode, {"torch": version("torch"), "transformers": version("transformers"), "device": device,
                    "generation": generation_options(), "note": "PyTorch reference; align token budget and WhisperKit heuristics before demanding exact parity"}


def load_firered(directory: Path):
    import numpy as np
    import sherpa_onnx
    for filename in ("encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt"):
        if not (directory / filename).is_file():
            raise ValueError(f"Missing FireRed AED artifact: {filename}")
    recognizer = sherpa_onnx.OfflineRecognizer.from_fire_red_asr(
        encoder=str(directory / "encoder.int8.onnx"), decoder=str(directory / "decoder.int8.onnx"),
        tokens=str(directory / "tokens.txt"), debug=False)
    def decode(samples):
        stream = recognizer.create_stream()
        stream.accept_waveform(16000, np.asarray(samples, dtype=np.float32) / 32768.0)
        recognizer.decode_stream(stream)
        return stream.result.text
    return decode, {"sherpa-onnx": version("sherpa-onnx"), "api": "OfflineRecognizer.from_fire_red_asr",
                    "note": "Converted AED reference. Verify ASR2 provenance and v2 dynamic-cache support; not a PyTorch parity result."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("backend", choices=("breeze", "firered-onnx", "firered-ctc-onnx"))
    parser.add_argument("corpus", type=Path); parser.add_argument("audio_root", type=Path)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--revision", help="Required for existing backends; immutable source/export revision")
    parser.add_argument("--candidate-pin", type=Path, help="CTC research only: separately reviewed two-file pin")
    parser.add_argument("--candidate-pin-sha256", help="CTC research only: independently reviewed pin digest")
    parser.add_argument("--device", choices=("cpu", "mps", "cuda"), default="cpu", help="Breeze only; start with a bounded reference run")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or args.output.is_symlink():
        parser.error("Output exists; do not overwrite previous evidence")
    ctc_research = args.backend == "firered-ctc-onnx"
    if ctc_research:
        if args.revision is not None or args.device != "cpu" or args.candidate_pin is None or not args.candidate_pin_sha256:
            parser.error("CTC research requires --candidate-pin and --candidate-pin-sha256, CPU, and no invented --revision")
    else:
        if args.candidate_pin is not None or args.candidate_pin_sha256 is not None:
            parser.error("Candidate pin arguments are valid only for explicit firered-ctc-onnx")
        if not args.revision or not re.fullmatch(r"[0-9a-f]{40}", args.revision):
            parser.error("Use a full immutable source/export revision, not main")
    report = {"schema": "mural.chinese-asr.predictions.v1", "backend": args.backend,
              "revision": args.revision, "predictions": [], "complete": False}
    try:
        rows = corpus(args.corpus)
        report["corpus_sha256"] = sha256(args.corpus)
        report["audio"] = validate_audio(rows, args.audio_root)
        if ctc_research:
            from firered_ctc_candidate import verify_candidate
            report.update(verify_candidate(args.model_dir, args.candidate_pin, args.candidate_pin_sha256))
        else:
            report["artifacts"] = {str(path.relative_to(args.model_dir)): {"bytes": path.stat().st_size, "sha256": sha256(path)}
                                   for path in sorted(args.model_dir.rglob("*")) if path.is_file() and not any(part.startswith(".") for part in path.relative_to(args.model_dir).parts)}
        if not report["artifacts"]:
            raise ValueError("Model directory is empty")
        started = time.perf_counter()
        if ctc_research:
            from firered_ctc_candidate import load_ctc
            decode, runtime = load_ctc(args.model_dir)
        else:
            decode, runtime = load_breeze(args.model_dir, args.device) if args.backend == "breeze" else load_firered(args.model_dir)
        report.update(runtime=runtime, prepare_seconds=time.perf_counter() - started)
        for row in rows:
            samples, seconds = pcm16(audio_path(args.audio_root, row["wav"]))
            started = time.perf_counter()
            text = decode(samples)
            report["predictions"].append({"id": row["id"], "text": text, "audio_seconds": seconds,
                                           "decode_seconds": time.perf_counter() - started})
        report["complete"] = True
    except Exception as error:
        report["failure"] = f"{type(error).__name__}: {error}"
        write_json(args.output, report)
        parser.exit(2, "Reference run failed; inspect the private report. No successful completion was recorded.\n")
    write_json(args.output, report)
    print(f"Replayed {len(rows)} local clips. This is not an iPhone result.")


if __name__ == "__main__":
    main()
