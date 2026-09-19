#!/usr/bin/env python3
"""Portable host tests. No Apple export, native inference or iPhone claims."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

import torch
from pal6_contract import SETTINGS as PAL6_SETTINGS, identity as pal6_identity
from pal4_contract import SETTINGS as PAL4_SETTINGS, identity as pal4_identity
from w8_runtime_identity import (SCHEMA, BLOCKED_V1, identity, validate_spec, challenge,
    expected_response, require_response, build_wrapper, unpack_host, validate_capture,
    check_contract, bundle_record, audit_reports, canonical)


def recipe(fmt="fp8", transport="packed"):
    return {"kind": "tiny", "format": fmt, "transport": transport,
            "control": {"kind": "tiny", "transport": transport, "compiler": "synthetic-test-only"}}


def body_for(fmt):
    code = {"fp16": 1, "fp8": 2, "int8": 3, "pal4": 4}[fmt]
    body = torch.nn.Linear(64, 64).half().eval().requires_grad_(False)
    with torch.no_grad():
        body.weight.zero_()
        for i in range(64):
            body.weight[i, i] = code
            body.weight[i, (i + 1) % 64] = -0.5 * code
        body.bias.fill_(code)
    return body


class IdentityTests(unittest.TestCase):
    def test_digest_abi_and_response_validation(self):
        for fmt in ("fp16", "fp8", "int8", "pal4"):
            spec = identity(recipe(fmt))
            validate_spec(spec)
            nonce = challenge(spec, 7)
            response = expected_response(spec, nonce)
            require_response(spec, nonce, response)
            self.assertTrue(all(float(torch.tensor(v, dtype=torch.float16)) == v for v in response))
            with self.assertRaises(ValueError):
                require_response(spec, challenge(spec, 23), response)
            bad = copy.deepcopy(spec); bad["marker_values"][0] += 1
            with self.assertRaises(ValueError): validate_spec(bad)
            bad = copy.deepcopy(spec); bad["marker_dtype"] = "int32"
            with self.assertRaises(ValueError): validate_spec(bad)

    def test_bad_challenges_and_nonfinite(self):
        spec = identity(recipe())
        good = challenge(spec, 0)
        for item in (float("nan"), float("inf"), 32, -1, 0.5, True):
            bad = list(good); bad[0] = item
            with self.assertRaises(ValueError): expected_response(spec, bad)
        bad_response = expected_response(spec, good); bad_response[0] = float("nan")
        with self.assertRaises(ValueError): require_response(spec, good, bad_response)

    def test_real_torch_export_both_transports_all_formats(self):
        for transport in ("packed", "split"):
            for fmt in ("fp16", "fp8", "int8", "pal4"):
                with self.subTest(transport=transport, fmt=fmt):
                    spec = identity(recipe(fmt, transport))
                    body = body_for(fmt)
                    wrapped = build_wrapper(body, spec)
                    samples = [torch.zeros(1, 64).half(), torch.ones(1, 64).half(),
                               torch.linspace(-0.5, 0.5, 64).half().reshape(1, 64)]
                    kwargs = {"input_features": samples[0],
                              "identity_challenge": torch.tensor([challenge(spec, 0)]).half()}
                    exported = torch.export.export(wrapped, args=(), kwargs=kwargs)
                    validate_capture(exported, spec)
                    for sample in samples:
                        for seed in (0, 7, 23):
                            nonce = challenge(spec, seed)
                            output = exported.module()(input_features=sample,
                                identity_challenge=torch.tensor([nonce]).half())
                            hidden = unpack_host(output, spec, nonce)
                            torch.testing.assert_close(hidden, body(sample), rtol=0, atol=0)
                    # Ensure challenge still participates in computation, not just signature.
                    zero = exported.module()(**kwargs)
                    with self.assertRaises(ValueError): unpack_host(zero, spec, challenge(spec, 1))

    def test_packet_corruption_rejected(self):
        spec = identity(recipe())
        nonce = challenge(spec, 0)
        output = build_wrapper(body_for("fp8"), spec)(torch.ones(1, 64).half(), torch.tensor([nonce]).half())
        bad = output.clone(); bad[0, -1] += 1
        with self.assertRaises(ValueError): unpack_host(bad, spec, nonce)
        bad = output.clone(); bad[0, 0] = float("nan")
        with self.assertRaises(ValueError): unpack_host(bad, spec, nonce)
        with self.assertRaises(ValueError): unpack_host(output.float(), spec, nonce)
        with self.assertRaises(ValueError): unpack_host(output[:, :-1], spec, nonce)

    def test_compiler_contract_rejects_old_constant_output(self):
        for transport in ("packed", "split"):
            spec = identity(recipe(transport=transport))
            width = len(spec["marker_values"])
            inputs = [{"name": "input_features", "type": "NDArray (Float16, 1 × 64)"},
                      {"name": "identity_challenge", "type": f"NDArray (Float16, 1 × {width})"}]
            outputs = ([{"name": "encoded_packet", "type": f"NDArray (Float16, 1 × {64 + width})"}]
                       if transport == "packed" else
                       [{"name": "encoder_hidden_states", "type": "NDArray (Float16, 1 × 64)"},
                        {"name": "identity_response", "type": f"NDArray (Float16, 1 × {width})"}])
            summary = {"summary": {"functions": [{"name": spec["entrypoint"], "inputs": inputs, "outputs": outputs}]}}
            check_contract(summary, spec)
            summary["summary"]["functions"][0]["outputs"][-1]["type"] = "NDArray (Int32, 16)"
            with self.assertRaises(ValueError): check_contract(summary, spec)

    def test_artifact_audit_collisions_mutations_and_controls(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            reports = []
            for i, fmt in enumerate(("fp16", "fp8", "int8")):
                r = recipe(fmt)
                report = {"schema": SCHEMA, "status": "aot-static-only", "recipe": r,
                          "control": r["control"], "identity": identity(r)}
                for kind in ("source", "aot"):
                    folder = root / (fmt + kind); folder.mkdir()
                    (folder / "main.hash").write_bytes(bytes([i + 1]) * 32)
                    (folder / ".weights").write_bytes(b"synthetic")
                    report[kind] = bundle_record(folder)
                reports.append(report)
            audit_reports(reports)
            audit_reports(reports[:1], require_triple=False)
            with self.assertRaises(ValueError): audit_reports(reports[:1])
            bad = copy.deepcopy(reports)
            bad[1]["aot"]["native_hashes"] = bad[0]["aot"]["native_hashes"]
            with self.assertRaises(ValueError): audit_reports(bad, rehash=False)
            bad = copy.deepcopy(reports)
            bad[1]["aot"]["native_hashes"][0]["native_bytes_hex"] = BLOCKED_V1
            with self.assertRaises(ValueError): audit_reports(bad, rehash=False)
            (Path(reports[0]["source"]["path"]) / ".weights").write_bytes(b"changed")
            with self.assertRaises(ValueError): audit_reports(reports)
            link = root / "link"; link.symlink_to(root / "fp16source", target_is_directory=True)
            with self.assertRaises(ValueError): bundle_record(link)

    def test_mixed_transport_and_recipe_tamper_rejected(self):
        with self.assertRaises(ValueError): validate_spec({})
        spec = identity(recipe())
        bad = copy.deepcopy(spec); bad["entrypoint"] = "main"
        with self.assertRaises(ValueError): validate_spec(bad)

    def test_swift_portable_verifier(self):
        verifier = Path(__file__).with_name("W8IdentityVerifier.swift")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            specs = [identity(recipe(fmt, transport)) for transport in ("packed", "split")
                     for fmt in ("fp16", "fp8", "int8", "pal4")]
            pal6_recipe = {"kind": "encoder", "format": "pal6", "transport": "packed",
                           "palettization": copy.deepcopy(PAL6_SETTINGS)}
            pal4_recipe = {"kind": "encoder", "format": "pal4", "transport": "packed",
                           "palettization": copy.deepcopy(PAL4_SETTINGS)}
            specs.extend([pal6_identity(pal6_recipe), pal4_identity(pal4_recipe)])
            (root / "specs.json").write_bytes(canonical(specs))
            (root / "main.swift").write_text(r'''
import Foundation
let specs = try JSONDecoder().decode([W8RuntimeIdentitySpec].self,
    from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
func reject(_ body: () throws -> Void) {
    do { try body(); fatalError("Expected rejection") } catch {}
}
for spec in specs where !["pal6", "pal4"].contains(spec.format) {
    try spec.validate()
    try spec.requireFunctions([spec.entrypoint])
    reject { try spec.requireFunctions(["main"]) }
    let nonce = try spec.challenge(seed: 7)
    let response = zip(nonce, spec.markerValues).map { $0 + Float16($1) }
    try spec.requireResponse(response, challenge: nonce)
    reject { try spec.requireResponse(response, challenge: spec.challenge(seed: 23)) }
    let hidden = (0..<64).map { Float16($0) / 8 }
    let values = spec.transport == "packed" ? hidden + response : hidden
    let result = try spec.unpack(values, response: spec.transport == "packed" ? nil : response, challenge: nonce)
    precondition(result == hidden)
    var bad = response; bad[0] = .nan
    reject { try spec.requireResponse(bad, challenge: nonce) }
}
guard let pal6 = specs.first(where: { $0.kind == "encoder" && $0.format == "pal6" && $0.transport == "packed" }),
      let pal4 = specs.first(where: { $0.kind == "encoder" && $0.format == "pal4" && $0.transport == "packed" }) else {
    fatalError("Missing PAL6/PAL4 encoder specs")
}
try pal6.validate()
try pal6.requireFunctions([pal6.entrypoint])
let pal6Nonce = try pal6.challenge(seed: 23)
let pal6Response = zip(pal6Nonce, pal6.markerValues).map { $0 + Float16($1) }
try pal6.requireResponse(pal6Response, challenge: pal6Nonce)
let pal6Hidden = (0..<1_920_000).map { Float16($0 % 257) / 8 }
let pal6Packet = pal6Hidden + pal6Response
let pal6Result = try pal6.unpack(pal6Packet, challenge: pal6Nonce)
precondition(pal6.hiddenShape == [1, 1500, 1280])
precondition(pal6.challengeShape == [1, 56])
precondition(pal6Result == pal6Hidden)
var stale = pal6Packet
stale[1_920_000] += 1
reject { _ = try pal6.unpack(stale, challenge: pal6Nonce) }
try pal4.validate()
try pal4.requireFunctions([pal4.entrypoint])
let pal4Nonce = try pal4.challenge(seed: 23)
let pal4Response = zip(pal4Nonce, pal4.markerValues).map { $0 + Float16($1) }
try pal4.requireResponse(pal4Response, challenge: pal4Nonce)
let pal4Hidden = (0..<1_920_000).map { Float16($0 % 257) / 8 }
let pal4Packet = pal4Hidden + pal4Response
let pal4Result = try pal4.unpack(pal4Packet, challenge: pal4Nonce)
precondition(pal4.hiddenShape == [1, 1500, 1280])
precondition(pal4.challengeShape == [1, 64])
precondition(pal4Result == pal4Hidden)
var stale4 = pal4Packet
stale4[1_920_000] += 1
reject { _ = try pal4.unpack(stale4, challenge: pal4Nonce) }
print("PASS: v3 Swift packed/split extraction plus PAL6/PAL4 encoder [1,1500,1280] and 56/64-value trailers")
''')
            binary = root / "verify"
            subprocess.run(["swiftc", "-D", "MURAL_W8_IDENTITY_PORTABLE_TEST", str(verifier),
                            str(root / "main.swift"), "-o", str(binary)], check=True, timeout=30)
            subprocess.run([str(binary), str(root / "specs.json")], check=True, timeout=10)


if __name__ == "__main__":
    unittest.main()
