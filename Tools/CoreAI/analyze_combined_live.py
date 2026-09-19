#!/usr/bin/env python3
"""Correlate app ASR and first tutor-audio timers by actual capture ID, not order."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
from uuid import UUID
from analyze_asr_trial import live_metrics, number, summary


def analyze(path):
    asr = live_metrics(path)
    if not asr["timing_sample_valid"]:
        raise ValueError("Incomplete ASR turn or memory warning; preserve failed sample")
    audio = {}
    for line in path.read_text().splitlines():
        m = re.search(r'asr_trial_audio\s+id=([0-9A-Fa-f-]{36})\s+(.*)', line)
        if not m: continue
        token, rest = m.groups()
        token = str(UUID(token))
        if token in audio: raise ValueError("Duplicate first-audio ID")
        fields = dict(re.findall(r'([a-z_]+)=([-+0-9.eE]+)', rest))
        audio[token] = {k: number(float(v), k) for k, v in fields.items()}
    expected = {str(UUID(t["id"])) for t in asr["turns"]}
    if set(audio) != expected:
        raise ValueError("Missing/extra ID-correlated audio; never pair by completed-turn order")
    turns = []
    for row in asr["turns"]:
        value = audio[str(UUID(row["id"]))]
        end = number(value.get("uptime"), "audio uptime")
        seconds = number(value.get("send_to_audio_seconds"), "Send-to-audio", positive=True)
        if abs(end-row["send_uptime"]-seconds) > 0.1 or seconds < row["send_to_final_seconds"]:
            raise ValueError("Invalid monotonic Send/ASR/audio boundaries")
        turns.append({**row, "send_to_first_tutor_audio_seconds": seconds,
            "post_asr_to_audio_seconds_not_pure_tutor_time": seconds-row["send_to_final_seconds"]})
    keys = ("send_to_final_seconds", "send_to_first_tutor_audio_seconds", "post_asr_to_audio_seconds_not_pure_tutor_time")
    return {"schema": "mural-correlated-conversation-timing-v1", "log_sha256": asr["log_sha256"],
        "turns": turns, "all_completed": {k: summary([t[k] for t in turns]) for k in keys},
        "first_turn": turns[0], "warm": {k: summary([t[k] for t in turns[1:]]) for k in keys},
        "scope": "App monotonic timers; no browser delay subtracted; no memory claim; no unpaired speedup claim"}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--log", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    try:
        result = analyze(a.log)
        with a.output.open("x") as f: json.dump(result, f, indent=2, allow_nan=False); f.write("\n")
        print(a.output)
    except (OSError, ValueError, KeyError, TypeError) as e:
        p.exit(1, f"Live analysis blocked: {e}\n")

if __name__ == "__main__": main()
