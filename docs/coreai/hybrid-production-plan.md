# Hybrid ASR production plan

Status: **GPU-preferred normal-Talk opt-in implemented and partially phone-verified. Default rollout remains gated.**

Latest: [GPU Talk checkpoint](gpu-talk-checkpoint.md). The original ANE-backed cached-load failure was reproduced and preserved. A separate GPU-preferred FP16 encoder passed bounded qualification and enabled an explicit Release Talk experiment. Real-path preparation, repeated turns, persistence, offline and Finalizing Stop/retry passed after fixing verification-buffer accumulation. The background-restoration correction still needs its phone replay; full rollback and release gates remain open.

Current assessment: [staged Talk assessment](staged-talk-assessment.md). The later [remaining-gates checkpoint](staged-remaining-gates-checkpoint.md) supersedes historical fixture-001-only evidence below: the staged corpus completed without warnings, and the user accepted fixture 007 as an explicit known-error exception. This does not clear reliability, integrated lifecycle, rollback, or Release gates.

Goal: reduce PhoWhisper startup time with the Core AI encoder while preserving FP16 weights, the existing frontend and tokenizer, WhisperKit decoding behavior, transcript quality and offline operation.

Current evidence shows:

- All-Core-ML preparation: `226.944 s`.
- Hybrid preparation: `82.528 s` after encoder specialization, and `8.149 s` on one cached run.
- Fixture 001 text, language and tokens matched exactly.
- Holding the hybrid resources across turns can reach roughly `3.5 GB` and trigger a kernel per-process memory-limit kill.
- Explicit release and cached recreation completed two exact turns in one diagnostic run, with two memory warnings.

The last two points are the main production risk. A speed result from one fixture is not enough to ship a new ASR runtime.

## Phase 1: make ownership and lifecycle explicit

Start from the existing single-owner `LocalConversationEngine.WhisperRecognizer` actor. Do not introduce a provider framework or a second decoder implementation unless the current owner cannot express the state machine.

1. Keep one actor responsible for preparation, active inference, cancellation and teardown.
2. Give the hybrid encoder function and the WhisperKit instance an explicit lifetime. Do not retain model-backed arrays or `InferenceFunction` values after teardown.
3. Never unload models while `transcribe` is still running. Stop must cancel the operation, await its completion, then release resources.
4. Add a small release-and-recreate path using the existing cached AOT assets. It must not delete cache entries or depend on cache invalidation.
5. Reset all per-turn state before the next recording. Prevent overlapping turns and stale task results using the existing generation/cancellation discipline.
6. Record only bounded diagnostics in development builds: preparation, reload, inference, footprint, memory warnings, thermal state and failure stage. Do not persist audio or large tensors in the release app.

Acceptance gate:

- Ten or more serial turns on representative short and long recordings without Jetsam, SIGABRT, stale output or unbounded footprint growth.
- Cancellation during preparation, encoder execution and decoder execution leaves the actor reusable.
- Background/foreground and app relaunch do not corrupt the session or learning data.
- Model resources are released after the chosen idle/turn boundary and reload uses the expected cached asset.

## Phase 2: controlled timing and memory benchmark

Compare the existing WhisperKit/Core ML path and the hybrid path on the same phone, build, assets and fixture set.

1. Run three fresh-process encoder specialization samples and three fresh-process cached samples for each path where the cache state can be verified.
2. Report every sample, median and range. Do not call a single sample a p95 or a guaranteed cold start.
3. Separate asset verification, specialization, function load, model load, first encoder execution, first complete transcript and subsequent-turn latency.
4. Measure peak footprint, RSS, memory warnings, thermal state and coexistence with the tutor/TTS path.
5. Include the release-and-recreate cost in subsequent-turn latency. A fast Ready label followed by a slow first Send is not a startup win.

Targets for review, not promises:

- Cold ASR readiness around 15 seconds or less with assets already installed.
- Cached readiness around 6 seconds or less.
- No material first-turn or warm-turn regression against matched-waveform WhisperKit measurements.
- No memory warning or process kill during the normal conversation envelope.

If the decoder prewarm remains the dominant cost, isolate that cost before changing the encoder. Do not repeat the blocked Core AI decoder configurations from the earlier checkpoints.

## Phase 3: transcript-quality gate

Use the frozen accepted corpus before enabling hybrid Talk. Compare the same audio through the existing and hybrid paths.

1. Use the repository's existing normalization only. The user-approved corpus disposition is **21 exact historical-reference matches plus one explicit fixture-007 known-error exception**, not `22/22` exact parity: `seal tea` and `seoul tea` both misrecognize Vietnamese `siêu thị`. Preserve both raw outputs and this exception. The failed fresh phone comparator still blocks controlled same-device parity claims.
2. Retain raw text, language, token and timing differences. Do not change punctuation, accents, prompts, thresholds or expected output to manufacture a pass.
3. Compare frontend mel, encoder output, decoder inputs, logits where available, generated tokens and final text in that order.
4. Keep separate checks for silence, Yes and No because the existing 22-file corpus does not cover all of those cases.
5. Verify repeated turns on each relevant fixture and ensure a new turn does not inherit KV state or prompt tokens.

A difference in Core AI and Core ML hidden tensor values is acceptable only if the complete transcript gate passes and the difference is understood enough to bound risk. Fixture 001 alone is not an accuracy guarantee.

## Phase 4: integrate behind a safe product gate

Only after Phases 1 through 3 pass:

1. Add the hybrid lifecycle to the existing private `WhisperRecognizer` owner rather than changing the public conversation flow.
2. Keep the accepted frontend, PhoWhisper tokenizer, control tokens, suppression rules, FP16 model and WhisperKit decoding policy unchanged.
3. Use architecture-matching AOT assets and verify their manifest before loading.
4. Keep the existing WhisperKit/Core ML path available as the normal rollback path while the hybrid is tested internally.
5. Treat throwing load failures separately from native runtime aborts. Swift can handle a thrown failure, but it cannot recover after a native SIGABRT or Jetsam kill. Never add an automatic retry loop for a known crashing configuration.
6. Keep all learning data and model assets in place during upgrades. Never use uninstall or data reset as a repair mechanism.
7. Confirm offline launch and offline transcription with network access disabled.

Internal rollout acceptance:

- Existing Talk conversation and ASR UI behavior are unchanged except for measured preparation/inference timing.
- Stop, retry, backgrounding and a second recording all work.
- Logs contain no private audio or transcript data beyond the existing approved diagnostics.
- Release builds exclude probe flags, tensor dumps and cache-deletion code.

## Phase 5: release and rollback

Before making hybrid the default:

- Repeat the timing, memory and corpus gates on the release configuration and supported device/OS combinations.
- Test at least one fresh install-like data container without deleting user data from the real device.
- Verify app launch, model verification failure, missing asset failure and cancellation messages.
- Keep a simple build-time or local development switch to return to WhisperKit/Core ML while the first production cohort is observed. Do not add a remote control plane for this one backend choice.
- Remove or quarantine stale diagnostic code and document the final artifact hashes, OS, Xcode and Core AI architecture.

Rollback trigger: any Jetsam/per-process kill, native abort, transcript mismatch outside the accepted baseline, repeated memory warning in the normal conversation envelope, or a material startup/inference regression.

## Definition of production ready

The hybrid path is production ready only when all of these are true:

- The accepted corpus gate, with the explicit fixture-007 exception recorded separately from exact parity, and explicit edge-case coverage pass.
- Cold and cached startup targets are met on controlled repeated samples.
- Repeated turns, cancellation, backgrounding and relaunch are stable.
- Peak memory stays below the device limit with tutor/TTS coexistence and no recurring warnings.
- The app has a tested rollback path and no cache deletion or data reset is required.
- Normal Talk uses the lifecycle-tested implementation, not the diagnostic probe.

Until then, keep the hybrid work in the development probe and retain WhisperKit/Core ML for normal Talk.
