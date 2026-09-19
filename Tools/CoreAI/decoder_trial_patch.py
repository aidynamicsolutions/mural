#!/usr/bin/env python3
"""Generate, never apply, a narrow patch to the reviewed eb26759 runtime.

PAL6 decoder requires pinned FP8 encoding. A separate opt-in prewarm=once test
skips only redundant hints after a successful same-support prewarm; real model
loads, native drains, decoder unloads, cache policy and warning latches remain.
"""
from __future__ import annotations

import argparse
import difflib
import hashlib
from pathlib import Path

from prepare_pal6_decoder_trial import CANDIDATE_PIN, IDENTITY


def once(text: str, old: str, new: str) -> str:
    count = text.count(old)
    if count != 1:
        raise ValueError(f"Source drift/already applied: expected one anchor, got {count}: {old[:100]!r}")
    return text.replace(old, new, 1)


def patch_engine(text: str, policy: str) -> str:
    text = once(text,
        'guard ["fp16", "pal8"].contains(decoder) else {\n'
        '                throw Failure("The v3 decoder must be fp16 or pal8.")\n'
        '            }',
        'guard ["fp16", "pal8", "pal6"].contains(decoder) else {\n'
        '                throw Failure("The v3 decoder must be fp16, pal8, or pal6.")\n'
        '            }\n'
        '            guard decoder != "pal6" || format == "fp8" else {\n'
        '                throw Failure("Decoder PAL6 qualification fixes the accepted FP8 encoder.")\n'
        '            }')
    text = once(text,
        '        let supportIdentity = decoder == "pal8" ? "phowhisper-cs-pal8-g16-v1" : "phowhisper-cs-fp16-v1"\n'
        '        let supportManifest = decoder == "pal8"\n'
        '            ? "430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336"\n'
        '            : "7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52"',
        '        let supportIdentity: String\n'
        '        let supportManifest: String\n'
        '        switch decoder {\n'
        f'        case "pal6": supportIdentity = "{IDENTITY}"\n'
        f'            supportManifest = "{CANDIDATE_PIN}"\n'
        '        case "pal8": supportIdentity = "phowhisper-cs-pal8-g16-v1"\n'
        '            supportManifest = "430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336"\n'
        '        default: supportIdentity = "phowhisper-cs-fp16-v1"\n'
        '            supportManifest = "7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52"\n'
        '        }')
    text = once(text,
        '        let arguments = ProcessInfo.processInfo.arguments\n        let encoderFlags =',
        '        let arguments = ProcessInfo.processInfo.arguments\n'
        '        _ = try DecoderTrialPolicy.once(arguments) // Reject unsupported/ambiguous policy before loading.\n'
        '        let encoderFlags =')
    text = once(text,
        '$0.hasPrefix("--coreai-w8-v3-encoder=") || $0.hasPrefix("--coreai-w8-v3-decoder=")',
        '$0.hasPrefix("--coreai-w8-v3-encoder=") || $0.hasPrefix("--coreai-w8-v3-decoder=") || $0.hasPrefix("--coreai-w8-v3-prewarm")')
    text = once(text,
        '        private var stagedTokenizer: (any WhisperTokenizer)?',
        '        private var stagedTokenizer: (any WhisperTokenizer)?\n'
        '        private var stagedDecoderPrewarmedAt: URL? // Only successful prewarm, not a retained model.')
    text = once(text,
        '                stagedDirectory = directory; stagedSelection = selection; stagedTokenizer = tokenizer',
        '                stagedDirectory = directory; stagedSelection = selection; stagedTokenizer = tokenizer\n'
        '                stagedDecoderPrewarmedAt = nil')
    text = once(text,
        '                logger.notice("asr_staged_decoder_speculative_complete',
        '                stagedDecoderPrewarmedAt = directory\n'
        '                logger.notice("asr_staged_decoder_speculative_complete')
    text = once(text,
        '                let prewarmStarted = ProcessInfo.processInfo.systemUptime\n'
        '                try await loaded.prewarmModels()\n'
        '                try Task.checkCancellation()\n'
        '                logger.notice("asr_staged_decoder_send_prewarm_complete',
        '                let prewarmStarted = ProcessInfo.processInfo.systemUptime\n'
        '                let reusePrewarm = try DecoderTrialPolicy.once(ProcessInfo.processInfo.arguments)\n'
        '                    && stagedDecoderPrewarmedAt == directory\n'
        '                if !reusePrewarm {\n'
        '                    try await loaded.prewarmModels()\n'
        '                    try Task.checkCancellation()\n'
        '                    stagedDecoderPrewarmedAt = directory\n'
        '                }\n'
        '                try Task.checkCancellation()\n'
        '                logger.notice("asr_trial_prewarm turn=\\(turn, privacy: .public) reused=\\(reusePrewarm, privacy: .public)")\n'
        '                logger.notice("asr_staged_decoder_send_prewarm_complete')
    # Both trial configurations get identical instrumentation. These logs are
    # content-free and tied to the existing random capture generation, not wall
    # clocks from the browser or time at which the agent receives a log batch.
    text = once(text,
        'self.logger.notice("capture_started model=\\(model, privacy: .public) input_hz=\\(format.sampleRate, privacy: .public)")',
        'self.logger.notice("capture_started model=\\(model, privacy: .public) input_hz=\\(format.sampleRate, privacy: .public)")\n'
        '                self.logger.notice("asr_trial_capture id=\\(token.uuidString, privacy: .public) uptime=\\(ProcessInfo.processInfo.systemUptime, privacy: .public)")')
    text = once(text, '        logger.notice("asr_send")',
        '        logger.notice("asr_send")\n'
        '        logger.notice("asr_trial_send id=\\(self.generation.uuidString, privacy: .public) uptime=\\(self.submittedAt!, privacy: .public)")')
    text = once(text, '                if self.asrText.isEmpty { self.asrNotice = "No speech recognized. Try another recording." }',
        '                self.logger.notice("asr_trial_final id=\\(token.uuidString, privacy: .public) uptime=\\(ProcessInfo.processInfo.systemUptime, privacy: .public) send_to_final_seconds=\\(self.finalizeSeconds!, privacy: .public) captured_seconds=\\(self.capturedSeconds, privacy: .public)")\n'
        '                if self.asrText.isEmpty { self.asrNotice = "No speech recognized. Try another recording." }')
    text = once(text, '                self.logger.error("asr_turn_failed")',
        '                self.logger.error("asr_turn_failed")\n'
        '                self.logger.error("asr_trial_failure id=\\(token.uuidString, privacy: .public) uptime=\\(ProcessInfo.processInfo.systemUptime, privacy: .public)")')
    text = once(text,
        '            let encoderTask = Task { try await PhoWhisperStagedEncoder.encode(samples, support: directory, selection: selection, challengeSeed: turn & 31) }',
        '            _ = VietnameseEnglishRecognizer.logMemory(stage: "trial-before-encoder", model: selection.supportIdentity)\n'
        '            let encoderTask = Task { try await PhoWhisperStagedEncoder.encode(samples, support: directory, selection: selection, challengeSeed: turn & 31) }')
    text = once(text, '            logger.notice("asr_staged_encoder_released turn=\\(turn, privacy: .public)")',
        '            logger.notice("asr_staged_encoder_released turn=\\(turn, privacy: .public)")\n'
        '            _ = VietnameseEnglishRecognizer.logMemory(stage: "trial-after-encoder-scope", model: selection.supportIdentity)')
    text = once(text,
        '                guard loaded.textDecoder.logitsSize == 51865 else { throw CocoaError(.fileReadCorruptFile) }',
        '                guard loaded.textDecoder.logitsSize == 51865 else { throw CocoaError(.fileReadCorruptFile) }\n'
        '                _ = VietnameseEnglishRecognizer.logMemory(stage: "trial-decoder-loaded", model: selection.supportIdentity)')
    text = once(text, '                let unloadStarted = ProcessInfo.processInfo.systemUptime',
        '                _ = VietnameseEnglishRecognizer.logMemory(stage: "trial-decoder-finished", model: selection.supportIdentity)\n'
        '                let unloadStarted = ProcessInfo.processInfo.systemUptime')
    text = once(text, '                logger.notice("asr_staged_decoder_unload_complete',
        '                _ = VietnameseEnglishRecognizer.logMemory(stage: "trial-decoder-unloaded", model: selection.supportIdentity)\n'
        '                logger.notice("asr_staged_decoder_unload_complete')
    if "enum DecoderTrialPolicy" in text:
        raise ValueError("DecoderTrialPolicy already integrated")
    return text.rstrip() + "\n\n" + policy.replace("import Foundation\n", "", 1).lstrip()


def patch_probe(text: str) -> str:
    old_sequence_guard = ('                if mode != "staged-gpu-encode" {\n'
                          '                    guard sequence.isEmpty else {\n'
                          '                        throw ProbeError("Staged decoder qualification uses the frozen corpus or fixture-001 turns.")\n'
                          '                    }\n'
                          '                }')
    new_sequence_guard = ('                if mode != "staged-gpu-encode" {\n'
                          '                    guard sequence.isEmpty || sequence.allSatisfy({ $0 == "001.wav" }) else {\n'
                          '                        throw ProbeError("Staged decoder qualification uses the frozen corpus or fixture-001 turns.")\n'
                          '                    }\n'
                          '                }')
    if old_sequence_guard in text:
        text = once(text, old_sequence_guard, new_sequence_guard)
    text = once(text,
        '            if let v3 = selection.v3 {\n                guard v3.format != "pal6" ||',
        '            if let v3 = selection.v3 {\n'
        f'                if v3.supportIdentity == "{IDENTITY}" {{\n'
        '                    guard ["staged-gpu", "staged-gpu-encode"].contains(mode) else {\n'
        '                        throw ProbeError("PAL6 decoder trial requires sequential GPU encoding.")\n'
        '                    }\n'
        '                }\n'
        '                guard v3.format != "pal6" ||')
    text = once(text,
        '        let prewarmTask = Task { try await kit.prewarmModels() }\n'
        '        try await prewarmTask.value\n',
        '        let reusePrewarm = try DecoderTrialPolicy.once(ProcessInfo.processInfo.arguments) && index > 1\n'
        '        if !reusePrewarm {\n'
        '            let prewarmTask = Task { try await kit.prewarmModels() }\n'
        '            try await prewarmTask.value\n'
        '        }\n'
        '        try productEvent("decoder-prewarm-policy", fields: ["reused": reusePrewarm,\n'
        '            "scope": "same-support-prior-successful-turn-real-load-still-required"])\n')
    # A changed fixture 001 must be retained for human quality review, not hidden
    # behind a historical recovery check that aborts all remaining decoder data.
    text = once(text,
        'if compressed == nil, selection.v3?.format != "pal6", config.mode.hasPrefix("staged"), file.lastPathComponent == "001.wav", !Self.productRecoveryMatches(turn) {',
        f'if compressed == nil, selection.v3?.format != "pal6", selection.supportIdentity != "{IDENTITY}", config.mode.hasPrefix("staged"), file.lastPathComponent == "001.wav", !Self.productRecoveryMatches(turn) {{')
    return text


def patch_product_test(text: str) -> str:
    anchor = "swift = " + "'" * 3 + "import Foundation"
    replacement = ("policy = Path(__file__).with_name('DecoderTrialPolicy.swift').read_text()\n"
                   + "swift = policy + " + "'" * 3 + "import Foundation")
    return once(text, anchor, replacement)


def patch_repository(root: Path) -> tuple[str, dict]:
    policy = Path(__file__).with_name("DecoderTrialPolicy.swift").read_text()
    output, hashes = [], {}
    for name, transform in (("App/LocalConversationEngine.swift", lambda t: patch_engine(t, policy)),
                            ("App/MuralApp.swift", patch_probe),
                            ("Tools/CoreAI/test_product_residency.py", patch_product_test)):
        path = root / name
        if path.is_symlink():
            raise ValueError(f"Refuse symlink source: {path}")
        original = path.read_text()
        hashes[name] = hashlib.sha256(original.encode()).hexdigest()
        modified = transform(original)
        output.extend(difflib.unified_diff(original.splitlines(True), modified.splitlines(True),
                                          fromfile="a/" + name, tofile="b/" + name))
    return "".join(output), hashes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()
    try:
        # Preview-only convenience for source review/testing. Actual artifact
        # admission must use prepare_pal6_decoder_trial.py before applying it.
        patch, _ = patch_repository(args.repo_root)
        print(patch, end="")
    except (ValueError, OSError) as exc:
        parser.exit(1, f"Patch not generated: {exc}\n")


if __name__ == "__main__":
    main()
