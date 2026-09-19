#!/usr/bin/env python3
"""Fresh, named W8 exports with an observable identity output; no cache mutation.

Start with --kind tiny. The real encoder is the exact frozen merged model.
This changes the diagnostic ABI, not the encoder's speech weights or math.
No app candidate is enabled by this tool. Run w8_identity.py after AOT builds.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import importlib.metadata
import inspect
import json
import logging
import math
from pathlib import Path
import subprocess
import sys
import warnings

from w8_identity import SCHEMA, bundle_record, canonical, file_hash, identity

PINS = {"coreai-core": "1.0.0b2", "coreai-torch": "0.4.1", "coreai-opt": "0.2.1"}
FROZEN_WEIGHTS = "264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a"
CONSUMERS = {"coreai.batch_matmul", "coreai.conv2d",
             "coreai.decomposable.broadcasting_batch_matmul", "coreai.gather_nd",
             "coreai.transpose"}


def build_wrapper(module, spec):
    """No arithmetic is added to the speech-output branch."""
    import torch

    class NamedEncoder(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.body = module
            self.register_buffer("identity_words", torch.tensor(spec["marker_values"], dtype=torch.int32))

        def forward(self, input_features):
            hidden = self.body(input_features)
            return hidden, self.identity_words.clone()

    return NamedEncoder().eval()


def build_tiny(precision):
    """Distinct synthetic arithmetic detects reuse beyond the marker output.

    Both weights and bias differ by format. Two nonzero weights per output
    limit quantization error; test vectors and a predeclared diagnostic bound
    are saved in the manifest. This is not a speech accuracy evaluation.
    """
    import torch
    code = {"fp16": 1, "fp8": 2, "int8": 3}[precision]
    module = torch.nn.Linear(64, 64).half().eval()
    with torch.no_grad():
        module.weight.zero_()
        for i in range(64):
            module.weight[i, i] = code
            module.weight[i, (i + 1) % 64] = -0.5 * code
        module.bias.fill_(code)
    vectors = [torch.zeros(1, 64, dtype=torch.float16),
               torch.ones(1, 64, dtype=torch.float16),
               torch.linspace(-0.5, 0.5, 64, dtype=torch.float16).reshape(1, 64)]
    return module, vectors


def audit(program, name):
    """Inspect only; no mutation of private IR attributes or native hashes."""
    root = program.get_graph(name).operation
    while root.parent is not None:
        root = root.parent
    root.verify()
    operations = Counter()
    eligible = []
    compressed = []

    def visit(op):
        operations[op.name] += 1
        if op.name in {"coreai.constant", "coreai.blockwise_shift_scale"}:
            tensor = op.results[0].type
            dtype = str(tensor.element_type)
            shape = list(tensor.shape)
            consumers = {use.owner.name for use in op.results[0].uses}
            count = math.prod(shape)
            row = {"shape": shape, "dtype": dtype, "elements": count,
                   "location": str(op.location)}
            if op.name == "coreai.blockwise_shift_scale":
                row["storage_type"] = str(op.operands[0].type)
                compressed.append(row)
            elif dtype in {"f16", "f32"} and count > 1024 and (
                    consumers <= CONSUMERS or count >= 100_000_000):
                eligible.append(row)
        for region in op.regions:
            for block in region.blocks:
                for child in block.operations:
                    visit(child.operation)
    visit(root)
    return {"ops": dict(operations), "eligible": eligible, "compressed": compressed}


def inspect_asset(path):
    return json.loads(subprocess.check_output(
        ["xcrun", "coreai-build", "inspect", str(path), "--storage", "--compute", "--ops", "--json"],
        text=True))


def check_contract(summary, spec, kind):
    def array_type(dtype, shape):
        return f"NDArray ({dtype}, {' × '.join(map(str, shape))})"
    input_shape = [1, 64] if kind == "tiny" else [1, 80, 3000]
    hidden_shape = [1, 64] if kind == "tiny" else [1, 1500, 1280]
    functions = summary["summary"]["functions"]
    if len(functions) != 1 or functions[0]["name"] != spec["entrypoint"]:
        raise ValueError("Compiler changed/dropped the named entrypoint")
    inputs = functions[0]["inputs"]
    outputs = functions[0]["outputs"]
    if inputs != [{"name": "input_features", "type": array_type("Float16", input_shape)}]:
        raise ValueError(f"Unexpected input ABI: {inputs}")
    expected = {"encoder_hidden_states": array_type("Float16", hidden_shape),
                spec["marker_output"]: array_type("Int32", spec["marker_shape"])}
    if len(outputs) != 2 or {o["name"]: o["type"] for o in outputs} != expected:
        raise ValueError(f"Compiler changed/dropped hidden output or identity output: {outputs}")


def run_command(command, log):
    with log.open("w") as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}); see {log}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kind", required=True, choices=("tiny", "encoder"))
    parser.add_argument("--format", required=True, choices=("fp16", "fp8", "int8"))
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--model-dir", type=Path)
    parser.add_argument("--aot", action="store_true")
    parser.add_argument("--architecture", default="h18p", choices=("h18p",))
    args = parser.parse_args()
    if args.output_dir.exists():
        parser.error("Output exists; no overwrite or automatic resume")
    if (args.kind == "encoder") != (args.model_dir is not None):
        parser.error("Only --kind encoder requires --model-dir")
    packages = (*PINS, "torch", "numpy", "ml-dtypes")
    if args.kind == "encoder":
        packages += ("transformers",)
    versions = {k: importlib.metadata.version(k) for k in packages}
    for package, pin in PINS.items():
        if versions[package] != pin:
            parser.error(f"Unreviewed {package} {versions[package]}; keep the pinned environment")
    import torch
    from coreai.authoring import AIModelAsset
    from coreai.runtime import AIModelAssetMetadata
    from coreai_torch import TorchConverter, get_decomp_table
    from coreai_opt.coreai_utils import quantize_weights, DType, CompressionGranularity
    from coreai_opt.coreai_utils.common import QScheme

    if "entrypoint_name" not in inspect.signature(TorchConverter.add_exported_program).parameters:
        parser.error("Installed public converter lacks entrypoint_name; do not patch its internals")
    compiler = subprocess.check_output(["xcrun", "coreai-build", "--version"], text=True).strip()
    weights = args.model_dir / "model.safetensors" if args.model_dir else None
    if weights and file_hash(weights) != FROZEN_WEIGHTS:
        parser.error("Merged source weights do not match the frozen bilingual model")
    source_files = {}
    if args.model_dir:
        for name in ("config.json", "preprocessor_config.json", "generation_config.json"):
            source_files[name] = file_hash(args.model_dir / name)
    control = {"kind": args.kind, "versions": versions, "compiler": compiler,
               "architecture": args.architecture, "min_deployment": "27.0", "compute": "gpu",
               "exporter_sha256": file_hash(Path(__file__)),
               "identity_helper_sha256": file_hash(Path(__file__).with_name("w8_identity.py")),
               "source_weights": FROZEN_WEIGHTS if weights else "synthetic-distinct-linear-v2",
               "source_configuration": source_files}
    recipe = {"kind": args.kind, "format": args.format, "control": control,
              "quantization": {"granularity": "per_channel", "qscheme": "symmetric",
                               "threshold": 1024, "scale_dtype": None,
                               "activation_quantization": False}}
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
            module, samples = build_tiny(args.format)
            metadata = AIModelAssetMetadata()
            metadata.model_description = "Mural synthetic W8 cache-isolation diagnostic; not an ASR model"
        else:
            from export_phowhisper_split_coreai import (
                EncoderModule, validate_model, deterministic_features, asset_metadata)
            import transformers
            model = transformers.AutoModelForSpeechSeq2Seq.from_pretrained(
                str(args.model_dir), torch_dtype=torch.float16, use_safetensors=True,
                local_files_only=True, low_cpu_mem_usage=True).eval()
            processor = transformers.AutoProcessor.from_pretrained(str(args.model_dir), local_files_only=True)
            validate_model(model, processor)
            report["attention_implementation"] = model.config._attn_implementation
            module = EncoderModule(model).eval()
            del model  # Retain only the encoder; the host need not keep decoder weights.
            samples = [deterministic_features(processor, torch.float16)]
            metadata = asset_metadata("encoder-w8-identity-v2")
        wrapped = build_wrapper(module, spec)
        # No training. Verify the wrapper itself leaves speech/synthetic output unchanged.
        references = []
        with torch.inference_mode():
            for sample in samples:
                reference = module(sample)
                hidden, marker = wrapped(sample)
                torch.testing.assert_close(hidden, reference, rtol=0, atol=0)
                if marker.tolist() != spec["marker_values"]:
                    raise ValueError("Wrapper marker mismatch")
                if not torch.isfinite(hidden).all():
                    raise ValueError("Non-finite uncompressed host output")
                if args.kind == "tiny":
                    references.append({"input": sample.float().tolist(),
                                       "uncompressed_output": hidden.float().tolist()})
        if references:
            report["tiny_vectors"] = references
            report["tiny_max_abs_error_bound"] = 0.05
            report["tiny_bound_scope"] = "Synthetic identity test only, not speech quality"
        report["wrapper_hidden_bit_exact_host"] = True
        with torch.autocast(device_type="cpu", dtype=torch.float16):
            exported = torch.export.export(wrapped, args=(), kwargs={"input_features": samples[0]},
                                           dynamic_shapes={"input_features": {}})
        with torch.inference_mode():
            actual = exported.module()(input_features=samples[0])
            expected = wrapped(samples[0])
            for a, b in zip(actual, expected):
                torch.testing.assert_close(a, b, rtol=0, atol=0)
        report["torch_capture_bit_exact_host"] = True
        program = TorchConverter(mode=TorchConverter.Mode.RELEASE).add_exported_program(
            exported_program=exported.run_decompositions(get_decomp_table()),
            input_names=["input_features"],
            output_names=["encoder_hidden_states", spec["marker_output"]],
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
            source_count = sum(r["elements"] for r in before["eligible"])
            compressed_count = sum(r["elements"] for r in after["compressed"])
            if (not source_count or after["eligible"] or source_count != compressed_count or
                    len(before["eligible"]) != len(after["compressed"])):
                raise ValueError("Incomplete/unexpected compression coverage; inspect report")
        path = args.output_dir / (spec["entrypoint"] + ".aimodel")
        metadata.model_description += f"; {args.format}; named identity ABI; diagnostic only"
        program.save_asset(path, metadata)
        check_contract(inspect_asset(path), spec, args.kind)
        if audit(AIModelAsset.load(path).program, spec["entrypoint"]) != after:
            raise ValueError("Saved graph audit changed")
        report["source"] = bundle_record(path)
        report["status"] = "source-static-only"
        if args.aot:
            destination = args.output_dir / "aot"
            command = ["xcrun", "coreai-build", "compile", str(path), "--platform", "iOS",
                       "--min-deployment-version", "27.0", "--preferred-compute", "gpu",
                       "--architecture", args.architecture, "--output", str(destination)]
            report["aot_command"] = command
            run_command(command, args.output_dir / "aot.log")
            bundles = sorted(destination.glob("*.aimodelc"))
            if len(bundles) != 1:
                raise ValueError("Expected one AOT bundle; inspect compiler output")
            check_contract(inspect_asset(bundles[0]), spec, args.kind)
            report["aot"] = bundle_record(bundles[0])
            report["status"] = "aot-static-only"
        if weights and file_hash(weights) != FROZEN_WEIGHTS:
            raise ValueError("Frozen weights changed during export")
        for name, digest in source_files.items():
            if file_hash(args.model_dir / name) != digest:
                raise ValueError(f"Source configuration changed: {name}")
    except Exception as error:
        report.update(status="failed", error=repr(error))
        raise
    finally:
        logging.getLogger().removeHandler(handler)
        (args.output_dir / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "identity": spec}, indent=2))
    print("Next: audit FP8/INT8 manifests with w8_identity.py; then the native tiny gate. No app is enabled.")


if __name__ == "__main__":
    main()
