#!/usr/bin/env python3
"""Strict native/corpus contrasts for the explicit combined trial.

Pins both actual encoders, verifies terminal/drained success and phase samples,
keeps 017 diagnostic, and allows hidden differences ONLY when encoding changes.
Native quality gates are not benchmarks or ground-truth accuracy claims.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
import statistics

import analyze_asr_trial as old
from combined_trial import COMBINED, ENCODERS as BASE_ENCODERS
from prepare_pal6_decoder_trial import REFERENCE_PIN, CANDIDATE_PIN, read_json, sha

COMBINED4 = "--coreai-w8-v3-combined=pal4-pal4"
PAL4_SUPPORT_PIN = "bbdee2a57bbb29e538389364969e75f731dd4f0baf2dd977830f966857095702"
ENCODERS = {
    **BASE_ENCODERS,
    "pal4": {
        "manifest": "96c7c788ec49b76aa8a4d52ac961a1f93869676d05fcb5109eeb8be581bf765f",
        "entrypoint": "mural_v3_encoder_pal4_packed_929ba0c6ad9cee6b808c",
        "aot_fingerprint": "f5d9a29d1cbe0f9e1e10ceeb38a2dc55881c043d188194f57378a70192c4c4d1",
        "aot_bytes": 323_253_517,
        "width": 64,
    },
}
SUPPORT_PINS = {"pal8": REFERENCE_PIN, "pal6": CANDIDATE_PIN, "pal4": PAL4_SUPPORT_PIN}
CONTRASTS = {
    "combined": (("fp8", "pal8"), ("pal6", "pal6")),
    "encoder-at-pal6": (("fp8", "pal6"), ("pal6", "pal6")),
    "decoder-at-pal6": (("pal6", "pal8"), ("pal6", "pal6")),
    "combined-pal4": (("fp8", "pal8"), ("pal4", "pal4")),
    "encoder-at-pal4": (("fp8", "pal4"), ("pal4", "pal4")),
}
COMBINED_FLAGS = {("pal6", "pal6"): COMBINED, ("pal4", "pal4"): COMBINED4}


def selected(context, prefix):
    values = [v[len(prefix):] for v in context["launch_arguments"] if v.startswith(prefix)]
    if len(values) != 1:
        raise ValueError(f"Require one explicit {prefix} in the actual launch arguments")
    return values[0]


def classify(context):
    enc = selected(context, "--coreai-w8-v3-encoder=")
    dec = selected(context, "--coreai-w8-v3-decoder=")
    policy = selected(context, "--coreai-w8-v3-prewarm=")
    if enc not in ENCODERS or dec not in SUPPORT_PINS or policy not in {"always", "once"}:
        raise ValueError("Unsupported explicit precision or policy")
    joint_flags = [s for s in context["launch_arguments"] if s.startswith("--coreai-w8-v3-combined")]
    expected_joint = COMBINED_FLAGS.get((enc, dec))
    if joint_flags != ([expected_joint] if expected_joint else []):
        raise ValueError("Wrong/missing/stray combined opt-in")
    if selected(context, "--coreai-product-mode=") != "staged-gpu":
        raise ValueError("Only sequential staged-gpu transcription runs can be compared")
    if policy != context.get("prewarm_policy"):
        raise ValueError("Context policy contradicts actual launch")
    return enc, dec, policy


def digest_list(values, label):
    if not isinstance(values, list) or not values or not all(isinstance(x, str) and re.fullmatch(r"[0-9a-f]{64}", x) for x in values):
        raise ValueError(f"Missing/malformed {label}")


def read_run(directory: Path, native=False):
    root = read_json(directory / "report.json")
    r = root.get("productGate", {})
    if (r.get("terminal") is not True or r.get("status") != "complete" or r.get("stateAtEnd") != "idle"
        or r.get("errors") != [] or r.get("cancellation") is not None or root.get("error") is not None
        or type(root.get("memoryWarnings")) is not int or root["memoryWarnings"] != 0
        or r.get("mode") != "staged-gpu" or r.get("lifecycle") != "recreate"):
        raise ValueError("Not a complete terminal/drained/warning-free sequential run")
    context = read_json(directory / "trial-context.json")
    if not isinstance(context.get("launch_arguments"), list) or not all(isinstance(x, str) for x in context["launch_arguments"]):
        raise ValueError("Missing actual launch arguments")
    for field in (*old.CONTEXT_MATCH, "process_session_id"):
        if not context.get(field):
            raise ValueError(f"Missing context {field}")
    for key, size in (("source_commit", 40), ("app_executable_sha256", 64)):
        if not re.fullmatch(r"[0-9a-f]{"+str(size)+"}", context[key]):
            raise ValueError(f"Bad context {key}")
    enc, dec, policy = classify(context)
    pin = ENCODERS[enc]
    if (root.get("runID") != r.get("runID") or not r.get("runID") or r.get("architecture") != "h18p"
        or r.get("encoderArtifactSHA256") != pin["aot_fingerprint"]
        or r.get("expectedEncoderArtifactSHA256") != pin["aot_fingerprint"]
        or r.get("supportManifestSHA256") != SUPPORT_PINS[dec]
        or not r.get("modelPrecision", "").startswith(f"v3 packed {enc} encoder,")):
        raise ValueError("Wrong pinned precision, architecture or run identity")
    expected = ["001.wav", "001.wav"] if native else old.EXPECTED
    if r.get("corpusRequested") is not (not native) or [t.get("file") for t in r["turns"]] != expected:
        raise ValueError("Wrong native two-turn/corpus cohort")
    args = context["launch_arguments"]
    if args.count("--coreai-product-corpus") != (0 if native else 1):
        raise ValueError("Cohort flags contradict report")
    if native and (selected(context, "--coreai-product-turns=") != "2" or r.get("requestedTurns") != 2):
        raise ValueError("Native gate requires exactly two fixture-001 turns")
    count = len(expected)
    if [t.get("turn") for t in r["turns"]] != list(range(1, count+1)) or [p.get("index") for p in r["preparations"]] != list(range(1, count+1)):
        raise ValueError("Missing/duplicate/reordered turns or preparations")
    events = []
    with (directory / "events.jsonl").open() as f:
        for line in f:
            if not line.strip(): continue
            e = json.loads(line)
            if e.get("runID") == r["runID"] and "sessionID" in e:
                events.append(e)
    if not events or len({e["sessionID"] for e in events}) != 1:
        raise ValueError("Missing/mixed session evidence")
    last = -1.0
    for e in events:
        now = old.number(e.get("uptime"), "uptime")
        if now < last: raise ValueError("Non-monotonic events")
        last = now
        if type(e.get("thermalState")) is not int or not 0 <= e["thermalState"] <= 3:
            raise ValueError("Missing thermal observation")
    rows = []
    for t, prep in zip(r["turns"], r["preparations"]):
        i = t["turn"]
        if (t.get("error") is not None or not isinstance(t.get("rawTranscript"), str)
            or not isinstance(t.get("normalizedTranscript"), str)
            or t.get("termination") not in ({"endToken", "tokenLimit"} if t["file"] == "017.wav" else {"endToken"})):
            raise ValueError("Incomplete transcript; retain failure separately, never hide it in averages")
        digest_list([t.get("audioSHA256")], "audio digest")
        for field in ("melSHA256", "encoderHiddenSHA256"): digest_list(t.get(field), field)
        def event(stage, **fields): return old.event_for(events, i, stage, **fields)
        response = event("encoder-response-verified")
        load = event("encoder-load-complete")
        encoded = event("encoder-run-end")
        released = event("encoder-post-release-footprint")
        resident = event("whisperkit-load-complete", phase="models")
        decoded = event("decoder-run-end", phase="text")
        full = event("staged-asr-full-complete")
        if (response.get("format") != enc or response.get("packetElements") != 1_920_000+pin["width"]
            or response.get("challengeSeed") != i & 31 or encoded.get("hiddenElements") != 1_920_000
            or load.get("function") != pin["entrypoint"] or load.get("cacheHit") is not True
            or old.number(load.get("specializationSeconds"), "specialization") != 0):
            raise ValueError("Unverified packet/cache/named function; specialization is not inference")
        if (full.get("file") != t["file"] or full.get("scope") != "after-audio-read-through-encoder-prepare-decoder-not-UI-send"):
            raise ValueError("Wrong full-harness timing definition")
        timings = t["timings"]
        row = {"file": t["file"], "turn": i, "termination": t["termination"],
            "staged_full_seconds": old.number(full.get("seconds"), "full", positive=True),
            "replay_pipeline_seconds_not_send": old.number(timings.get("totalSeconds"), "replay", positive=True),
            "encoder_native_seconds": old.number(response.get("nativeSeconds"), "native", positive=True),
            "encoder_validation_copy_seconds": old.number(response.get("validationCopySeconds"), "copy"),
            "encoder_function_load_seconds": old.number(load.get("functionLoadSeconds"), "function load"),
            "encoder_cache_lookup_seconds": old.number(load.get("cacheLookupSeconds"), "lookup"),
            "decoder_seconds": old.number(timings.get("decoderSeconds"), "decoder", positive=True),
            "decoder_load_seconds": old.number(prep.get("whisperKitLoadSeconds"), "decoder load"),
            "decoder_prewarm_seconds": old.number(prep.get("whisperKitPrewarmSeconds"), "prewarm"),
            "thermal_before": t["thermalBefore"], "thermal_after": t["thermalAfter"]}
        for label, e in (("encoder_response", response), ("encoder_post_release", released),
                         ("decoder_loaded", resident), ("decoder_text_end", decoded)):
            row[label+"_footprint_bytes"] = old.number(e.get("memory", {}).get("footprintBytes"), label, positive=True)
        if row["staged_full_seconds"] < max(row["encoder_native_seconds"], row["replay_pipeline_seconds_not_send"]):
            raise ValueError("Impossible nested timings")
        rows.append(row)
    if native:
        a, b = r["turns"]
        if any(a[k] != b[k] for k in ("audioSHA256", "melSHA256", "encoderHiddenSHA256", "rawTranscript", "generatedTokens", "detectedLanguages")):
            raise ValueError("Native repeated input/output identity changed across challenges")
        if any(t["rawTranscript"] != "Yesterday I went to the supermarket." for t in r["turns"]):
            raise ValueError("Native fixture-001 transcript gate failed")
    return {"context": context, "report": r, "rows": rows, "classification": (enc, dec, policy),
            "process_lifetime_rss_peak_bytes": max(old.number(e.get("memory", {}).get("processRSSPeakBytes"), "RSS", positive=True) for e in events),
            "evidence": {f: sha(directory/f) for f in ("report.json", "events.jsonl", "trial-context.json")},
            "native": native}


def aggregate(rows, native):
    if not native: return old.aggregate(rows)
    keys = [k for k in rows[0] if k.endswith(("_seconds", "_bytes")) or k == "replay_pipeline_seconds_not_send"]
    return {"native_two_turns_not_corpus": {k: old.summary([r[k] for r in rows]) for k in keys},
            "first_turn": rows[0], "second_turn": rows[1]}


def compare(a, b, contrast):
    ca, cb = a["context"], b["context"]
    ra, rb = a["report"], b["report"]
    if a["native"] != b["native"] or ra["runID"] == rb["runID"] or ca["process_session_id"] == cb["process_session_id"]:
        raise ValueError("Unmatched cohorts or reused run/process")
    for field in old.CONTEXT_MATCH:
        if ca[field] != cb[field]: raise ValueError(f"Unmatched context: {field}")
    for field in ("architecture", "tokenizer", "melBoundary", "decodingOptions", "lifecycle"):
        if ra[field] != rb[field]: raise ValueError(f"Unmatched runtime: {field}")
    ae, ad, ap = a["classification"]; be, bd, bp = b["classification"]
    if contrast == "prewarm":
        if (ae, ad) != (be, bd) or (ap, bp) != ("always", "once"):
            raise ValueError("Policy contrast must hold BOTH artifacts fixed")
        changed = ["--coreai-w8-v3-prewarm="]
    else:
        if ((ae, ad), (be, bd)) != CONTRASTS[contrast] or (ap, bp) != ("always", "always"):
            raise ValueError("Wrong precision contrast or changed prewarm policy")
        changed = (["--coreai-w8-v3-encoder="] if ae != be else []) + (["--coreai-w8-v3-decoder="] if ad != bd else [])
        # The extra safety opt-in is mandatory for C and absent on the controls.
        changed += ["--coreai-w8-v3-combined="]
    def stable(ctx): return sorted(x for x in ctx["launch_arguments"] if not any(x.startswith(p) for p in changed))
    if stable(ca) != stable(cb): raise ValueError("Unmatched launcher options outside the selected contrast")
    differences, matches = [], 0
    for x, y in zip(ra["turns"], rb["turns"]):
        for key in ("file", "audioSHA256", "sampleCount", "melSHA256"):
            if not x.get(key) or x[key] != y.get(key): raise ValueError(f"Input mismatch: {key}")
        if ae == be and x["encoderHiddenSHA256"] != y["encoderHiddenSHA256"]:
            raise ValueError("Fixed encoder hidden states changed")
        scored = x["file"] != "017.wav"
        if scored and x["normalizedTranscript"] == y["normalizedTranscript"]: matches += 1
        keys = ("rawTranscript", "normalizedTranscript", "generatedTokens", "detectedLanguages", "termination")
        if any(x[k] != y[k] for k in keys):
            differences.append({"file": x["file"], "turn": x["turn"], "scored": scored,
                "reference": {k: x[k] for k in keys}, "candidate": {k: y[k] for k in keys}})
    if a["native"] and differences: raise ValueError("Native quality gate has a transcript/token/language difference")
    aa, bb = aggregate(a["rows"], a["native"]), aggregate(b["rows"], b["native"])
    group = "native_two_turns_not_corpus" if a["native"] else "scored"
    changes = {k: 100*(bb[group][k]["mean"]/v["mean"]-1) for k, v in aa[group].items() if v["mean"] > 0}
    return {"reference_run": ra["runID"], "candidate_run": rb["runID"], "contrast": contrast,
        "normalized_agreement": {"matches": matches, "denominator": 2 if a["native"] else 21, "not_ground_truth_accuracy": True},
        "differences": differences, "reference": aa, "candidate": bb,
        "run_mean_changes_percent": changes, "process_lifetime_rss_peak_bytes": {
            "reference": a["process_lifetime_rss_peak_bytes"], "candidate": b["process_lifetime_rss_peak_bytes"]},
        "evidence": {"reference": a["evidence"], "candidate": b["evidence"]},
        "disposition": "Native gate only; reviewer must assess resource tradeoff" if a["native"] else "PENDING human/resource/lifecycle review"}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--kind", choices=("native", "corpus"), required=True)
    p.add_argument("--contrast", choices=(*CONTRASTS, "prewarm"), required=True)
    p.add_argument("--reference-run", type=Path, action="append", required=True)
    p.add_argument("--candidate-run", type=Path, action="append", required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    try:
        if len(a.reference_run) != len(a.candidate_run): raise ValueError("Unpaired runs")
        left = [read_run(d, a.kind == "native") for d in a.reference_run]
        right = [read_run(d, a.kind == "native") for d in a.candidate_run]
        for values in ([r["report"]["runID"] for r in left+right], [r["context"]["process_session_id"] for r in left+right]):
            if len(values) != len(set(values)): raise ValueError("Repeated run/process across pairs")
        pairs = [compare(x, y, a.contrast) for x, y in zip(left, right)]
        keys = set.intersection(*(set(r["run_mean_changes_percent"]) for r in pairs))
        result = {"schema": "mural-combined-comparison-v1", "kind": a.kind, "contrast": a.contrast, "pairs": pairs,
            "descriptive_run_level_changes": {k: old.summary([r["run_mean_changes_percent"][k] for r in pairs]) for k in sorted(keys)},
            "scope": "Staged harness after audio read; not UI Send-to-final. RSS and phase samples are distinct.",
            "promotion": "NOT AUTOMATIC; no independent effect attributed to a two-component swap"}
        with a.output.open("x") as f: json.dump(result, f, indent=2, allow_nan=False); f.write("\n")
        print(a.output)
    except (OSError, ValueError, KeyError, TypeError) as e:
        p.exit(1, f"Combined analysis blocked: {e}\n")

if __name__ == "__main__":
    main()
