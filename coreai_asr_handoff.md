# Core AI ASR implementation handoff

## Status

This commit implements the **loading-time decision gate**, not the final runtime
migration.

The existing on-device conversation path remains unchanged on
WhisperKit/Core ML.

New work in this commit:

- deterministic helper to recreate the pinned merged PhoWhisper source if the
  previously frozen source is unavailable;
- Core AI `.aimodel` exporter derived from Apple's official Whisper example;
- Core AI AOT compilation helper;
- an explicit Mural launch-time Core AI load probe;
- persistent specialization-cache measurement and controlled per-model cache
  reset;
- JSON diagnostic output for reporting.

## Why this boundary is deliberate

The current unacceptable delay is historical ~215 s first preparation, with
~206 s in WhisperKit/Core ML prewarm/specialization. Before implementing a new
ASR decoder, prove that Core AI AOT actually reduces the expensive part.

The app probe does not transcribe and cannot affect normal conversations.

## Current reference

- branch before this work: `mvp`
- starting head: `c3e6b1b0859c579983a263cf831689a40e2ff734`
- retained model: `phowhisper-cs-fp16-v1`
- retained runtime bytes: ~3.10 GB
- Large-v2/PhoWhisper frontend: 80 mel bins
- current Core ML/ANE cold preparation: ~215.2 s historical
- current cached preparation: ~6.3 s historical

## Next agent: exact task

1. Pull the new `mvp` commit.
2. Read `Tools/CoreAI/README.md`.
3. Confirm the checkout is clean and do not modify unrelated Phase 5 work.
4. Locate the exact previously frozen merged PhoWhisper FP16 Hugging Face source
   from the existing local benchmark artifacts. Prefer it over re-merging.
5. If it is missing, run `Tools/CoreAI/merge_phowhisper.py`.
6. Replay the existing frozen ASR corpus against the source before conversion.
   Stop if source parity fails.
7. Run `Tools/CoreAI/export_phowhisper_coreai.py`.
8. Run `Tools/CoreAI/compile_aot.sh`.
9. Identify the compiled asset matching `AIModel.deviceArchitectureName` on the
   iPhone 17.
10. Stage only that asset into Mural's app container.
11. Build Mural Release using the existing bundle/signing/device workflow.
12. Launch with `--coreai-load-probe --coreai-reset-cache` for an uncached trial.
13. Run at least two additional controlled uncached trials if cache deletion is
    safe and repeatable.
14. Force-close/relaunch with `--coreai-load-probe` for at least three cached
    trials.
15. Retrieve `Documents/coreai-load-probe.json` after each representative run.
16. Report exact raw timings, architecture, asset size, Xcode/iOS versions, and
    any error.
17. Do **not** implement the Core AI ASR decoder yet if cold readiness exceeds
    60 s.

## Pass gate

Proceed with full Core AI transcription only when:

- median/representative cold AOT ready <= 55 s;
- cached ready <= 5 s;
- no app termination during specialization/function loading.

Stretch target: cold <= 15 s.

## If the gate passes

Report back before doing a large refactor. The next code change should preserve
the exact FP16 weights and implement transcript parity in stages:

- exact 80-mel frontend;
- current PhoWhisper tokenizer/control tokens;
- greedy decode first;
- frozen-corpus parity;
- then decoder performance/KV-cache work;
- then phone integration.

## Report template

```text
MVP commit tested:
Mac / Xcode:
iPhone model / iOS:
Core AI architecture:
Source model path/hash:
.aimodel bytes:
matching .aimodelc bytes:

Uncached run 1:
  cache lookup:
  specialization:
  loadFunction:
  total:
Uncached run 2:
Uncached run 3:

Cached run 1:
Cached run 2:
Cached run 3:

Errors / termination / heat:
coreai-load-probe.json:
PASS/FAIL against <=55 s cold and <=5 s cached:
```
