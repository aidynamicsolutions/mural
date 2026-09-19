#!/usr/bin/env python3
"""Paired, scope-correct corpus measurements and app-monotonic live timings.

Never labels the staged replay timer Send-to-final; never treats asset bytes or
RSS as physical footprint. Missing safety/identity/timing evidence fails closed.
Writes an exclusive JSON result; does not edit references or make a promotion.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re
import statistics

from prepare_pal6_decoder_trial import REFERENCE_PIN, CANDIDATE_PIN, read_json, sha

SCORED = {f"{i:03d}.wav" for i in range(1, 23) if i != 17}
EXPECTED = [f"{i:03d}.wav" for i in range(1, 23)]
CONTEXT_MATCH = ("source_commit", "app_executable_sha256", "device_model", "os_build",
                 "cache_condition", "measurement_protocol")


def number(value, label, *, positive=False):
    if type(value) not in (int, float) or not math.isfinite(value) or value < 0 or (positive and value == 0):
        raise ValueError(f"Missing/invalid {label}: {value!r}")
    return value


def summary(values):
    if not values:
        return None
    return {"count": len(values), "mean": statistics.mean(values),
            "median": statistics.median(values), "min": min(values), "max": max(values)}


def event_for(events, turn, stage, **fields):
    rows = [e for e in events if e.get("turn") == turn and e.get("stage") == stage
            and all(e.get(k) == v for k, v in fields.items())]
    if len(rows) != 1:
        raise ValueError(f"Expected one {stage} event for turn {turn}, got {len(rows)}")
    return rows[0]


def load_run(directory: Path):
    root = read_json(directory / "report.json")
    report = root.get("productGate")
    if (not isinstance(report, dict) or report.get("status") != "complete"
            or report.get("errors") != [] or root.get("error") is not None
            or type(root.get("memoryWarnings")) is not int or root["memoryWarnings"] != 0
            or report.get("cancellation") is not None):
        raise ValueError(f"Incomplete/failed/warning/cancelled run: {directory}")
    if report.get("mode") != "staged-gpu" or not report.get("corpusRequested"):
        raise ValueError("Only complete sequential 22-file corpus runs are comparable here")
    run_id = report["runID"]
    if root.get("runID") != run_id:
        raise ValueError("Outer/inner run identity mismatch")
    turns = report["turns"]
    if [t.get("file") for t in turns] != EXPECTED or [t.get("turn") for t in turns] != list(range(1, 23)):
        raise ValueError("Missing/reordered/duplicate corpus fixtures")
    for t in turns:
        if (t.get("error") is not None or not isinstance(t.get("rawTranscript"), str)
                or not isinstance(t.get("normalizedTranscript"), str)
                or (t["file"] in SCORED and t.get("termination") != "endToken")
                or (t["file"] not in SCORED and t.get("termination") not in {"endToken", "tokenLimit"})):
            raise ValueError("Failed/incomplete transcript; retain it as quality evidence, not a passed benchmark")
    context = read_json(directory / "trial-context.json")
    for key in (*CONTEXT_MATCH, "prewarm_policy", "process_session_id", "launch_arguments"):
        if not context.get(key):
            raise ValueError(f"Missing trial-context.{key}; do not infer test conditions")
    if context["prewarm_policy"] not in {"always", "once"}:
        raise ValueError("Unknown prewarm policy")
    if not isinstance(context["launch_arguments"], list) or not all(isinstance(x, str) for x in context["launch_arguments"]):
        raise ValueError("launch_arguments must be actual launcher arguments")
    for key, width in (("source_commit", 40), ("app_executable_sha256", 64)):
        if not re.fullmatch(r"[0-9a-f]{" + str(width) + r"}", context[key]):
            raise ValueError(f"Invalid {key}")
    def selected(prefix, default=None):
        values = [x[len(prefix):] for x in context["launch_arguments"] if x.startswith(prefix)]
        if len(values) > 1:
            raise ValueError(f"Duplicate launch selector: {prefix}")
        return values[0] if values else default
    encoder = selected("--coreai-w8-v3-encoder=")
    decoder = selected("--coreai-w8-v3-decoder=")
    if (encoder not in {"fp8", "pal6"} or decoder not in {"pal8", "pal6"}
            or not report["modelPrecision"].startswith(f"v3 packed {encoder} encoder,")
            or selected("--coreai-w8-v3-prewarm=", "always") != context["prewarm_policy"]
            or report["encoderArtifactSHA256"] != report["expectedEncoderArtifactSHA256"]):
        raise ValueError("Launch/precision/policy/artifact provenance contradicts report")
    expected_support = REFERENCE_PIN if decoder == "pal8" else CANDIDATE_PIN
    if report["supportManifestSHA256"] != expected_support:
        raise ValueError("Launch decoder does not match pinned support")
    events = []
    with (directory / "events.jsonl").open() as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            try:
                e = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"Truncated event {line_number}") from exc
            if e.get("runID") == run_id and "sessionID" in e:
                events.append(e)
    if not events or len({e["sessionID"] for e in events}) != 1:
        raise ValueError("Missing/mixed product session events")
    previous = -1
    for e in events:
        now = number(e.get("uptime"), "event uptime")
        if now < previous:
            raise ValueError("Out-of-order monotonic events")
        previous = now
    metrics = []
    preparations = report["preparations"]
    if [p.get("index") for p in preparations] != list(range(1, 23)):
        raise ValueError("Missing/reordered preparation records")
    for t, p in zip(turns, preparations):
        i = t["turn"]
        native = event_for(events, i, "encoder-response-verified")
        load = event_for(events, i, "encoder-load-complete")
        full = event_for(events, i, "staged-asr-full-complete")
        resident = event_for(events, i, "whisperkit-load-complete", phase="models")
        encoded = event_for(events, i, "encoder-run-end")
        decoded = event_for(events, i, "decoder-run-end", phase="text")
        if full.get("file") != t["file"] or full.get("scope") != "after-audio-read-through-encoder-prepare-decoder-not-UI-send":
            raise ValueError("Changed/ambiguous full staged timing scope")
        timings = t["timings"]
        row = {"file": t["file"], "turn": i, "termination": t["termination"],
               "staged_full_seconds": number(full.get("seconds"), "staged full", positive=True),
               "replay_pipeline_seconds_not_send": number(timings.get("totalSeconds"), "replay timer", positive=True),
               "encoder_native_seconds": number(native.get("nativeSeconds"), "native encoder", positive=True),
               "encoder_validation_copy_seconds": number(native.get("validationCopySeconds"), "encoder validation/copy"),
               "encoder_lookup_seconds": number(load.get("cacheLookupSeconds"), "cache lookup"),
               "encoder_specialization_seconds": number(load.get("specializationSeconds"), "specialization"),
               "encoder_function_load_seconds": number(load.get("functionLoadSeconds"), "function load"),
               "decoder_seconds": number(timings.get("decoderSeconds"), "decoder", positive=True),
               "decoder_prewarm_seconds": number(p.get("whisperKitPrewarmSeconds"), "prewarm"),
               "decoder_load_seconds": number(p.get("whisperKitLoadSeconds"), "load"),
               "decoder_predictions_seconds": number(timings.get("decodingPredictionsSeconds"), "prediction"),
               "decoder_loop_seconds": number(timings.get("decodingLoopSeconds"), "loop"),
               "generated_token_count": sum(len(x) for x in t["generatedTokens"]),
               "thermal_before": t["thermalBefore"], "thermal_after": t["thermalAfter"]}
        # These are separately named samples, not average-of-every-log-point RAM.
        for label, event in (("encoder_end", encoded), ("decoder_loaded", resident), ("decoder_text_end", decoded)):
            row[label + "_footprint_bytes"] = number(event.get("memory", {}).get("footprintBytes"), label + " footprint", positive=True)
        if row["staged_full_seconds"] < max(row["encoder_native_seconds"], row["replay_pipeline_seconds_not_send"]):
            raise ValueError("Impossible timing nesting")
        if load.get("cacheHit") is not True:
            raise ValueError("Corpus is not a retained-cache run; compare specialization separately")
        metrics.append(row)
    rss = [number(e.get("memory", {}).get("processRSSPeakBytes"), "process RSS", positive=True) for e in events]
    return {"root": directory, "context": context, "report": report, "rows": metrics,
            "process_lifetime_rss_peak_bytes": max(rss),
            "evidence": {n: sha(directory / n) for n in ("report.json", "events.jsonl", "trial-context.json")}}


def aggregate(rows):
    metric_keys = [k for k in rows[0] if k.endswith(("_seconds", "_bytes")) or k == "replay_pipeline_seconds_not_send"]
    scored = [r for r in rows if r["file"] in SCORED]
    return {"scored": {k: summary([r[k] for r in scored]) for k in metric_keys},
            "first_turn": rows[0],
            "warm_scored": {k: summary([r[k] for r in scored if r["turn"] != 1]) for k in metric_keys},
            "diagnostic_017": next(r for r in rows if r["file"] == "017.wav")}


def compare(left, right, phase):
    a, b = left["report"], right["report"]
    ca, cb = left["context"], right["context"]
    if a["runID"] == b["runID"] or ca["process_session_id"] == cb["process_session_id"]:
        raise ValueError("Use distinct fresh process sessions; never duplicate one run as two observations")
    for field in CONTEXT_MATCH:
        if ca[field] != cb[field]:
            raise ValueError(f"Unmatched test conditions: {field}")
    for field in ("architecture", "tokenizer", "melBoundary", "decodingOptions", "lifecycle"):
        if a[field] != b[field]:
            raise ValueError(f"Speech/runtime control differs: {field}")
    if phase == "decoder":
        if not a["modelPrecision"].startswith("v3 packed fp8 encoder,") or not b["modelPrecision"].startswith("v3 packed fp8 encoder,"):
            raise ValueError("Decoder comparison must hold the accepted FP8 encoder fixed")
        if (a["encoderArtifactSHA256"] != b["encoderArtifactSHA256"]
                or a["supportManifestSHA256"] != REFERENCE_PIN or b["supportManifestSHA256"] != CANDIDATE_PIN
                or ca["prewarm_policy"] != cb["prewarm_policy"]):
            raise ValueError("Decoder comparison changed another variable or used unpinned support")
    elif phase == "encoder":
        if (a["supportManifestSHA256"] != REFERENCE_PIN or b["supportManifestSHA256"] != REFERENCE_PIN
                or a["encoderArtifactSHA256"] == b["encoderArtifactSHA256"]
                or ca["prewarm_policy"] != cb["prewarm_policy"]):
            raise ValueError("Encoder comparison must fix the PAL8 decoder and prewarm policy")
    else:
        if (a["encoderArtifactSHA256"] != b["encoderArtifactSHA256"]
                or a["supportManifestSHA256"] != b["supportManifestSHA256"]
                or (ca["prewarm_policy"], cb["prewarm_policy"]) != ("always", "once")):
            raise ValueError("Prewarm comparison must fix both model artifacts")
    # Allow only the explicitly changed launch selection; all other arguments
    # (including diagnostics and cohort controls) must match.
    changed_prefix = {"encoder": "--coreai-w8-v3-encoder=", "decoder": "--coreai-w8-v3-decoder=",
                      "prewarm": "--coreai-w8-v3-prewarm="}[phase]
    def controls(context):
        return sorted(x for x in context["launch_arguments"] if not x.startswith(changed_prefix))
    if controls(ca) != controls(cb):
        raise ValueError("Unmatched launcher arguments outside the selected experimental variable")
    differences = []
    normalized_agreement = 0
    for x, y in zip(a["turns"], b["turns"]):
        for key in ("file", "audioSHA256", "sampleCount", "melSHA256"):
            if not x.get(key) or x[key] != y.get(key):
                raise ValueError(f"Unmatched/missing input {key} for {x['file']}")
        if phase != "encoder" and (not x["encoderHiddenSHA256"] or x["encoderHiddenSHA256"] != y["encoderHiddenSHA256"]):
            raise ValueError("Decoder/prewarm comparison did not receive identical encoder hidden states")
        if x["file"] in SCORED and x["normalizedTranscript"] == y["normalizedTranscript"]:
            normalized_agreement += 1
        if any(x[k] != y[k] for k in ("rawTranscript", "generatedTokens", "detectedLanguages")):
            differences.append({"file": x["file"], "scored": x["file"] in SCORED,
                "reference": {k: x[k] for k in ("rawTranscript", "generatedTokens", "detectedLanguages")},
                "candidate": {k: y[k] for k in ("rawTranscript", "generatedTokens", "detectedLanguages")}})
    aa, bb = aggregate(left["rows"]), aggregate(right["rows"])
    deltas = {k: 100 * (bb["scored"][k]["mean"] / v["mean"] - 1)
              for k, v in aa["scored"].items() if v["mean"] > 0}
    return {"reference_run": a["runID"], "candidate_run": b["runID"],
            "reference": aa, "candidate": bb, "scored_mean_change_percent": deltas,
            "normalized_agreement_out_of_21_not_accuracy": normalized_agreement,
            "all_raw_token_language_differences": differences,
            "process_lifetime_rss_peak_bytes": {"reference": left["process_lifetime_rss_peak_bytes"],
                                                "candidate": right["process_lifetime_rss_peak_bytes"]},
            "evidence_sha256": {"reference": left["evidence"], "candidate": right["evidence"]},
            "promotion": "PENDING human quality/resource review"}


def live_metrics(path: Path):
    records = {}
    warnings = []
    for line in path.read_text().splitlines():
        if "asr_staged_memory_warning" in line or "ios_memory_warning" in line:
            warnings.append(line)
        match = re.search(r"asr_trial_(capture|send|final|failure)\s+id=([0-9A-Fa-f-]{36})\s+(.*)", line)
        if not match:
            continue
        stage, token, rest = match.groups()
        values = dict(re.findall(r"([a-z_]+)=([-+0-9.eE]+)", rest))
        row = {k: number(float(v), k) for k, v in values.items()}
        number(row.get("uptime"), "live uptime")
        entry = records.setdefault(token, {})
        if stage in entry:
            raise ValueError("Duplicate live event: use one bounded process log, not merged captures")
        entry[stage] = row
    if not records:
        raise ValueError("No instrumented live events")
    rows, incomplete = [], []
    for token, stages in records.items():
        if set(stages) != {"capture", "send", "final"}:
            incomplete.append({"id": token, "stages": sorted(stages)})
            continue
        capture, send, final = (stages[k] for k in ("capture", "send", "final"))
        if not capture["uptime"] <= send["uptime"] <= final["uptime"]:
            raise ValueError("Invalid live monotonic order")
        measured = number(final.get("send_to_final_seconds"), "Send-to-final", positive=True)
        if abs(final["uptime"] - send["uptime"] - measured) > 0.1:
            raise ValueError("App timer and same-process monotonic boundaries disagree by >100 ms")
        rows.append({"id": token, "capture_uptime": capture["uptime"], "send_uptime": send["uptime"],
                     "send_to_final_seconds": measured,
                     "capture_to_send_seconds": send["uptime"] - capture["uptime"],
                     "captured_audio_seconds": number(final.get("captured_seconds"), "captured audio")})
    rows.sort(key=lambda r: r["capture_uptime"])
    return {"schema": "mural-live-asr-timing-v1", "log_sha256": sha(path), "turns": rows,
            "incomplete_or_failed_turns": incomplete, "memory_warning_lines": warnings,
            "first_completed_turn": rows[0] if rows else None,
            "warm_completed_summary": summary([r["send_to_final_seconds"] for r in rows[1:]]),
            "timing_sample_valid": not incomplete and not warnings,
            "speech_onset_and_browser_delays": "NOT inferred from capture duration",
            "scope": "App Send-to-final; not Send-to-first-tutor-audio or browser interview time"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    corpus = commands.add_parser("corpus")
    corpus.add_argument("--phase", required=True, choices=("encoder", "decoder", "prewarm"))
    corpus.add_argument("--reference-run", type=Path, action="append", required=True)
    corpus.add_argument("--candidate-run", type=Path, action="append", required=True)
    live = commands.add_parser("live")
    live.add_argument("--log", type=Path, required=True)
    for command in (corpus, live):
        command.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "live":
            result = live_metrics(args.log)
        else:
            if len(args.reference_run) != len(args.candidate_run):
                raise ValueError("Supply equal numbers of paired runs")
            references = [load_run(p) for p in args.reference_run]
            candidates = [load_run(p) for p in args.candidate_run]
            all_runs = references + candidates
            for key in ("run", "process"):
                values = [r["report"]["runID"] if key == "run" else r["context"]["process_session_id"] for r in all_runs]
                if len(values) != len(set(values)):
                    raise ValueError("Repeated run/process across pairs")
            pairs = [compare(a, b, args.phase) for a, b in zip(references, candidates)]
            keys = set.intersection(*(set(p["scored_mean_change_percent"]) for p in pairs))
            result = {"schema": "mural-paired-asr-v1", "phase": args.phase, "pairs": pairs,
                      "run_level_change_percent_descriptive_only": {
                          k: summary([p["scored_mean_change_percent"][k] for p in pairs]) for k in sorted(keys)},
                      "scope": "Full staged harness includes preparation and synchronous diagnostic/report writes; not UI Send-to-final",
                      "limitations": ["Not ground-truth accuracy; inspect every difference", "Footprint samples are not continuous peaks",
                                      "RSS is process-lifetime, not per-turn RAM", "Decoder loop/prediction fields overlap; do not sum",
                                      "One run pair is exploratory, not repeatable performance evidence"]}
        with args.output.open("x") as stream:
            json.dump(result, stream, indent=2, allow_nan=False); stream.write("\n")
        print(args.output)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        parser.exit(1, f"Analysis blocked: {exc}\n")


if __name__ == "__main__":
    main()
