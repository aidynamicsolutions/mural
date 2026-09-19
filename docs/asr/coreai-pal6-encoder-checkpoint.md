# PAL6 encoder checkpoint: reviewed direction, host implementation, device pending

Starting remote: `afa5eee17d6aea686c9e9bc23fc816e4c7da1056`, branch `mvp`.
This checkpoint and [the local handoff](local-agent-pal6-handoff.md) supersede older
“restart FP8/cache investigation” next actions, not their historical evidence.

## Decision and product goal

Proceed with **one encoder-only PAL6 experiment**, preserving the accepted
**packed-v3 FP8 Core AI encoder + PAL8 Core ML decoder** as control and rollback.
The objective is acceptable English/Vietnamese code-switch recognition with less
waiting, storage pressure, heat and resource use—not the smallest bit count at
any cost. No production/default Talk selection has changed in this commit.

PAL6 means six-bit codebook indices, not FP6 floating-point or INT6 arithmetic.
Use the same frozen merged PhoWhisper source, 80-bin frontend, tokenizer,
transcription/no-forced-language policy, FP16 input/hidden-state handoff, GPU
preference, staged single owner and native-drain behavior. Do not compress the
already-compressed FP8 artifact. Do not change the decoder, VAD, suppression,
language detection, generation policy, context length, or model family.

Moving an index payload from eight to six bits is arithmetically 25% smaller
before codebook/metadata costs. That is **not** a prediction for the whole model,
AOT package, app footprint, RSS, execution latency, or perceived waiting. The
encoder still accepts the same fixed `[1,80,3000]` input and produces
`[1,1500,1280]` hidden states. Reduced weight storage does not remove that work.
The native compiler/runtime must demonstrate a useful operational benefit.

Cold start also includes artifact verification, cache/specialization/function
load, frontend work and decoder readiness. Greeting-time decoder prewarm already
exists; it must resolve to the same retained PAL8 directory used at Send. Keep
prewarm/ownership policies unchanged for this experiment so their effects are
not misattributed to precision.

## Important finding: the old staged corpus timer is not end-to-end

At the starting commit, `App/MuralApp.swift` runs `productStageEncoder`, then
`productPrepare`, then `productTranscribe`. The latter starts its timer only when
`WhisperKit.transcribe` begins, using `ProductReplayEncoder` to consume the already
computed hidden states. Thus **staged `ProductTurn.timing.totalSeconds` excludes
the real encoder and its preceding preparation**. It also excludes the preceding
decoder preparation. Its `encoderSeconds` must not be interpreted as the native
staged encoder duration.

The supplied handoff labels 1.148 s and 1.762 s corpus means “Send-to-final.” The
local raw evidence has not been recovered on the connector host. Preserve those
reported values, but recover their exact source fields before repeating that
label or the reported 34.9% end-to-end improvement. If the values came from the
staged `ProductTurn` timer, relabel them as decoder/replay-pipeline measurements.
Do not manufacture a corrected number by adding averages from different live
runs. This finding does not undo the supplied human accuracy/waiting acceptance.

`prepare_pal6_trial.py` therefore generates measurement-only trial changes for
**both** FP8 and PAL6: a `staged-asr-full-complete` event from after audio-file read
through frontend/encoder/decoder preparation and transcription; plus separate
native encoder and validation/copy durations in `encoder-response-verified`.
The new full interval still is **not UI Send-to-final**. Keep true live Send-to-
final, preparation, and this laboratory interval as separately named metrics.
Historical fields and expected transcripts are not overwritten.

## Evidence recovered versus evidence supplied

**Recovered from tracked source:** frozen lineage/weight identity, runtime
contracts, exact FP8 full-encoder and PAL8 support manifest pins, current staged
ownership/prewarm paths, and the historical Core ML six-bit checkpoint.

**Supplied by the user, not remeasured here:** successful 22-recording FP8/PAL8
qualification (21 scored, 017 diagnostic), zero new scored differences, successful
live bilingual/numbers/negation/quiet-answer/offline checks, approximately
0.507–0.562 s native encoder and 0.0046–0.0167 s validation/copy, 2.332–3.963 s
live Send-to-final, no warning/abort in that bounded qualification, and better
perceived waiting/heat. Reported sampled footprint mean/max is 1.249/1.285 GB;
reported process-lifetime RSS is 1.432 GB. Historical comparators must be
recovered and matched, not combined into one “RAM” percentage.

The `.build/verification/w8-v3-*` evidence directories are not tracked in the
inspected remote tree and are unavailable on this Linux connector host. This
**does not establish that they are missing on the user's Mac**. No local Mac
checkout, actual weights/AOT bundles, Xcode/Core AI installation, or iPhone was
accessible here.

**Historical six-bit context recovered from `mvp_plan.md`:** full Core ML PAL6,
grouped channels/group 16, runtime payload 1,265,613,461 bytes, 19/21 normalized
agreement with FP16, fixture 011 `I went to` → `I went through`, and the known 007
`seal tea` → `seoul tea` variation. First-16/follow-up WER was
5.46875%/2.89855%. Mac preparation/first-file/warm-median was
65.699/13.082/2.670 s. These are neither new Core AI nor iPhone results.
Historical PAL6 manifest:
`13f9bbd0d08bf0b6a111f8415ddffad158f8d1fb4e4014c17585066e37fd23bb`.
Recover exact old commands, thresholds, LUT policy and skipped tensors locally;
those details were not established by the tracked summary alone.

## Implemented tooling

- `build_pal6_encoder.py`: exclusive-output FP16-source conversion using Apple's
  Core AI weight-palettization API, reference/control checks before model load,
  real Torch wrapper/capture checks, per-tensor coverage audit, source/AOT ABI
  inspection, immutable manifests, actual bundle sizes, compiler identities,
  and failed-attempt manifests. No native execution or deployment is claimed.
- `pal6_contract.py`: exact reference/decoder pins, provenance/control checks,
  PAL6 LUT/index validation, explicit retention reasons, logical byte accounting,
  artifact rehash and static pair/cache-key separation checks.
- `w8_runtime_identity.py`: PAL6 gets width 56 and a recipe-derived named
  entrypoint. Existing FP16/FP8/INT8 identities and the three-way W8 audit remain
  unchanged. The working wrapper and challenge-response verifier are reused.
- `prepare_pal6_trial.py`: after real candidate artifacts pass the pair audit,
  emits a reviewable local runtime patch and receipt with the **actual** manifest
  pin. It does not apply the patch, stage assets, install, or supply fake pins.
  The patch extends Swift's packet bound to 1,920,056; permits PAL6 only with an
  explicit PAL8 decoder; restricts PAL6 probes to the sequential GPU owner; adds
  the timing events above; and defers PAL6-only fixture-001 textual differences
  to corpus/human review rather than changing expected text. Existing candidate
  recovery checks stay intact. Numeric/identity/error gates stay intact.
- `compare_pal6_hidden.py`: verifies saved FP16 tensor digests/shapes and the same
  mel identity, then reports finite values, max/mean absolute error, cosine,
  bit identity and optional repeatability. Numerical agreement is not ASR quality.

The initial recipe is `n_bits=6`, K-means, grouped channel 16, scalar cluster
`1`, FP16 LUT storage, `lut_dtype=None` (no additional LUT quantization), threshold
1024, four clustering workers, no per-channel scale, no activation quantization,
no pruning/training. Fast K-means decimal rounding is **disabled** to avoid an
additional approximation in the initial quality experiment; this may cost export
time, not device inference time. Record any justified recipe change as a new
identity, not an in-place “fix” to accepted bytes.

Small retained rank-1 constants up to 16,384 elements and below-threshold
constants are recorded without falsely failing the experiment for tiny affine/
normalization/metadata overhead. Every larger or rank-2+ skipped floating tensor
requires an exact location/shape/dtype-keyed reason. Duplicate/ambiguous mappings,
disappeared matrices, wrong index/LUT types or additional quantization fail closed.
`--retained-exceptions` documents existing exporter skips; **it is not a precision
selector and must not be used to pretend a layer was held at FP16**.

## Verification on the connector host

30 `unittest` tests passed, zero skipped, including real Torch export of a
synthetic full-shape encoder with runtime challenges, stale/nonfinite/ABI
rejection, logical byte accounting, explicit skips, retained small vectors,
artifact rehash/mutation/collision checks, old W8 trio compatibility, source-patch
safety and same-mel numerical comparisons. Python syntax/CLI checks also passed.
The original shared Python helper was verified against Git blob
`de3978869a1eab4b7805d99726755051634958df` before its minimal changes.

These are host contract tests and synthetic IR records, **not a converted
PhoWhisper run, Apple compiler validation, complete Swift build, on-phone cache
isolation, corpus test, live test, or benchmark**. Actual pinned Apple API/IR
compatibility is a local gate. Correct narrow exporter/SDK contract differences
using installed signatures and source, preserving the experiment, rather than
abandoning it or silently weakening the audit.

## Promotion and scope boundary

Qualify PAL6 encoder/PAL8 decoder against the exact retained FP8/PAL8 control,
with raw corpus differences and human bilingual acceptance plus matched resource
measurements. One evidence-selected mixed-precision candidate is allowed only
for a narrow meaningful regression accompanied by a worthwhile resource win;
no layer sweep and no test-set training. Decoder PAL6 needs a separate explicit
encoder-result review first. Silence/VAD remains a separate final experiment.

**Current disposition: retain FP8/PAL8; PAL6 encoder tooling is ready for local
conversion and qualification, not promoted or device-qualified.**

## Primary references

Apple Core AI Optimization overview (PAL6 versus weight-quantization types):
https://apple.github.io/coreai-optimization/

Core AI direct program compression and API contract (verify against pinned
`coreai-opt 0.2.1` locally):
https://apple.github.io/coreai-optimization/utils/coreai_compression.html
https://apple.github.io/coreai-optimization/api/generated/coreai_opt.coreai_utils.palettize_weights.html
https://apple.github.io/coreai-optimization/_modules/coreai_opt/coreai_utils/passes/weight_palettization.html

Apple Core ML palettization concepts and runtime-version context (not proof of a
Core AI speedup):
https://apple.github.io/coremltools/docs-guides/source/opt-palettization-overview.html
https://apple.github.io/coremltools/docs-guides/source/opt-whats-new.html
