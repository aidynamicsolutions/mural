# Decoder-first optimization review - 2026-09-18

> **Delivery status:** Prepared against `eb2675980cd9c944cd376d7bb70e4d2800f15df8`. The GitHub connector rejected the remote write, so these changes are **not committed or pushed**. Apply the delivered `decoder-next.patch` using the package’s `DELIVERY.md` before running this handoff.

Reviewed remote `mvp` at `eb2675980cd9c944cd376d7bb70e4d2800f15df8`
(parent `b806b6c2f7175597100f6adc617a8ceed32a4686`).
The current user explicitly authorizes investigating PAL6 decoding even if the
PAL6 encoder has no worthwhile win. This supersedes the earlier requirement to
accept PAL6 encoding before starting the decoder. It does not authorize unsafe
ownership overlap, reference rewriting, cache deletion, or a default switch.

## Evidence availability is the first finding

The latest commit changes eight source/test files. It adds the real PAL6 encoder
pin, Swift format/shape support, native/validation/full-staged timing fields,
and changes the host coverage audit. It adds **no results document, raw corpus
output, benchmark table, run metadata, or live interview report**. The commit
message is only `feat(asr): add PAL6 encoder qualification`; its comments endpoint
was empty. The previous review/handoff documents are unchanged.

The user's report that the local test found no speed/memory improvement is useful
but remains **user-reported**, not independently recomputed here. The Mac, iPhone,
model binaries and ignored `.build/verification` evidence are unavailable on the
connector host. Do not invent trial measurements or claim a reviewed phone pass.
Recover the local evidence first and commit a compact, privacy-reviewed results
summary at the end of the next session; keep raw personal recordings/logs local.

## Source-level findings

1. `LocalConversationEngine.WhisperRecognizer.transcribeStaged` calls the actual
   Core AI encoder on **every recording**, then releases its local scope. It then
   constructs a new WhisperKit instance, prewarms, loads, transcribes and unloads
   the Core ML decoder. Cached specialization is not a permanently loaded model;
   it is also not permission to reuse another utterance's encoder features.
2. Greeting-time `prewarmStagedDecoder` prewarms `TextDecoder.mlmodelc` and unloads
   it. The Send path waits for that task and nevertheless calls `prewarmModels`
   before `loadModels` each turn. Redundant prewarm hints are a concrete
   optimization opportunity to measure, not proof that all real load costs can
   be removed. The proposed `prewarm=once` test keeps actual loads/unloads and
   native drains; no decoder remains resident across the encoder scope.
3. The old staged `ProductTurn.timings.totalSeconds` still measures the replay/
   decoder pipeline, not all ASR. The latest commit correctly adds
   `staged-asr-full-complete`, starting before real encoding and decoder prepare.
   It also adds `nativeSeconds` and `validationCopySeconds` to the identity event.
   Whether the local agent used these fields cannot be checked without its logs.
4. The full staged timer includes harness work: input hashing, preparation,
   synchronous event logging/fsync and report writes. It is not UI Send-to-final.
   Keep it, native execution, decoder timing and app-monotonic Send-to-final as
   different scopes. Do not add overlapping WhisperKit timing fields together.
5. In staged mode, native encoding happens before `productTranscribe` resets its
   per-turn capture fields. Use **encoder-stage events** for encoder footprint,
   rather than relying on replay-path memory fields or only a decoder-resident
   sample. The new analyzer reports fixed encoder-end, decoder-loaded and
   decoder-text-end footprint anchors separately; RSS remains process-lifetime.
6. The changed PAL6 audit maps source weights to palette results by ordered shape
   correspondence, after compiler locations changed. This can establish aggregate
   count/shape coverage, but repeated same-shaped layers make it insufficient to
   prove exact per-layer provenance or a precision exception. The source comment
   that traversal order is preserved is not an independent compiler guarantee.
   This is **not proof of a bad model or wrong output**. Do not discard qualified
   bytes on this basis. For a targeted exception, require graph-use/content-based
   mapping and a regression test that rejects a same-shaped source swap.

## Why smaller need not mean faster or lower measured RAM

Six-bit indices have a smaller logical payload than eight-bit weights, but LUTs,
retained tensors, compiler artifacts, activations, attention caches, output
buffers, allocator retention and other app models do not shrink automatically.
Core ML's documented compression behavior depends on the backend: weights may
be decompressed ahead of runtime or just in time. More grouped LUTs can also
increase runtime overhead. These are plausible explanations to investigate, not
an assertion about what this particular Core AI GPU build did.

In an idealized sequential pipeline, the overall peak is determined by the
largest phase plus common/residual allocations. Lowering an encoder phase that
is already below the decoder phase need not lower the whole-process peak. The
real implementation does not prove native allocation retirement merely by
releasing Swift references; retain event samples to observe it.

Similarly, shaving a fraction off the encoder cannot remove decoder preparation,
per-token predictions, token-processing/copy overhead, or tutor/TTS latency.
The next experiment targets the decoder because of this cost structure and the
observed repeated preparation path, not because the unavailable report proves
an exact bottleneck percentage.

## Interview delay: real confounder, but not a stopwatch correction

`finishRecording` sets `submittedAt` from `systemUptime` on Send, and `record`
computes `finalizeSeconds` from that timestamp when the transcript is assigned.
A browser form displayed three seconds later does not add three seconds to this
app timer. Do not subtract estimated interview delays from measurements.

However, a pause before recording gives speculative prewarm more time to finish,
which can make a cold first turn look better. A pause after Record but before the
sentence changes captured audio and can add silence, hit the turn cap or change
recognition. Inter-turn pauses change thermal/idle conditions. A browser-driven
subjective total also includes agent overhead. None of these pauses occurs in
the automated retained-corpus loop.

Prepare the complete instruction/feedback form on the **Mac before launching the
phone test**. A user then performs 4–6 consecutive turns without waiting for new
agent messages. Include a short first utterance as well as normal mixed speech.
Compare app timers and raw captures, not instruction-delivery times.

## Decision and implementation

Keep FP8/PAL8 as control. Do one bounded encoder recheck only if local evidence
has mismatched identities, scopes, phases or pacing. Do not rebuild the encoder
or restart the solved FP8/cache-identity investigation.

Main comparison: **fixed accepted FP8 Core AI encoder + PAL8 Core ML decoder**
versus **that same FP8 encoder + PAL6 Core ML decoder**, with unchanged prewarm
policy. Reuse the historical PAL6 decoder only after exact-pin and unchanged-
frontend/tokenizer/suppression verification. The historical whole-pair 19/21
agreement and fixture-011 change are context, not this decoder's result.

`prepare_pal6_decoder_trial.py` admits only the pinned historical PAL6 support
manifest (`13f9bb...23bb`), compares all common support files to retained PAL8,
rehashes the accepted FP8 encoder, and optionally copies only inventoried
originals into a fresh staging directory. Existing cache extras are recorded and
left untouched. It emits a source-hash-bound, reviewable patch; it does not apply,
install, compile, run or promote anything.

The patch admits PAL6 decoding only with the fixed FP8 encoder and sequential
probe; original PAL6 encoding remains paired only with PAL8. Default choices and
all existing model pins remain unchanged. Its separate `prewarm=once` policy
skips redundant hints only after successful same-support prewarming (or a prior
successful corpus turn). It always executes actual load/unload and native-drain
paths. It adds content-free capture/Send/final IDs and phase memory samples, and
updates the portable product-test harness to include the policy helper.

`analyze_asr_trial.py` refuses incomplete/unsafe/mismatched corpus comparisons,
separates 21 scored fixtures from diagnostic 017, preserves all raw/token/language
differences, separates timing/memory scopes and reports descriptive paired-run
changes. Its live mode uses app-monotonic timestamps, not browser receipt times.
Raw content in its output stays local unless reviewed for publication.

Thirty-two new portable tests pass, including compiling/executing the real Swift
policy with Swift 6.2.1 on Linux. The rest use synthetic support inventories,
logs/reports and patch anchors. Python syntax/CLI checks pass. **Not run here:**
full iOS source-patch application, Apple conversion, Xcode build, native model
ABI, existing full app test suite, corpus, live speech, physical memory or timing.
No application source/default is changed by this prepared change set; the actual
runtime integration is a local, audited patch-application/build step.

## Beyond compression, without speculative rewrites

If loading dominates, evaluate the isolated prewarm-once experiment first. If
predictions dominate, inspect the decoder compute plan and a bounded Instruments
trace, then identify expensive matmuls/attention or decompression. If host-side
loop work dominates, inspect token sampling and KV transfers; do not add a
second cache or reuse previous-utterance state blindly. The pinned WhisperKit
already has a within-turn KV-cache path.

Apple's `fastPrediction` specialization hint is another possible *separate*
experiment, but it explicitly may increase memory, disk and specialization time;
it is not a free simultaneous RAM/speed win. Stateful **Core ML** decoder export
could reduce explicit state transfers, but changes the ABI and needs a separate
numerical/quality bring-up. Do not confuse it with permission to relaunch the
historically crashing Core AI decoder. Neither is implemented in this change set.

No VAD/silence, model replacement, lower-than-six-bit sweep, training, decoding
threshold changes or cloud fallback is included. Choose the measured Pareto
tradeoff, not a preferred bit count. A compression failure does not end latency
work; it changes which measured component is targeted next.

## Primary sources (reviewed 2026-09-18)

- Apple compression/runtime caveats: https://apple.github.io/coremltools/docs-guides/source/opt-overview.html
- Apple palettization performance and grouped-LUT cost: https://apple.github.io/coremltools/docs-guides/source/opt-palettization-perf.html
- Apple supported codebook widths: https://apple.github.io/coreai-optimization/
- Apple fastPrediction tradeoff: https://developer.apple.com/documentation/coreml/mloptimizationhints-swift.struct/specializationstrategy-swift.enum/fastprediction
- Apple compute-plan device usage (anticipated, not measured placement): https://developer.apple.com/documentation/coreml/mlcomputeplandeviceusage
- Pinned runtime configuration: https://github.com/argmaxinc/argmax-oss-swift/blob/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d/Sources/WhisperKit/Core/Configurations.swift
- Runtime release/within-turn KV-cache context: https://github.com/argmaxinc/argmax-oss-swift/releases/tag/v1.0.0

Next action: [local-agent-decoder-handoff.md](local-agent-decoder-handoff.md).
