#!/usr/bin/env python3
"""Build ONE fresh encoder PAL6 candidate from frozen FP16 weights, not from FP8.

Requires the actual retained FP8/PAL8 manifests and the pinned Apple environment.
Does not install assets, edit app pins, run inference on a phone, or change Talk.
"""
from __future__ import annotations

import argparse
import importlib.metadata
import inspect
import json
import logging
from pathlib import Path
import random
import subprocess
import warnings

from pal6_contract import (SCHEMA, SETTINGS, PINS, FROZEN_WEIGHTS, FP8_MANIFEST,
                           PAL8_MANIFEST, CONTROL_FIELDS, sha256, read_pinned,
                           identity, challenge, build_wrapper, unpack_host,
                           check_contract, snapshot, coverage, validate_pair)


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", required=True, type=Path)
    parser.add_argument("--reference-manifest", required=True, type=Path)
    parser.add_argument("--pal8-manifest", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--retained-exceptions", type=Path,
                        help="Reviewed JSON mapping exact audit tensor keys to reasons; no patterns")
    parser.add_argument("--architecture", required=True, choices=("h18p",))
    parser.add_argument("--aot", action="store_true")
    args = parser.parse_args()
    if args.output_dir.exists():
        parser.error("Output exists; use a new immutable directory, never overwrite/resume")
    reference = read_pinned(args.reference_manifest, FP8_MANIFEST)
    read_pinned(args.pal8_manifest, PAL8_MANIFEST)
    from w8_runtime_identity import audit_reports, bundle_record
    from rebuild_w8_identity import inspect_asset, run_command
    audit_reports([reference], require_triple=False)
    if (reference["identity"]["kind"], reference["identity"]["format"],
            reference["identity"]["transport"]) != ("encoder", "fp8", "packed"):
        parser.error("The reference must be the pinned packed FP8 full encoder")
    protected = [args.model_dir, args.reference_manifest.parent, args.pal8_manifest.parent]
    protected += [Path(reference[k]["path"]) for k in ("source", "aot")]
    if any(args.output_dir.resolve().is_relative_to(p.resolve()) for p in protected):
        parser.error("Output must not be inside source, reference, or decoder assets/evidence")
    weights = args.model_dir / "model.safetensors"
    if sha256(weights) != FROZEN_WEIGHTS:
        parser.error("Not the frozen merged bilingual weights; do not remerge or requantize FP8")
    config = {name: sha256(args.model_dir / name) for name in
              ("config.json", "preprocessor_config.json", "generation_config.json")}
    versions = {name: importlib.metadata.version(name) for name in
                (*PINS, "torch", "numpy", "ml-dtypes", "transformers")}
    if any(versions[name] != version for name, version in PINS.items()):
        parser.error("Unreviewed Apple toolchain; recover the pinned environment before proceeding")
    compiler = subprocess.check_output(["xcrun", "coreai-build", "--version"], text=True).strip()
    control = {"kind": "encoder", "transport": "packed", "versions": versions,
               "compiler": compiler, "architecture": args.architecture,
               "min_deployment": "27.0", "compute": "gpu",
               "source_weights": FROZEN_WEIGHTS, "source_configuration": config}
    for field in CONTROL_FIELDS:
        if control[field] != reference["control"].get(field):
            parser.error(f"Unmatched FP8 control: {field}; do not silently change two variables")
    tool_dir = Path(__file__).resolve().parent
    control["tool_hashes"] = {name: sha256(tool_dir / name) for name in (
        "build_pal6_encoder.py", "pal6_contract.py", "w8_runtime_identity.py",
        "rebuild_w8_identity.py", "export_phowhisper_split_coreai.py")}
    source_files = {p.name: sha256(p) for p in sorted(args.model_dir.iterdir())
                    if p.is_file() and p.suffix in {".json", ".txt"}}
    exceptions = json.loads(args.retained_exceptions.read_text()) if args.retained_exceptions else {}
    if not isinstance(exceptions, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in exceptions.items()):
        parser.error("Retained exceptions must be an exact key-to-reason JSON object")

    import numpy as np
    import torch
    from coreai.authoring import AIModelAsset
    from coreai_torch import TorchConverter, get_decomp_table
    from coreai_opt.coreai_utils import palettize_weights, CompressionGranularity
    from export_phowhisper_split_coreai import (EncoderModule, validate_model,
                                                deterministic_features, asset_metadata)
    import transformers
    kwargs = {key: SETTINGS[key] for key in (
        "lut_dtype", "n_bits", "group_size", "cluster_dim", "enable_per_channel_scale",
        "weight_num_threshold", "num_kmeans_workers", "enable_fast_kmeans_mode", "rounding_precision")}
    kwargs.update(granularity=CompressionGranularity.PER_GROUPED_CHANNEL, in_place=False)
    signature = inspect.signature(palettize_weights)
    # Verify the public API BEFORE an expensive model load. No guessed FP6 dtype.
    signature.bind(None, **kwargs)
    if "entrypoint_name" not in inspect.signature(TorchConverter.add_exported_program).parameters:
        parser.error("Installed converter lacks named entrypoints")
    optimizer_source = inspect.getsourcefile(palettize_weights)
    control["palettizer_api"] = {"signature": str(signature),
                                "source_sha256": sha256(Path(optimizer_source)) if optimizer_source else None}
    recipe = {"kind": "encoder", "format": "pal6", "transport": "packed", "control": control,
              "palettization": SETTINGS, "retained_exceptions": exceptions,
              "reference_manifest_sha256": FP8_MANIFEST, "decoder_manifest_sha256": PAL8_MANIFEST,
              "source_support_files": source_files}
    spec = identity(recipe)
    args.output_dir.mkdir(parents=True, exist_ok=False)
    report = {"schema": SCHEMA, "status": "started", "recipe": recipe, "control": control,
              "identity": spec, "warnings": [], "native_mac_execution": "not performed",
              "device_qualification": "not performed", "speech_quality": "not measured"}

    class Capture(logging.Handler):
        def emit(self, record):
            report["warnings"].append(self.format(record))
    handler = Capture(level=logging.WARNING)
    logging.getLogger().addHandler(handler)
    try:
        random.seed(SETTINGS["seed"])
        np.random.seed(SETTINGS["seed"])
        torch.manual_seed(SETTINGS["seed"])
        model = transformers.AutoModelForSpeechSeq2Seq.from_pretrained(
            str(args.model_dir), torch_dtype=torch.float16, use_safetensors=True,
            local_files_only=True, low_cpu_mem_usage=True).eval()
        processor = transformers.AutoProcessor.from_pretrained(str(args.model_dir), local_files_only=True)
        validate_model(model, processor)
        report["attention_implementation"] = model.config._attn_implementation
        if report["attention_implementation"] != reference.get("attention_implementation"):
            raise ValueError("Attention implementation differs from accepted FP8 export")
        body = EncoderModule(model).eval()
        del model
        body.requires_grad_(False)
        sample = deterministic_features(processor, torch.float16)
        if list(sample.shape) != [1, 80, 3000] or sample.dtype != torch.float16 or not torch.isfinite(sample).all():
            raise ValueError("Frozen frontend sample contract changed")
        report["host_mel_sha256"] = __import__("hashlib").sha256(sample.cpu().numpy().astype("<f2").tobytes()).hexdigest()
        wrapped = build_wrapper(body, spec)
        with torch.inference_mode():
            expected = body(sample)
            for seed in (0, 7, 23):
                nonce = challenge(seed)
                packet = wrapped(sample, torch.tensor([nonce], dtype=torch.float16))
                torch.testing.assert_close(unpack_host(packet, spec, nonce), expected, rtol=0, atol=0)
        report["wrapper_hidden_bit_exact_host"] = True
        inputs = {"input_features": sample, "identity_challenge": torch.tensor([challenge(0)], dtype=torch.float16)}
        with torch.autocast(device_type="cpu", dtype=torch.float16):
            exported = torch.export.export(wrapped, args=(), kwargs=inputs,
                                           dynamic_shapes={key: {} for key in inputs})
        user_inputs = [s.arg.name for s in exported.graph_signature.input_specs if s.kind.name == "USER_INPUT"]
        if user_inputs != list(inputs):
            raise ValueError("Capture specialized away a runtime input")
        with torch.inference_mode():
            for seed in (0, 7, 23):
                nonce = challenge(seed)
                packet = exported.module()(input_features=sample,
                    identity_challenge=torch.tensor([nonce], dtype=torch.float16))
                torch.testing.assert_close(unpack_host(packet, spec, nonce), expected, rtol=0, atol=0)
        report["torch_capture_bit_exact_host"] = True
        report["challenge_runtime_input_verified_host"] = True
        program = TorchConverter(mode=TorchConverter.Mode.RELEASE).add_exported_program(
            exported_program=exported.run_decompositions(get_decomp_table()), input_names=list(inputs),
            output_names=["encoded_packet"], entrypoint_name=spec["entrypoint"]).to_coreai()
        program.optimize()
        before = snapshot(program, spec["entrypoint"])
        report["audit_before"] = before
        write_json(args.output_dir / "audit-before.json", before)
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            program = palettize_weights(program, **kwargs)
            program.optimize()
        report["warnings"].extend(str(w.message) for w in caught)
        after = snapshot(program, spec["entrypoint"])
        report["audit_after"] = after
        write_json(args.output_dir / "audit-after.json", after)
        report["coverage"] = coverage(before, after, exceptions)
        path = args.output_dir / (spec["entrypoint"] + ".aimodel")
        metadata = asset_metadata("encoder-pal6-packed-v3-trial")
        metadata.model_description += "; PAL6 g16 scalar FP16 LUT; encoder-only unqualified experiment"
        program.save_asset(path, metadata)
        check_contract(inspect_asset(path), spec)
        if snapshot(AIModelAsset.load(path).program, spec["entrypoint"]) != after:
            raise ValueError("Saved PAL6 graph audit changed")
        report.update(source=bundle_record(path), status="source-static-only")
        if args.aot:
            destination = args.output_dir / "aot"
            command = ["xcrun", "coreai-build", "compile", str(path), "--platform", "iOS",
                       "--min-deployment-version", "27.0", "--preferred-compute", "gpu",
                       "--architecture", args.architecture, "--output", str(destination)]
            report["aot_command"] = command
            run_command(command, args.output_dir / "aot.log")
            bundles = sorted(destination.glob("*.aimodelc"))
            if len(bundles) != 1:
                raise ValueError("Expected exactly one immutable PAL6 AOT bundle")
            check_contract(inspect_asset(bundles[0]), spec)
            report.update(aot=bundle_record(bundles[0]), status="aot-static-only")
            validate_pair(reference, report)
        if sha256(weights) != FROZEN_WEIGHTS or any(sha256(args.model_dir / name) != digest for name, digest in source_files.items()):
            raise ValueError("Source files changed during conversion")
        read_pinned(args.reference_manifest, FP8_MANIFEST)
        read_pinned(args.pal8_manifest, PAL8_MANIFEST)
    except Exception as error:
        report.update(status="failed", error=repr(error))
        raise
    finally:
        logging.getLogger().removeHandler(handler)
        write_json(args.output_dir / "manifest.json", report)
    print(json.dumps({"status": report["status"], "identity": spec,
                      "device_qualification": "NOT PERFORMED"}, indent=2))


if __name__ == "__main__":
    main()
