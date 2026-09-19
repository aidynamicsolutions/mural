#!/usr/bin/env python3
"""Generate a reviewable patch against 374a7b3. Does not apply or weaken pins.

The small policy source is duplicated in the existing app file, as in the
reviewed baseline. This updates BOTH copies. No Xcode project changes.
"""
from __future__ import annotations
import argparse
import difflib
import hashlib
from pathlib import Path

BASE_BLOBS = {
    "App/LocalConversationEngine.swift": "1cde3da5f81e0fb6b77c52bd28af3bd6db992081",
    "App/MuralApp.swift": "2a7461ccc2678bef80f8c345640c8b7df4f7cc26",
}
OLD_GUARDS = '''            guard decoder != "pal6" || format == "fp8" else {
                throw Failure("Decoder PAL6 qualification fixes the accepted FP8 encoder.")
            }
            guard format != "pal6" || decoder == "pal8" else {
                throw Failure("PAL6 encoder qualification requires the retained PAL8 decoder explicitly.")
            }'''
NEW_GUARDS = '''            try DecoderTrialPolicy.validatePair(encoder: format, decoder: decoder, arguments: arguments)'''
OLD_RECOVERY = '''                if compressed == nil, selection.v3?.format != "pal6", selection.supportIdentity != "phowhisper-cs-pal6-g16-v1", config.mode.hasPrefix("staged"), file.lastPathComponent == "001.wav", !Self.productRecoveryMatches(turn) {'''
NEW_RECOVERY = '''                let requireRecovery: Bool
                if try DecoderTrialPolicy.combined(ProcessInfo.processInfo.arguments) {
                    requireRecovery = !config.corpus // Joint native 001 gate; corpus differences remain reviewable.
                } else {
                    requireRecovery = selection.v3?.format != "pal6" && selection.supportIdentity != "phowhisper-cs-pal6-g16-v1"
                }
                if compressed == nil, requireRecovery, config.mode.hasPrefix("staged"), file.lastPathComponent == "001.wav", !Self.productRecoveryMatches(turn) {'''


def replace_one(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Source drift/already applied: {old[:95]!r}")
    return text.replace(old, new, 1)


def blob(text):
    data = text.encode()
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def patch_sources(sources, policy):
    e = replace_one(sources["App/LocalConversationEngine.swift"], OLD_GUARDS, NEW_GUARDS)
    e = replace_one(e, '$0.hasPrefix("--coreai-w8-v3-encoder=") || $0.hasPrefix("--coreai-w8-v3-decoder=") || $0.hasPrefix("--coreai-w8-v3-prewarm") }',
        '$0.hasPrefix("--coreai-w8-v3-encoder=") || $0.hasPrefix("--coreai-w8-v3-decoder=") || $0.hasPrefix("--coreai-w8-v3-prewarm") || $0.hasPrefix("--coreai-w8-v3-combined") }')
    # Existing policy is appended at EOF. Do not drop unrelated source suffixes.
    marker = '/// Offline qualification policy only.'
    if e.count(marker) != 1 or not e.rstrip().endswith('return flag == prefix + "once"\n    }\n}'):
        raise ValueError("Embedded policy no longer matches the reviewed EOF layout")
    e = e.split(marker)[0] + policy.replace("import Foundation\n", "", 1).lstrip()
    # Content-free correlation: no transcript, microphone or browser timestamp.
    e = replace_one(e, '    private var generation = UUID()',
        '    private var generation = UUID()\n    private var trialFirstAudioGeneration: UUID?')
    old = '                self.logger.notice("local_audio_started send_to_audio_seconds=\\(gap, privacy: .public)")'
    new = old + '''
                if self.trialFirstAudioGeneration != self.generation {
                    self.trialFirstAudioGeneration = self.generation
                    self.logger.notice("asr_trial_audio id=\\(self.generation.uuidString, privacy: .public) uptime=\\(time, privacy: .public) send_to_audio_seconds=\\(gap, privacy: .public)")
                }'''
    e = replace_one(e, old, new)
    m = replace_one(sources["App/MuralApp.swift"], OLD_RECOVERY, NEW_RECOVERY)
    return {"App/LocalConversationEngine.swift": e, "App/MuralApp.swift": m}


def patch_repository(root, policy):
    if any((root/name).is_symlink() for name in BASE_BLOBS):
        raise ValueError("Refuse symlink source")
    sources = {name: (root/name).read_text() for name in BASE_BLOBS}
    for name, content in sources.items():
        if blob(content) != BASE_BLOBS[name]:
            raise ValueError(f"{name} differs from reviewed 374a7b3. Preserve it; inspect/rebase the PATCH, not branch history.")
    patched = patch_sources(sources, policy)
    return ''.join(''.join(difflib.unified_diff(sources[n].splitlines(True), patched[n].splitlines(True),
                      fromfile='a/'+n, tofile='b/'+n)) for n in sources)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repo-root", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    try:
        policy = Path(__file__).with_name("DecoderTrialPolicy.swift").read_text()
        patch = patch_repository(a.repo_root, policy)
        with a.output.open("x") as f:
            f.write(patch)
        print("Generated only. Inspect; git apply --check; apply; run tests and Release build.")
    except (ValueError, OSError) as e:
        p.exit(1, f"Patch blocked: {e}\n")

if __name__ == "__main__":
    main()
