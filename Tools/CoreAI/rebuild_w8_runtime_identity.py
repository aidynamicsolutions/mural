#!/usr/bin/env python3
"""Build W8 v3 with a computed FP16 marker; never return a constant Int32 tensor.

Default transport packs hidden values and response into ONE runtime output.
--transport split is a bounded alternative, not an automatic production fallback.
Start with --kind tiny --format fp16; do not rebuild large assets before it runs.
"""
from __future__ import annotations

import argparse
import importlib.metadata
import inspect
import json
import logging
from pathlib import Path
import subprocess
import warnings

from w8_runtime_identity import (SCHEMA, identity, file_hash, bundle_record,
                                build_wrapper, challenge, unpack_host,
                                validate_capture, check_contract)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kind", required=True, choices=("tiny", "encoder"))
    parser.add_argument("--format", required=True, choices=("fp16", "fp8", "int8"))
    parser.add_argument("--transport", choices=("packed", "split"), default="packed")
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--model-dir", type=Path)
    parser.add_argument("--aot", action="store_true")
    parser.add_argument("--architecture", default="h18p", choices=("h18p",))
    args = parser.parse_args()
    if args.output_dir.exists():
        parser.error("Output exists; use a new directory, not overwrite/resume")
    if (args.kind == "encoder") != (args.model_dir is not None):
        parser.error("Only the encoder kind requires --model-dir")

    # Reuse the reviewed v2 numerical model/audit helpers, NOT its constant-marker wrapper.
    from rebuild_w8_identity import (PINS, FROZEN_WEIGHTS, audit, build_tiny,
                                     inspect_asset, run_command)
    packages = (*PINS, "torch", "numpy", "ml-dtypes")
    if args.kind == "encoder":
        packages += ("transformers",)
    versions = {name: importlib.metadata.version(name) for name in packages}
    for name, version in PINS.items():
        if versions[name] != version:
            parser.error(f"Unreviewed {name} {versions[name]}; isolate any toolchain change")
    import torch
    from coreai.authoring import AIModelAsset
    from coreai.runtime import AIModelAssetMetadata
    from coreai_torch import TorchConverter, get_decomp_table
    from coreai_opt.coreai_utils import quantize_weights, DType, CompressionGranularity
    from coreai_opt.coreai_utils.common import QScheme
    if "entrypoint_name" not in inspect.signature(TorchConverter.add_exported_program).parameters:
        parser.error("Installed converter lacks named entrypoints")

    compiler = subprocess.check_output(["xcrun", "coreai-build", "--version"], text=True).strip()
    weights = args.model_dir / "model.safetensors" if args.model_dir else None
    if weights is not None and file_hash(weights) != FROZEN_WEIGHTS:
        parser.error("Not the frozen merged PhoWhisper weights")
    source_files = {}
    if args.model_dir:
        for name in ("config.json", "preprocessor_config.json", "generation_config.json"):
            source_files[name] = file_hash(args.model_dir / name)
    tool_dir = Path(__file__).parent
    control = {"kind": args.kind, "transport": args.transport, "versions": versions,
               "compiler": compiler, "architecture": args.architecture,
               "min_deployment": "27.0", "compute": "gpu",
               "tool_hashes": {name: file_hash(tool_dir / name) for name in
                   ("rebuild_w8_runtime_identity.py", "w8_runtime_identity.py", "rebuild_w8_identity.py")},
               "source_weights": FROZEN_WEIGHTS if weights else "synthetic-distinct-linear-v2",
               "source_configuration": source_files}
    recipe = {"kind": args.kind, "format": args.format, "transport": args.transport, "control": control,
              "quantization": {"granularity": "per_channel", "qscheme": "symmetric",
                               "threshold": 1024, "scale_dtype": None, "activation_quantization": False}}
    spec = identity(recipe)
    args.output_dir.mkdir(parents=True, exist_ok=False)
    report = {"schema": SCHEMA, "status": "started", "recipe": recipe,
              "control": control, "identity": spec, "warnings": [],
              "native_mac_execution": "not performed", "device_qualification": "not performed"}

    class Capture(logging.Handler):
        def emit(self, record):
            report["warnings"].append(self.format(record))
    handler = Capture(level=logging.WARNING)
    logging.getLogger().addHandler(handler)
    try:
        if args.kind == "tiny":
            body, samples = build_tiny(args.format)
            metadata = AIModelAssetMetadata()
            metadata.model_description = "Mural synthetic computed-marker v3; not speech"
        else:
            from export_phowhisper_split_coreai import (EncoderModule, validate_model,
                                                        deterministic_features, asset_metadata)
            import transformers
            model = transformers.AutoModelForSpeechSeq2Seq.from_pretrained(
                str(args.model_dir), torch_dtype=torch.float16, use_safetensors=True,
                local_files_only=True, low_cpu_mem_usage=True).eval()
            processor = transformers.AutoProcessor.from_pretrained(str(args.model_dir), local_files_only=True)
            validate_model(model, processor)
            report["attention_implementation"] = model.config._attn_implementation
            body = EncoderModule(model).eval()
            del model
            samples = [deterministic_features(processor, torch.float16)]
            metadata = asset_metadata("encoder-w8-runtime-identity-v3")
        body.requires_grad_(False)
        wrapped = build_wrapper(body, spec)
        references = []
        with torch.inference_mode():
            for sample in samples:
                expected = body(sample)
                for seed in (0, 7, 23):
                    nonce = challenge(spec, seed)
                    value = wrapped(sample, torch.tensor([nonce], dtype=torch.float16))
                    hidden = unpack_host(value, spec, nonce)
                    torch.testing.assert_close(hidden, expected, rtol=0, atol=0)
                if args.kind == "tiny":
                    references.append({"input": sample.float().tolist(),
                                       "uncompressed_output": expected.float().tolist()})
        report["wrapper_hidden_bit_exact_host"] = True
        if references:
            report.update(tiny_vectors=references, tiny_max_abs_error_bound=0.05,
                          tiny_bound_scope="Synthetic identity test only; not ASR accuracy")
        kwargs = {"input_features": samples[0],
                  "identity_challenge": torch.tensor([challenge(spec, 0)], dtype=torch.float16)}
        print("Capturing computed-marker graph...", flush=True)
        with torch.autocast(device_type="cpu", dtype=torch.float16):
            exported = torch.export.export(wrapped, args=(), kwargs=kwargs,
                                           dynamic_shapes={key: {} for key in kwargs})
        validate_capture(exported, spec)
        # Validate NON-example inputs and changed nonces after capture as well.
        with torch.inference_mode():
            for sample in samples:
                for seed in (0, 7, 23):
                    nonce = challenge(spec, seed)
                    value = exported.module()(input_features=sample,
                                identity_challenge=torch.tensor([nonce], dtype=torch.float16))
                    torch.testing.assert_close(unpack_host(value, spec, nonce), body(sample), rtol=0, atol=0)
        report["torch_capture_bit_exact_host"] = True
        report["challenge_runtime_input_verified_host"] = True
        output_names = ([spec["packed_output"]] if args.transport == "packed" else
                        ["encoder_hidden_states", spec["response_output"]])
        print("Converting and auditing Core AI graph...", flush=True)
        program = TorchConverter(mode=TorchConverter.Mode.RELEASE).add_exported_program(
            exported_program=exported.run_decompositions(get_decomp_table()),
            input_names=list(kwargs), output_names=output_names,
            entrypoint_name=spec["entrypoint"]).to_coreai()
        program.optimize()
        before = audit(program, spec["entrypoint"])
        report["audit_before"] = before
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            if args.format != "fp16":
                program = quantize_weights(program,
                    dtype=DType.FP8_E4M3FN if args.format == "fp8" else DType.INT8,
                    qscheme=QScheme.SYMMETRIC, granularity=CompressionGranularity.PER_CHANNEL,
                    weight_num_threshold=1024, scale_dtype=None, in_place=False)
                program.optimize()
        report["warnings"].extend(str(w.message) for w in caught)
        after = audit(program, spec["entrypoint"])
        report["audit_after"] = after
        if args.format != "fp16":
            count = sum(r["elements"] for r in before["eligible"])
            if (not count or after["eligible"] or count != sum(r["elements"] for r in after["compressed"])
                    or len(before["eligible"]) != len(after["compressed"])):
                raise ValueError("Incomplete/unexpected compression coverage; inspect audit")
        path = args.output_dir / (spec["entrypoint"] + ".aimodel")
        metadata.model_description += f"; {args.format}; {args.transport} computed FP16 marker; trial only"
        program.save_asset(path, metadata)
        check_contract(inspect_asset(path), spec)
        if audit(AIModelAsset.load(path).program, spec["entrypoint"]) != after:
            raise ValueError("Saved graph audit changed")
        report.update(source=bundle_record(path), status="source-static-only")
        if args.aot:
            print("Compiling fresh AOT artifact...", flush=True)
            destination = args.output_dir / "aot"
            command = ["xcrun", "coreai-build", "compile", str(path), "--platform", "iOS",
                       "--min-deployment-version", "27.0", "--preferred-compute", "gpu",
                       "--architecture", args.architecture, "--output", str(destination)]
            report["aot_command"] = command
            run_command(command, args.output_dir / "aot.log")
            bundles = sorted(destination.glob("*.aimodelc"))
            if len(bundles) != 1:
                raise ValueError("Expected one AOT bundle")
            check_contract(inspect_asset(bundles[0]), spec)
            report.update(aot=bundle_record(bundles[0]), status="aot-static-only")
        if weights is not None and file_hash(weights) != FROZEN_WEIGHTS:
            raise ValueError("Frozen weights changed")
        for name, digest in source_files.items():
            if file_hash(args.model_dir / name) != digest:
                raise ValueError(f"Source config changed: {name}")
    except Exception as error:
        report.update(status="failed", error=repr(error))
        raise
    finally:
        logging.getLogger().removeHandler(handler)
        (args.output_dir / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "identity": spec}, indent=2))
    print("Next: w8_runtime_identity.py manifest(s) --print-swift-pins, then the tiny phone gate.")


if __name__ == "__main__":
    main()
