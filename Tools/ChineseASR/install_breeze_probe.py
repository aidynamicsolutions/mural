#!/usr/bin/env python3
"""Prepare the small Breeze probe integration against the reviewed mvp source.

Default: print the proposed engine diff without changing anything. --apply stages
source changes locally; it does not alter Git refs, models, stores or defaults.
Native build/tests must precede committing these app-source changes.
"""
from __future__ import annotations
import argparse
import difflib
import hashlib
import os
from pathlib import Path
import shutil
import tempfile

BASE_BLOB = "2162ca8d88a5dda8a51487ddd585e4129a6474b3"
CHANGES = [
    ('case phoWhisper = "PhoWhisper CS", parakeet = "Parakeet VI–EN", whisper = "Whisper", nemotron = "Nemotron"',
     'case phoWhisper = "PhoWhisper CS", parakeet = "Parakeet VI–EN", whisper = "Whisper", nemotron = "Nemotron"\n        case breeze = "Breeze TW–EN (probe)"'),
    ('private var parakeet: VietnameseEnglishRecognizer?', 'private var parakeet: VietnameseEnglishRecognizer?\n    private var breeze: BreezeEnglishRecognizer?'),
    ('(asr != nil || whisper != nil || parakeet != nil)', '(asr != nil || whisper != nil || parakeet != nil || breeze != nil)'),
    ('asr == nil && whisper == nil && parakeet == nil', 'asr == nil && whisper == nil && parakeet == nil && breeze == nil'),
    ('asr = nil; whisper = nil; parakeet = nil', 'asr = nil; whisper = nil; parakeet = nil; breeze = nil'),
    ('switch selected {\n                case .phoWhisper:',
     'switch selected {\n                case .breeze:\n                    directory = try await BreezeEnglishRecognizer.localDirectory()\n                case .phoWhisper:'),
    ('switch selected {\n                case .parakeet:',
     'switch selected {\n                case .breeze:\n                    let recognizer = BreezeEnglishRecognizer()\n                    try await recognizer.prepare(directory: directory)\n                    try Task.checkCancellation()\n                    guard self.generation == token else { return }\n                    self.breeze = recognizer\n                    self.preparationDetail += " · Local PAL8 Breeze probe; no hosted fallback."\n                case .parakeet:'),
    ('let manager = asr, whisper = whisper, parakeet = parakeet',
     'let manager = asr, whisper = whisper, parakeet = parakeet, breeze = breeze'),
    ('decoderWarmup: decoderWarmup, parakeet: parakeet, limitSeconds: limit, turnID: token,',
     'decoderWarmup: decoderWarmup, parakeet: parakeet, breeze: breeze, limitSeconds: limit, turnID: token,'),
    ('decoderWarmup: Task<Void, Error>?, parakeet: VietnameseEnglishRecognizer?, limitSeconds: Int, turnID: UUID,',
     'decoderWarmup: Task<Void, Error>?, parakeet: VietnameseEnglishRecognizer?, breeze: BreezeEnglishRecognizer?, limitSeconds: Int, turnID: UUID,'),
    ('} else if let parakeet {\n            turnSamples.append(contentsOf: tail)',
     '} else if let breeze {\n            turnSamples.append(contentsOf: tail)\n            text = try await breeze.transcribe(turnSamples)\n        } else if let parakeet {\n            turnSamples.append(contentsOf: tail)'),
    ('self.asrState = .failed\n                self.logger.error("asr_preparation_failed model=',
     'if selected == .breeze { self.asrError = "Breeze probe preparation failed. Stage its verified local assets and manifest pin; Repair download does not apply. (\\(error.localizedDescription))" }\n                self.asrState = .failed\n                self.logger.error("asr_preparation_failed model=')
]


def transform(source: str) -> str:
    for before, after in CHANGES:
        count = source.count(before)
        if count != 1:
            raise ValueError(f"Expected one integration anchor; found {count}: {before[:90]}")
        source = source.replace(before, after, 1)
    return source


def git_blob(data: bytes) -> str:
    return hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    engine = args.root / "App/LocalConversationEngine.swift"
    destination = args.root / "App/BreezeEnglishRecognizer.swift"
    candidate = Path(__file__).resolve().with_name("BreezeEnglishRecognizer.swift")
    try:
        original = engine.read_bytes()
        if git_blob(original) != BASE_BLOB:
            raise ValueError("Engine differs from reviewed mvp blob. Rebase the small diff explicitly; do not bypass this check or reset user work.")
        if destination.exists():
            raise FileExistsError("Breeze source already exists; inspect the existing integration")
        updated = transform(original.decode("utf-8"))
        print("".join(difflib.unified_diff(original.decode().splitlines(True), updated.splitlines(True),
                                         fromfile="a/App/LocalConversationEngine.swift", tofile="b/App/LocalConversationEngine.swift")))
        if args.apply:
            # Copy first so a failed copy cannot leave an engine referencing a missing type.
            shutil.copyfile(candidate, destination)
            try:
                with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=engine.parent, delete=False) as handle:
                    temporary = Path(handle.name)
                    handle.write(updated)
                try:
                    shutil.copymode(engine, temporary)
                    # Refuse changes made by another editor since the dry-run read.
                    if engine.read_bytes() != original:
                        raise OSError("Engine changed during integration; original file preserved")
                    os.replace(temporary, engine)
                finally:
                    temporary.unlink(missing_ok=True)
            except OSError:
                destination.unlink()
                raise
            print("Applied local probe source. Regenerate the Xcode project using scripts/generate_project.py; review its diff and build before committing.")
        else:
            print("Dry run only. Use --apply after reviewing this diff.")
    except (OSError, ValueError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
