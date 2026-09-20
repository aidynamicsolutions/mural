#!/usr/bin/env python3
"""Local-only Mandarin/English ASR checks. No downloads or third-party packages.

MER uses one Han character or one Latin/number word per token. Traditional and
Simplified characters remain distinct. This is a declared local metric, not a
reproduction of any publisher's benchmark. Missing predictions are errors;
explicit empty predictions are scored as deletions. Silence is scored separately.
"""
from __future__ import annotations

import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import unicodedata
import wave

GROUPS = {"zh", "en", "zh-en", "en-zh", "multi-switch", "short", "silence"}


def read_json(path: Path):
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"Duplicate JSON key: {key}")
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def han(char: str) -> bool:
    return unicodedata.name(char, "").startswith(("CJK UNIFIED IDEOGRAPH", "CJK COMPATIBILITY IDEOGRAPH"))


def tokens(text: str) -> list[str]:
    # NFC, not NFKC: don't silently change script or compatibility characters.
    text = unicodedata.normalize("NFC", text).casefold().replace("’", "'")
    result, word = [], []
    for index, char in enumerate(text):
        if han(char):
            if word:
                result.append("".join(word)); word = []
            result.append(char)
        elif char.isalnum() or (unicodedata.category(char).startswith("M") and word):
            word.append(char)
        elif char == "'" and word and index + 1 < len(text) and text[index + 1].isalpha():
            word.append(char)
        elif word:
            result.append("".join(word)); word = []
    if word:
        result.append("".join(word))
    return result


def edits(reference: list[str], hypothesis: list[str]) -> int:
    previous = list(range(len(hypothesis) + 1))
    for i, left in enumerate(reference, 1):
        current = [i]
        for j, right in enumerate(hypothesis, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1,
                               previous[j - 1] + (left != right)))
        previous = current
    return previous[-1]


def corpus(path: Path) -> list[dict]:
    data = read_json(path)
    if not isinstance(data, dict) or data.get("schema") != "mural.chinese-asr.corpus.v1":
        raise ValueError("Expected mural.chinese-asr.corpus.v1")
    rows = data.get("clips")
    if not isinstance(rows, list) or not rows:
        raise ValueError("Corpus must contain clips")
    seen = set()
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("Each clip must be an object")
        identity = row.get("id")
        if not isinstance(identity, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", identity):
            raise ValueError("Clip ID must contain 1-80 ASCII letters, digits, underscores or hyphens")
        if identity in seen:
            raise ValueError(f"Duplicate clip ID: {identity}")
        seen.add(identity)
        if row.get("group") not in GROUPS or row.get("locale") not in {"zh-TW", "zh-CN"}:
            raise ValueError(f"Invalid group/locale: {identity}")
        if not isinstance(row.get("reference"), str):
            raise ValueError(f"Missing reference: {identity}")
        if (row["group"] == "silence") != (not row["reference"].strip()):
            raise ValueError(f"Only silence clips may have empty references: {identity}")
        if row["group"] != "silence" and not tokens(row["reference"]):
            raise ValueError(f"Speech reference has no scored tokens: {identity}")
        if not isinstance(row.get("speaker"), str) or not row["speaker"].strip():
            raise ValueError(f"Missing anonymous speaker label: {identity}")
        relative = row.get("wav")
        if not isinstance(relative, str) or "\\" in relative:
            raise ValueError(f"Invalid WAV path: {identity}")
        parts = relative.split("/")
        if not relative.endswith(".wav") or any(part in {"", ".", ".."} for part in parts):
            raise ValueError(f"WAV path must be relative without traversal: {identity}")
    return rows


def audio_path(root: Path, relative: str) -> Path:
    root = root.resolve(strict=True)
    path = (root / relative).resolve(strict=True)
    if not path.is_relative_to(root) or not path.is_file():
        raise ValueError("Audio path leaves the corpus directory")
    return path


def pcm16(path: Path) -> tuple[array, float]:
    with wave.open(str(path), "rb") as handle:
        frames = handle.getnframes()
        if (handle.getnchannels(), handle.getsampwidth(), handle.getframerate(), handle.getcomptype()) != (1, 2, 16000, "NONE"):
            raise ValueError(f"Require mono 16 kHz PCM16 WAV: {path.name}")
        if not 0 < frames <= 480_000:
            raise ValueError(f"Require 0 < duration <= 30 seconds: {path.name}")
        raw = handle.readframes(frames)
        if len(raw) != frames * 2:
            raise ValueError(f"Truncated WAV: {path.name}")
    values = array("h", raw)
    if sys.byteorder != "little":
        values.byteswap()
    return values, frames / 16000.0


def validate_audio(rows: list[dict], root: Path) -> dict:
    clips = []
    for row in rows:
        path = audio_path(root, row["wav"])
        _, seconds = pcm16(path)
        clips.append({"id": row["id"], "seconds": seconds, "sha256": sha256(path)})
    return {"clip_count": len(clips), "audio_seconds": sum(x["seconds"] for x in clips), "clips": clips}


def evaluate(rows: list[dict], predictions: dict, include_text: bool = False) -> dict:
    if not isinstance(predictions, dict) or predictions.get("schema") != "mural.chinese-asr.predictions.v1":
        raise ValueError("Expected mural.chinese-asr.predictions.v1")
    if predictions.get("complete") is False or "failure" in predictions:
        raise ValueError("Incomplete or failed run cannot be scored as successful evidence")
    incoming = predictions.get("predictions")
    if not isinstance(incoming, list):
        raise ValueError("Missing predictions list")
    found = {}
    for item in incoming:
        if not isinstance(item, dict) or not isinstance(item.get("id"), str):
            raise ValueError("Invalid prediction object/ID")
        identity = item["id"]
        if identity in found:
            raise ValueError(f"Duplicate prediction: {identity}")
        if item.get("error") or not isinstance(item.get("text"), str):
            raise ValueError(f"Failed or missing transcript: {identity}; retain the failure, do not score it as success")
        for key in ("decode_seconds", "send_to_final_seconds", "peak_footprint_bytes"):
            if key in item and (type(item[key]) not in (int, float) or not math.isfinite(item[key]) or item[key] < 0):
                raise ValueError(f"Invalid {key}: {identity}")
        found[identity] = item
    expected = {row["id"] for row in rows}
    if set(found) != expected:
        raise ValueError(f"ID mismatch: missing={sorted(expected - set(found))}, extra={sorted(set(found) - expected)}")
    totals = {"edits": 0, "reference_tokens": 0, "speech_clips": 0, "normalized_matches": 0,
              "silence_clips": 0, "silence_nonempty": 0}
    groups, details = {}, []
    for row in rows:
        item = found[row["id"]]
        reference, hypothesis = tokens(row["reference"]), tokens(item["text"])
        detail = {"id": row["id"], "locale": row["locale"], "group": row["group"]}
        if row["group"] == "silence":
            nonempty = bool(item["text"].strip())  # Even punctuation-only output is visible to the user.
            totals["silence_clips"] += 1
            totals["silence_nonempty"] += nonempty
            detail["nonempty_on_silence"] = nonempty
        else:
            count = edits(reference, hypothesis)
            detail.update(edits=count, reference_tokens=len(reference), normalized_match=reference == hypothesis)
            bucket = groups.setdefault(f"{row['locale']}/{row['group']}", {"edits": 0, "reference_tokens": 0, "clips": 0})
            bucket["edits"] += count; bucket["reference_tokens"] += len(reference); bucket["clips"] += 1
            totals["edits"] += count; totals["reference_tokens"] += len(reference)
            totals["speech_clips"] += 1; totals["normalized_matches"] += reference == hypothesis
        if include_text:
            detail.update(reference=row["reference"], hypothesis=item["text"])
        details.append(detail)
    for bucket in groups.values():
        bucket["mer"] = bucket["edits"] / bucket["reference_tokens"]
    totals["mer"] = totals["edits"] / totals["reference_tokens"] if totals["reference_tokens"] else None
    return {"schema": "mural.chinese-asr.score.v1", "normalization": "NFC + casefold; Han characters + words; no script conversion",
            "totals": totals, "groups": groups, "clips": details,
            "note": "Descriptive accuracy only. No automatic promotion; review English preservation and latency separately."}


def write_json(path: Path, value: dict) -> None:
    # Never overwrite a prior recording run or ground truth.
    with path.open("x", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2, allow_nan=False)
        handle.write("\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    check = sub.add_parser("check-audio")
    check.add_argument("corpus", type=Path); check.add_argument("audio_root", type=Path)
    check.add_argument("--output", type=Path, required=True)
    score = sub.add_parser("score")
    score.add_argument("corpus", type=Path); score.add_argument("predictions", type=Path)
    score.add_argument("--output", type=Path, required=True)
    score.add_argument("--include-text", action="store_true", help="Private local report only; never commit it")
    args = parser.parse_args()
    try:
        rows = corpus(args.corpus)
        result = validate_audio(rows, args.audio_root) if args.command == "check-audio" else evaluate(rows, read_json(args.predictions), args.include_text)
        write_json(args.output, result)
        print(f"Wrote {args.output.name}; {len(rows)} clips. No audio or transcripts uploaded.")
    except (ValueError, OSError, wave.Error) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
