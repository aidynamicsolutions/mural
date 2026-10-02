#!/usr/bin/env python3
"""Compare matched, evidence-backed PAL8/PAL4 runs. No inference or promotion.

Input: existing Chinese-ASR predictions format plus a `benchmark` record.
Missing metrics stay unknown. Failed/incomplete/unclean or mismatched runs fail.
Existing evaluate.py supplies the unchanged, script-sensitive accuracy score.
"""
from __future__ import annotations
import argparse
import math
from pathlib import Path
import re
from evaluate import corpus, evaluate, read_json, sha256, tokens, write_json
from breeze_pal4_trial import BASE_MANIFEST

COMMON = ("hardware", "os_build", "app_sha256", "install_id", "runtime_revision",
          "compute", "vad_policy_sha256", "decode_policy_sha256", "corpus_sha256",
          "audio_manifest_sha256", "input_mode", "pair")
HASHES = ("app_sha256", "vad_policy_sha256", "decode_policy_sha256", "corpus_sha256", "audio_manifest_sha256", "model_manifest_sha256")


def require(ok: bool, message: str) -> None:
    if not ok: raise ValueError(message)


def number(value):
    require(type(value) in (int, float) and math.isfinite(value) and value >= 0, "Invalid nonnegative measurement")
    return value


def quantile(values: list[float], p: float):
    if not values: return None
    s = sorted(values); index = (len(s) - 1) * p; low = int(index)
    return s[low] + (s[min(low + 1, len(s) - 1)] - s[low]) * (index - low)


def summary(values):
    return {"n": len(values), "p50": quantile(values, .5), "p95": quantile(values, .95),
            "min": min(values) if values else None, "max": max(values) if values else None}


def reduction(a, b):
    return None if a is None or b is None or a == 0 else 100 * (1 - b / a)


def validate_run(data: dict, expected_arm: str, corpus_hash: str) -> dict:
    require(data.get("complete") is True and not data.get("failure"), "Complete successful run required")
    c = data.get("benchmark", {})
    require(c.get("schema") == "mural.breeze-ab.run.v1" and c.get("arm") == expected_arm, "Wrong benchmark schema/arm")
    require(c.get("physical_device") is True and c.get("hardware") == "iPhone18,3", "This report requires real iPhone 17 evidence")
    require(c.get("cleanup_passed") is True and c.get("safety_stop") is False, "Unclean/safety-stopped runs must be retained as failures")
    require(c.get("corpus_sha256") == corpus_hash, "Frozen corpus hash differs")
    for key in COMMON + ("run_id", "process_start_utc", "evidence_path"):
        require(isinstance(c.get(key), str) and bool(c[key].strip()), f"Missing benchmark context: {key}")
    for key in HASHES:
        require(re.fullmatch(r"[0-9a-f]{64}", c.get(key, "")) is not None, f"Invalid context hash: {key}")
    if expected_arm == "pal8":
        require(c["model_manifest_sha256"] == BASE_MANIFEST, "Wrong reviewed PAL8 baseline manifest")
    require(type(c.get("process_id")) is int and c["process_id"] > 0, "Missing exact native PID")
    require(c.get("input_mode") in ("file-replay", "acoustic"), "Declare the real input mode")
    require(c.get("measurement_scope") == "whole-process", "RAM scope must be whole-process")
    require(c.get("cache_regime") in ("first-artifact-load", "unchanged-install-warm"), "Declare known cache regime")
    for key in ("payload_bytes", "allocated_model_bytes", "attributed_cache_bytes", "wire_bytes",
                "peak_install_staging_bytes", "peak_physical_footprint_bytes", "post_drain_30s_footprint_bytes"):
        if c.get(key) is not None: number(c[key])
    preparations = c.get("preparations", [])
    require(isinstance(preparations, list), "Invalid preparation measurements")
    for item in preparations:
        require(isinstance(item, dict) and item.get("regime") in ("first-artifact-load", "unchanged-install-warm"), "Unknown preparation regime")
        number(item.get("seconds"))
    return c


def latency(rows, left, right, field):
    pairs = []
    for row in rows:
        a, b = left[row["id"]].get(field), right[row["id"]].get(field)
        # Do not silently drop unmatched measurements and score a favorable subset.
        require((a is None) == (b is None), f"Unmatched {field}: {row['id']}")
        if a is not None: pairs.append((number(a), number(b)))
    if not pairs: return {"status": "unmeasured", "n": 0}
    require(len(pairs) == len(rows), f"Partial {field} coverage; separate the incomplete run")
    a, b = [x[0] for x in pairs], [x[1] for x in pairs]
    return {"baseline": summary(a), "candidate": summary(b),
            "paired_delta_seconds": summary([y - x for x, y in pairs]),
            "p95_reduction_percent": reduction(quantile(a, .95), quantile(b, .95))}


def entity_hits(rows, predictions, include_text=False):
    details = []
    for row in rows:
        entities = row.get("entities", [])
        require(isinstance(entities, list) and all(isinstance(e, str) and tokens(e) for e in entities), "Invalid entity annotations")
        hyp = tokens(predictions[row["id"]]["text"])
        for e in entities:
            ref = tokens(e)
            hit = any(hyp[i:i+len(ref)] == ref for i in range(len(hyp)-len(ref)+1))
            detail = {"id": row["id"], "entity_index": len(details), "exact_token_sequence_present": hit}
            if include_text: detail["entity"] = e
            details.append(detail)
    return {"n": len(details), "hits": sum(x["exact_token_sequence_present"] for x in details),
            "note": "Descriptive exact-token entity presence, not a semantic/entity-role accuracy proof", "details": details}


def compare(corpus_path: Path, baseline: dict, candidate: dict, include_text=False) -> dict:
    rows = corpus(corpus_path)
    a = validate_run(baseline, "pal8", sha256(corpus_path)); b = validate_run(candidate, "pal4", sha256(corpus_path))
    for key in COMMON + ("cache_regime",):
        require(a[key] == b[key], f"Confounded comparison: {key}")
    require(a["model_manifest_sha256"] != b["model_manifest_sha256"], "Same model manifest in both arms")
    require(a["process_start_utc"] != b["process_start_utc"] and a["run_id"] != b["run_id"], "Separate native processes/runs required")
    sa, sb = evaluate(rows, baseline, include_text), evaluate(rows, candidate, include_text)
    left = {x["id"]: x for x in baseline["predictions"]}; right = {x["id"]: x for x in candidate["predictions"]}
    for row in rows:
        aa, bb = left[row["id"]], right[row["id"]]
        require(type(aa.get("vad_rejected")) is bool and type(bb.get("vad_rejected")) is bool, "Record VAD outcome, including false rejections")
        require(type(aa.get("first_since_prepare")) is bool and aa.get("first_since_prepare") == bb.get("first_since_prepare"), "Match first/warm inference positions")
        require(number(aa.get("audio_seconds")) == number(bb.get("audio_seconds")), "Match exact fixture durations")
        for pred in (aa, bb):
            require(not pred["vad_rejected"] or pred["text"] == "", "VAD-rejected turn has a transcript")
    buckets = {"all_fixed_corpus": rows}
    for row in rows:
        buckets.setdefault(f"{row['locale']}/{row['group']}", []).append(row)
        duration = left[row["id"]]["audio_seconds"]
        length = "under-2s" if duration < 2 else "2-10s" if duration <= 10 else "over-10s"
        buckets.setdefault("duration/" + length, []).append(row)
        position = "first" if left[row["id"]]["first_since_prepare"] else "warm"
        buckets.setdefault("inference/" + position, []).append(row)
    timing = {}
    for key, subset in buckets.items():
        timing[key] = {field: latency(subset, left, right, field) for field in ("send_to_final_seconds", "asr_including_vad_seconds")}
        # Decoder timing comparisons only for speech accepted by BOTH arms. List exclusions.
        accepted = [r for r in subset if not left[r["id"]]["vad_rejected"] and not right[r["id"]]["vad_rejected"]]
        timing[key]["decode_seconds"] = latency(accepted, left, right, "decode_seconds")
        timing[key]["decoder_excluded_ids"] = [r["id"] for r in subset if r not in accepted]
    metrics = {}
    for key in ("payload_bytes", "allocated_model_bytes", "attributed_cache_bytes", "wire_bytes",
                "peak_install_staging_bytes", "peak_physical_footprint_bytes", "post_drain_30s_footprint_bytes"):
        metrics[key] = {"baseline": a.get(key), "candidate": b.get(key), "reduction_percent": reduction(a.get(key), b.get(key))}
    preparation = {}
    for regime in ("first-artifact-load", "unchanged-install-warm"):
        x = [number(r["seconds"]) for r in a.get("preparations", []) if r["regime"] == regime]
        y = [number(r["seconds"]) for r in b.get("preparations", []) if r["regime"] == regime]
        preparation[regime] = {"baseline": summary(x), "candidate": summary(y),
                                "p50_reduction_percent": reduction(quantile(x, .5), quantile(y, .5))}
    ma, mb = sa["totals"]["mer"], sb["totals"]["mer"]
    newly_hallucinated = [r["id"] for r in rows if r["group"] == "silence" and not left[r["id"]]["text"].strip() and right[r["id"]]["text"].strip()]
    return {"schema": "mural.breeze-ab.report.v1", "automatically_promoted": False,
            "accuracy": {"baseline": sa, "candidate": sb, "delta_mer_percentage_points": None if ma is None or mb is None else 100 * (mb-ma),
                         "new_nonempty_silence_ids": newly_hallucinated,
                         "changed_ids": [r["id"] for r in rows if left[r["id"]]["text"] != right[r["id"]]["text"]],
                         "baseline_entities": entity_hits(rows, left, include_text), "candidate_entities": entity_hits(rows, right, include_text)},
            "timing": timing, "resources": metrics, "preparation": preparation,
            "provenance": {"baseline": a, "candidate": b},
            "limitations": ["Measurement receipts are caller-supplied: inspect exact-PID native logs and capture provenance.",
                            "Small corpus p95 is descriptive, not a production tail estimate or confidence interval.",
                            "Physical footprint is whole-process, not compressed weights or model-only RAM.",
                            "Metadata-declared first loads do not establish internally cold Core ML caches.",
                            "Review English spans, critical names/numbers/negation and lifecycle separately."]}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("corpus", type=Path); p.add_argument("baseline", type=Path); p.add_argument("candidate", type=Path)
    p.add_argument("--output", required=True, type=Path); p.add_argument("--include-text", action="store_true")
    args=p.parse_args()
    try:
        write_json(args.output, compare(args.corpus, read_json(args.baseline), read_json(args.candidate), args.include_text))
    except (OSError, ValueError, KeyError, TypeError) as e: p.exit(2, f"error: {e}\n")

if __name__ == "__main__": main()
