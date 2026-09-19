# ASR: FP8 encoder + PAL8 decoder

The normal On-device Talk path now uses **packed-v3 FP8 Core AI encoder + PAL8
Core ML decoder**, with `prewarm=always`. The repeated live comparison favored
its mixed-language accuracy over PAL4/PAL4's resource savings. PAL8 is not an
FP8 decoder. PAL6/PAL4 are historical qualification work, not the next experiment.

Read the [precision findings](precision-comparison-20260918.md),
[engineering review](final-engineering-review-20260919.md), then the
[one bounded iPhone validation](final-fp8-pal8-validation.md).

## Selection and identity

The default Release Talk path selects FP8/PAL8 without `MURAL_COREAI_TALK`,
`MURAL_COREAI_W8`, or launch arguments. `prewarm=always` is the built-in default.
The h18p device gate and pinned manifest, AOT, ABI, support inventory, and cache
checks remain mandatory; missing or incompatible assets fail closed rather than
falling back silently. Explicit diagnostic selectors remain available for reviewed
qualification paths, but are not needed for normal Talk.

| Identity | SHA-256 of pinned manifest |
|---|---|
| Full packed-v3 FP8 encoder | `73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13` |
| PAL8 support (`phowhisper-cs-pal8-g16-v1`) | `430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336` |

Retain the named entrypoint, h18p gate, complete AOT fingerprint, runtime response,
40-value FP16 trailer and FP16 hidden-state handoff. Do not use `main` as a v3
fallback, relax the cache-alias block, clear the warning latch, or overlap owners.
Drain speculative decoder prewarm before encoding; the encoder scope must return
before turn decoder loading. Cancellation must drain native work before teardown/recovery. Do not delete caches or regenerate models.

## Measurement boundaries

Native encoder execution, function load, validation/copy, decoder support prewarm,
model load and decoder predictions are different intervals. Live
`asr_staged_decoder_decode_complete.seconds` covers replay/transcription, not just
native decoder execution. `asr_staged_turn_complete.end_to_end_seconds` is a legacy
key for the staged pipeline through unload, not UI latency. Both now carry scope
labels. The staged harness starts after audio-file read and includes diagnostics.
Only ID-correlated `asr_trial_send`/`final`/`audio` measure app Send-to-final and
first tutor audio. Phase footprint is not process-lifetime RSS or model-only RAM.

## Historical evidence, not current work orders

The [PAL8 live result](combined-pal8-mixed-result-20260918.md),
[PAL4 result](combined-pal4-result-20260918.md),
[decoder qualification](decoder-qualification-20260918-real-results.md) and
[PAL6 native-only result](combined-pal6-result-20260918.md) retain their measured
results and limitations. Earlier plans, checkpoints, patch generators and
`local-agent-*-handoff.md` files explain how those experiments were performed;
their pending-work instructions are superseded by this index. Retain useful
identity/layout/policy regressions and immutable export provenance. Do not restart
PAL4/PAL6, mixed precision, prewarm-policy comparisons, conversion or compact-model
research. Silence/VAD is separate and is not started by this review.

Keep recordings, stores, screenshots and complete device logs local. Publish only
a concise sanitized result with source/build/artifact hashes and explicit limits.
