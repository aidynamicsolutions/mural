#!/usr/bin/env python3
"""Audit real FP8/PAL6 artifacts, then emit a narrow reviewable app patch.

No fake pins, automatic source edits, asset staging, cache writes, or installs.
The patch requires `git apply --check` and review on the Mac before application.
"""
from __future__ import annotations

import argparse
import difflib
import json
from pathlib import Path
import re

from pal6_contract import (FP8_MANIFEST, PAL8_MANIFEST, read_pinned, sha256, validate_pair)


def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise ValueError(f"Expected one reviewed source anchor, found {text.count(old)}: {old[:100]}")
    return text.replace(old, new, 1)


def patched_sources(sources: dict[str, str], pin: str) -> dict[str, str]:
    if not re.fullmatch(r"[0-9a-f]{64}", pin) or pin == FP8_MANIFEST:
        raise ValueError("Expected a new real PAL6 manifest SHA-256")
    result = dict(sources)
    path = "Tools/CoreAI/W8IdentityVerifier.swift"
    text = result[path]
    text = replace_once(text, 'let widths = ["fp16": 32, "fp8": 40, "int8": 48]',
                        'let widths = ["fp16": 32, "fp8": 40, "int8": 48, "pal6": 56]')
    text = replace_once(text,
        'shape.allSatisfy({ $0 > 0 && $0 <= 1_920_048 }), shape.reduce(1, *) <= 1_920_048 else {',
        'shape.allSatisfy({ $0 > 0 && $0 <= 1_920_056 }), shape.reduce(1, *) <= 1_920_056 else {')
    result[path] = text
    path = "App/LocalConversationEngine.swift"
    text = result[path]
    text = replace_once(text, 'guard ["fp16", "fp8", "int8"].contains(format) else {',
                        'guard ["fp16", "fp8", "int8", "pal6"].contains(format) else {')
    text = replace_once(text, 'The v3 encoder must be fp16, fp8, or int8.',
                        'The v3 encoder must be fp16, fp8, int8, or pal6.')
    text = replace_once(text, '            return try makeV3Selection(format: format, decoder: decoder)',
        '            guard format != "pal6" || decoder == "pal8" else {\n'
        '                throw Failure("PAL6 encoder qualification requires the retained PAL8 decoder explicitly.")\n'
        '            }\n'
        '            return try makeV3Selection(format: format, decoder: decoder)')
    result[path] = text
    path = "App/MuralApp.swift"
    text = result[path]
    text = replace_once(text,
        '            if let v3 = selection.v3 {\n'
        '                guard ["hybrid", "staged-gpu", "staged-gpu-encode", "encoder-only", "encoder-gpu-only"].contains(mode) else {',
        '            if let v3 = selection.v3 {\n'
        '                guard v3.format != "pal6" || ["staged-gpu", "staged-gpu-encode"].contains(mode) else {\n'
        '                    throw ProbeError("PAL6 qualification requires the sequential GPU-preferred owner.")\n'
        '                }\n'
        '                guard ["hybrid", "staged-gpu", "staged-gpu-encode", "encoder-only", "encoder-gpu-only"].contains(mode) else {')
    # The old staged ProductTurn.totalSeconds starts AFTER encoder execution
    # and decoder preparation. Add a separately named full ASR interval; never
    # relabel historical decoder/replay timings as UI Send-to-final.
    text = replace_once(text, '                let replay: ProductReplayEncoder?',
        '                let stagedASRStarted = ProcessInfo.processInfo.systemUptime\n'
        '                let replay: ProductReplayEncoder?')
    text = replace_once(text, '                report.turns.append(turn)',
        '                report.turns.append(turn)\n'
        '                if config.mode == "staged-gpu" {\n'
        '                    try productEvent("staged-asr-full-complete", fields: [\n'
        '                        "file": file.lastPathComponent,\n'
        '                        "seconds": ProcessInfo.processInfo.systemUptime - stagedASRStarted,\n'
        '                        "scope": "after-audio-read-through-encoder-prepare-decoder-not-UI-send"])\n'
        '                }')
    text = replace_once(text, '        var outputs = try await loaded.function.run(inputs: inputs)\n        let owned: [Float16]',
        '        let nativeStarted = ProcessInfo.processInfo.systemUptime\n'
        '        var outputs = try await loaded.function.run(inputs: inputs)\n'
        '        let nativeSeconds = ProcessInfo.processInfo.systemUptime - nativeStarted\n'
        '        let validationStarted = ProcessInfo.processInfo.systemUptime\n'
        '        let owned: [Float16]')
    text = replace_once(text,
        '            owned = try v3.identity.unpack(packed, challenge: challenge ?? [])\n'
        '            try productEvent("encoder-response-verified", fields: ["format": v3.format,\n'
        '                "challengeSeed": productTurnNumber & 31, "packetElements": packed.count])',
        '            owned = try v3.identity.unpack(packed, challenge: challenge ?? [])\n'
        '            try productEvent("encoder-response-verified", fields: ["format": v3.format,\n'
        '                "challengeSeed": productTurnNumber & 31, "packetElements": packed.count,\n'
        '                "nativeSeconds": nativeSeconds,\n'
        '                "validationCopySeconds": ProcessInfo.processInfo.systemUptime - validationStarted])')
    # PAL6 raw differences go to the full corpus review. Keep the old recovery
    # gate for every existing candidate; do not edit any expected transcript.
    text = replace_once(text,
        '                if compressed == nil, config.mode.hasPrefix("staged"), file.lastPathComponent == "001.wav", !Self.productRecoveryMatches(turn) {',
        '                if compressed == nil, selection.v3?.format != "pal6", config.mode.hasPrefix("staged"), file.lastPathComponent == "001.wav", !Self.productRecoveryMatches(turn) {')
    result[path] = text
    path = "App/W8TinyProbe.swift"
    text = result[path]
    if '"packed:pal6"' in text:
        raise ValueError("PAL6 already pinned; do not replace an existing candidate")
    # The FP8 champion must still have its exact original full-encoder pin.
    full = text.split("static let fullManifestPins:", 1)
    if len(full) != 2 or f'"packed:fp8": "{FP8_MANIFEST}"' not in full[1]:
        raise ValueError("Retained full FP8 pin changed or disappeared")
    text = replace_once(text, '        // END W8_V3_FULL_PINS',
                        f'        "packed:pal6": "{pin}",\n        // END W8_V3_FULL_PINS')
    result[path] = text
    return result


PATHS = ("Tools/CoreAI/W8IdentityVerifier.swift", "App/LocalConversationEngine.swift",
         "App/MuralApp.swift", "App/W8TinyProbe.swift")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference-manifest", required=True, type=Path)
    parser.add_argument("--candidate-manifest", required=True, type=Path)
    parser.add_argument("--pal8-manifest", required=True, type=Path)
    parser.add_argument("--repo-dir", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    if args.output_dir.exists():
        parser.error("Output exists; use a new patch/evidence directory")
    reference = read_pinned(args.reference_manifest, FP8_MANIFEST)
    read_pinned(args.pal8_manifest, PAL8_MANIFEST)
    pin = sha256(args.candidate_manifest)
    candidate = json.loads(args.candidate_manifest.read_text())
    validate_pair(reference, candidate)
    protected = [args.reference_manifest.parent, args.candidate_manifest.parent, args.pal8_manifest.parent]
    protected += [Path(report[k]["path"]) for report in (reference, candidate) for k in ("source", "aot")]
    if any(args.output_dir.resolve().is_relative_to(p.resolve()) for p in protected):
        parser.error("Do not write patch evidence inside immutable model/support directories")
    before = {path: (args.repo_dir / path).read_text() for path in PATHS}
    after = patched_sources(before, pin)
    patch = "".join("".join(difflib.unified_diff(before[p].splitlines(True), after[p].splitlines(True),
                      fromfile="a/" + p, tofile="b/" + p)) for p in PATHS)
    # Recheck inputs after the expensive artifact rehash and before emitting pins.
    if sha256(args.candidate_manifest) != pin:
        raise ValueError("Candidate manifest changed while auditing")
    args.output_dir.mkdir(parents=True, exist_ok=False)
    (args.output_dir / "pal6-runtime.patch").write_text(patch)
    receipt = {"status": "static-pair-audited-patch-not-applied", "device_qualification": "NOT PERFORMED",
               "reference_manifest_sha256": FP8_MANIFEST, "candidate_manifest_sha256": pin,
               "decoder_manifest_sha256": PAL8_MANIFEST,
               "source_file_sha256": {p: sha256(args.repo_dir / p) for p in PATHS},
               "candidate_identity": candidate["identity"], "candidate_aot": candidate["aot"],
               "patch_sha256": sha256(args.output_dir / "pal6-runtime.patch")}
    (args.output_dir / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("Static pair audit passed; runtime patch generated but NOT applied or device-qualified.")
    print(args.output_dir / "pal6-runtime.patch")


if __name__ == "__main__":
    main()
