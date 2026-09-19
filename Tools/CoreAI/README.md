# Core AI PhoWhisper migration tools

## Current W8 trial: blocked on AOT cache identity

See [implementation checkpoint](../../docs/asr/coreai-w8-implementation-checkpoint.md)
and [candidate manifests](../../docs/asr/coreai-w8-candidates.json). The separate
`compress_phowhisper_encoder.py` exports audited FP8/INT8 weights from the frozen
source encoder using `compression-requirements.lock.txt` in an isolated Python
3.11 environment. The original exporter and environment remain unchanged.

Both candidates AOT-compiled and produced finite encoder-only phone output, but
their identical compiled `main.hash` caused native cache aliasing. Compressed
candidate loading is now fail-closed. Do not remove the guard, delete caches,
or treat a cache hit as weight-identity proof. Decoder/PAL8/live qualification
remains blocked. The historical sections below are not instructions to repeat
failed native runs.

This directory contains the staged migration of Mural's accepted
`phowhisper-cs-fp16-v1` model from WhisperKit/Core ML to Core AI.

The goal is **startup + inference runtime migration without changing ASR
weights or transcript quality**.

## Latest: hybrid encoder memory follow-up

The approved [single-entry cache-invalidation experiment](../../docs/coreai/hybrid-invalidation-checkpoint.md)
produced a verified cache miss, a successful encoder load, and the **first complete
hybrid transcript**, matching fixture 001's baseline text/language/token IDs on
byte-identical mel. The subsequent ordinary cached-startup run reached the same
first transcript, then was terminated on turn two by the kernel's per-process
memory limit, explicitly reported as Jetsam/per-process-limit.

The bounded lifetime diagnostic released WhisperKit's models and the hybrid Core AI
encoder after turn one. Footprint fell from about 3.526 GB to 55 MB. A follow-up
release-and-recreate diagnostic then completed both turns with exact text, language,
tokens, mel, and hidden tensors. It still produced two memory warnings, so this is
a lifetime finding, not proof of long-running stability or a production fix. See
[hybrid memory evidence](../../.build/verification/coreai-hybrid-memory/).

No corpus or production integration was performed. Do not repeat the invalidation
launch; preserve the newly working cache and old artifact backup.
`--coreai-hybrid-invalidate-encoder` is an explicit one-entry, hybrid+fresh-only
diagnostic, never automatic fallback or normal Talk behavior. The release and
recreate flags are bounded diagnostics only and are not normal Talk behavior.

### Previous hybrid attempts

The approved [fresh-path follow-up](../../docs/coreai/hybrid-fresh-encoder-checkpoint.md)
also stopped: a byte-verified original AOT copy under a new directory still
resolved to a cached specialization. The new `--coreai-hybrid-fresh-encoder`
guard refuses that hit before function loading. No fresh specialization or hybrid
inference occurred; no caches were deleted. Do not repeat either attempt unchanged.

The separately approved one-fixture hybrid proof is implemented but blocked at
Core AI encoder function loading. The all-Core-ML baseline completed fixture 001
twice: 226.944 s preparation, including 34.760 s decoder prewarm and 185.172 s
encoder prewarm. The hybrid threw while loading the existing cached encoder;
no hybrid inference or transcript occurred. See
[hybrid-checkpoint.md](../../docs/coreai/hybrid-checkpoint.md).

The existing probe accepts `--coreai-whisperkit=baseline|hybrid` with
`--coreai-asr-probe --coreai-asr-auto --coreai-fixture=001.wav`. These are bounded
development modes, not Talk selections or full-corpus modes. Do not repeat the
unchanged failing hybrid load. All original assets/caches remain preserved.

`python3 Tools/CoreAI/test_hybrid_layout.py` checks the actual Swift FP16 layout
bridge on Mac without requiring a Core AI runtime. Phone proof output retains
`whisperkit-proof.json`, per-turn WhisperKit JSON, canonical mel/hidden tensors
and existing flushed events under the UUID run directory.

## Earlier checkpoints

The first AOT loading gate passed on the physical iPhone 17 (`iPhone18,3`,
Core AI architecture `h18p`):

- previous Core ML / ANE first prepare: ~215 s historical;
- Core AI AOT cold ready: 11.73–14.82 s across three controlled cache misses;
- Core AI cached ready: 5.35–5.78 s, dominated by `loadFunction("main")`;
- no correlated Mural crash, Jetsam, memory-pressure termination, or thermal warning;
- `.aimodel` / `.aimodelc` stayed ~3.087 GB; these were loading-only measurements,
  not a usable-recognizer or first-transcript result.

**Decoder diagnostic checkpoint 1 is complete, with execution still blocked.**
Length 1 works; length 4 aborts both as a first call and after length 1. CPU-only
also traps, and a fixed-length-4 export still aborts in the ANE path. See the
[checkpoint result](../../docs/coreai/decoder-diagnostic-checkpoint.md) and
[approved plan](../../docs/coreai/startup-plan.md). Stop at review: no full corpus,
KV-cache work, or production integration is authorized by this diagnostic result.

### Latest: bounded stateful checkpoint also blocked

The user separately approved the blocked-full-prefix alternative. Its
[checkpoint result](../../docs/coreai/stateful-decoder-checkpoint.md) supersedes
the preparation/review status above: fixed-one-token self-KV steps pass Mac
PyTorch comparison/reset checks, but the first phone step SIGABRTs in ANE/MPSGraph.
No phone logits or transcript returned. **Stopped for review; do not retry or
advance to corpus/production work.** The remaining original phase descriptions
below are historical gates, not instructions to rerun failed variants.

`export_stateful_decoder.py` reuses the frozen decoder with HF StaticCache,
224 slots and 64 FP16 state buffers. Cross projections still repeat per step.
It checks the predetermined control/lexical sequence against full prefixes in
SDPA and eager, bit-exact reset/replay, and captured-graph state persistence before
Core AI conversion. The predeclared diagnostic gate requires finite rows, equal
winners and max absolute error <=0.125; it is not transcript-parity acceptance.

For reproducing the **Mac-only** check, use a new output directory:

```sh
PY=/Users/tiger/.cache/uv/environments-v2/export-phowhisper-split-coreai-97c1d1b385bbb09a/bin/python
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 "$PY" Tools/CoreAI/export_stateful_decoder.py \
  --model-dir /Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/merge-fp16/model \
  --checkpoint .build/verification/coreai-decoder-diagnostic/checkpoints/001.wav.fp16 \
  --output-dir .build/coreai/stateful-reference-new
```

`--export` additionally converts to a distinct `decoder-stateful.aimodel` after
checks pass. Existing source/reference evidence is under
`.build/verification/coreai-stateful-decoder/candidate-buffer-binding/`; the
`h18p` AOT artifact is under `.build/coreai/stateful-decoder/aot/`.

The existing development probe now has separate `--coreai-stateful=steps` and
`--coreai-stateful=transcribe` modes. Both require `--coreai-fixture=001.wav`,
`--coreai-decode-only` and an explicit `--coreai-decoder-path`; no legacy case or
CPU-only flag. Core AI position input is Int32 (conversion narrows Torch Int64).
Native state/output buffers persist across calls without full-cache Swift copies.
The steps mode schedules eight tokens, resets, then replays. Transcription is a
separate deliberate launch, gated on successful phone comparisons; **it was not
run and must not be run after the current failure**. Rediscover the data-container
URL after every in-place install: its UUID can change without deleting app data.

## Invariants

- Keep the existing PhoWhisper Large-v2 lineage and VI/EN code-switch LoRA.
- Keep FP16.
- Do not switch to Whisper Large-v3.
- Do not quantize/palettize in this phase.
- Do not change the working normal Mural conversation path.
- Do not "fix" the known silence hallucination during runtime migration.
- The accepted model uses 80 mel bins and vocabulary size 51,865.

## Source model

Prefer the already-frozen merged source used by the successful loading test:

```text
/Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/merge-fp16/model
```

The reported weights were:

```text
3,086,759,768 bytes
SHA256 264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a
```

The source replay passed 22/22 normalized transcripts.

Only if that frozen source is unavailable should `merge_phowhisper.py` be used.

## Phase A: export split Core AI encoder + parity decoder

Run:

```bash
uv run Tools/CoreAI/export_phowhisper_split_coreai.py \
  --model-dir /Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/merge-fp16/model \
  --output-dir .build/coreai/split-export
```

The script refuses a model unless it sees:

- Whisper/PhoWhisper Large-v2 shape;
- 80 mel bins;
- `d_model=1280`;
- 32 encoder layers;
- 32 decoder layers;
- vocabulary 51,865.

It exports:

```text
phowhisper-cs-fp16-v1.encoder.aimodel
phowhisper-cs-fp16-v1.decoder.aimodel
```

The decoder intentionally has **no KV cache yet**. It accepts the full current
decoder prefix each step. This is slower, but makes the first Core AI
transcription implementation simple enough to debug stage-by-stage.

Do not optimize the decoder before transcript parity is proven or the user
explicitly approves the plan's blocked-full-prefix alternative. The bounded
fixed-length 1/4 controls below are diagnostics, not a KV-cache implementation.

## Phase B: AOT compile both assets

```bash
Tools/CoreAI/compile_split_aot.sh \
  .build/coreai/split-export \
  .build/coreai/split-aot
```

Always re-check:

```swift
AIModel.deviceArchitectureName
```

For the previous iPhone 17 test this was `h18p`.

Stage the matching pair under:

```text
Library/Application Support/CoreAI/PhoWhisperSplit/
```

with canonical names:

```text
phowhisper-cs-fp16-v1.encoder.<arch>.aimodelc
phowhisper-cs-fp16-v1.decoder.<arch>.aimodelc
```

The probe also accepts explicit paths:

```text
--coreai-encoder-path=/absolute/device/path
--coreai-decoder-path=/absolute/device/path
```

## Phase C: accepted frontend/tokenizer reuse

For this parity phase, Mural deliberately reuses the already-accepted
development assets at:

```text
Library/Application Support/PhoWhisperCS/phowhisper-cs-fp16-v1/
```

Specifically:

- `MelSpectrogram.mlmodelc` provides the exact accepted 80-bin frontend;
- the existing `PhoWhisperTokenizer` loads the same local tokenizer;
- `generation_config.json` provides the same suppression tokens.

This means the initial parity test changes only the encoder/decoder runtime.
It does **not** introduce a second mel implementation at the same time.

An alternate support directory can be supplied with:

```text
--coreai-support-dir=/absolute/device/path
```

## Phase D: stage the frozen audio corpus

Copy the same 22 accepted audio fixtures to:

```text
Documents/CoreAI/PhoWhisper/Fixtures/
```

or pass:

```text
--coreai-fixtures-dir=/absolute/device/path
```

Do not substitute new microphone recordings for the frozen parity corpus.

## Phase E: run the Core AI transcript probe

Build/install the normal Release app in place, preserving the existing bundle
identifier and user data.

Launch with:

```text
--coreai-asr-probe
```

The screen lets the tester prepare the split model and run the staged corpus.

For automated execution after launch, add:

```text
--coreai-asr-auto
```

Each invocation creates a UUID run directory and writes an initial report before
preparation, then updates it after preparation, each fixture, and completion/error:

```text
Documents/CoreAI/PhoWhisper/Runs/<runID>/report.json
Documents/CoreAI/PhoWhisper/Runs/<runID>/events.jsonl
Documents/coreai-asr-probe.json
```

The last path is only a latest/compatibility pointer. Retrieve it to discover the
fresh `runID`, then retrieve that run directory. A native abort leaves a partial
report and a flushed `decoder-before` without `decoder-after`; an empty `files`
array or a preparation status is not a successful inference. Stop the corpus at
its first thrown fixture error. Do not retry an unchanged crashing variant.

The probe now loads the encoder and decoder sequentially per fixture. Only an
owned, finite FP16 `[1,1500,1280]` buffer crosses their lifetime boundary; the
decoder input is checked for bit-exact preservation. Runtime allocation release
is measured, not assumed from Swift reference lifetimes.

For a bounded first-fixture check, add `--coreai-fixture=001.wav`. To isolate
runtime resources across processes, first run with `--coreai-encode-only`,
terminate that app process, then launch with `--coreai-decode-only` and the same
fixture selection. Checkpoints are development-only files under
`Documents/CoreAI/PhoWhisper/EncoderCheckpoints-v2/`. Metadata binds fixture
bytes, sample count, encoder/support content fingerprints and the FP16 tensor's
SHA-256. The decoder can be varied while keeping the exact hidden states fixed.
Legacy checkpoints remain untouched and are not accepted as v2 inputs. An
encode-only or bounded diagnostic result is not a transcript or a parity pass.

Fingerprints use the probe's recursive sorted Foundation JSON encoding. Do not
compare whole-tree digests produced by a different JSON serializer. Runtime-added
`specialized_model_*.mpsgraph` files can change a tree digest; compare original
files individually and record extras rather than deleting caches to force a match.

The JSON contains:

- per-result `encoderLoad` and `decoderLoad` cache/specialization/loadFunction timings;
- mel/tokenizer preparation timings (model loads are deferred until each fixture);
- exact transcript per fixture;
- detected language token;
- generated token count;
- mel, encoder, language detection, decoder, and total inference timings;
- per-file errors and explicit `endToken` / `tokenLimit` transcript termination;
- preparation asset fingerprints and decoder compute options;
- `runID`, mode and status, distinguishing diagnostics from transcripts.

The probe follows the pinned WhisperKit control prefix, first-step blank/EOS
suppression and special-token exclusion from `suppress_tokens`. It stops lexical
append at `Constants.maxTokenContext - 1`. These source-level alignments do not
establish end-to-end parity. Every raw output row is checked for finite values;
only the last row is saved and consumed.

Normal `Talk > On-device` still uses the old WhisperKit/Core ML recognizer.

## Bounded decoder diagnostics

Use one explicit fixture and the matching v2 checkpoint in a fresh app process:

```text
--coreai-asr-probe --coreai-asr-auto --coreai-fixture=001.wav
--coreai-decode-only --coreai-decoder-case=<case>
```

| Case | Teacher-forced calls |
| --- | --- |
| `one-one` | `[50258]`, then the same prefix again |
| `four` | `[50258,50278,50359,50363]` as the first call |
| `one-four` | `[50258]`, then the four-token prefix |

These are diagnostic inputs, not forced-language production decoding. Each call
records exact tokens, monotonic uptime, inference time, shape/type, all-row finite
validation, top-five logits, winner margin, sampled footprint, process-lifetime
RSS peak and thermal state. Last-row dumps are little-endian Float32 files named
`step-0001.logits.f32`, etc., each containing 51,865 values. They widen the FP16
output without changing its values. Footprint and RSS peak are distinct metrics.

`--coreai-decoder-cpu-only` requires a bounded case and a **source `.aimodel`**,
not a default-compute `.aimodelc`. It looks for
`phowhisper-cs-fp16-v1.decoder.aimodel` in the split directory unless an explicit
`--coreai-decoder-path` is supplied. It uses documented `.cpuOnly` specialization
and the persistent cache. CPU is a diagnostic control, not a shipping backend.

Observe each approved variant for at most roughly 90-120 seconds; stop on its
first failure and preserve its run plus correlated Mural crash evidence. Native
SIGABRT/SIGTRAP cannot be caught as Swift errors. Cancellation does not guarantee
interruption of an in-flight driver call. **The checkpoint's failing variants
have already been run; the commands here document them, not authorize retries.**

### Numerical reference

Reuse the existing split-export Python environment without installing packages.
`compare_decoder_logits.py` verifies the frozen weights and checkpoint digest,
runs the exact decoder wrapper on CPU/FP16 for both diagnostic prefixes, records
the resolved implicit attention implementation, then also evaluates eager
attention used by the accepted Python benchmark. It reports finite raw logits,
top candidates/margins, absolute/RMS differences and calls with missing outputs.
It sets no post-hoc numerical tolerance and does not label matching winners a
transcript-parity pass.

```sh
PY=/Users/tiger/.cache/uv/environments-v2/export-phowhisper-split-coreai-97c1d1b385bbb09a/bin/python
E=.build/verification/coreai-decoder-diagnostic
"$PY" Tools/CoreAI/compare_decoder_logits.py --self-test
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 "$PY" Tools/CoreAI/compare_decoder_logits.py \
  --model-dir /Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/merge-fp16/model \
  --checkpoint "$E/checkpoints/001.wav.fp16" \
  --run-dir "$E/one-one-run" \
  --output-dir "$E/reference-new"
```

Repeat `--run-dir` for additional runs; the output directory must not exist.
This isolates the decoder with identical hidden states. It does not validate the
Core AI encoder against PyTorch or Core ML.

### Fixed-length controls (checkpoint 1 only)

The split exporter accepts paired `--diagnostic-prefix-length=1|4` and
`--encoder-checkpoint=<001.wav.fp16>`. This skips encoder export and emits only
`<name>.decoder-fixed<N>.aimodel`, with unchanged FP16 source weights, no cache,
and no dynamic input dimensions. Direct PyTorch execution and captured graph
outputs must be bit-exact before conversion; this is not a Core AI numerical-parity assertion.
Its JSON records input identity, resolved attention, shapes and reference logits.

For an approved new reproduction, use a separate output directory, no overwrite,
and compile only the discovered architecture:

```sh
"$PY" Tools/CoreAI/export_phowhisper_split_coreai.py \
  --model-dir /Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/merge-fp16/model \
  --output-dir "$OUT/export" --diagnostic-prefix-length=4 \
  --encoder-checkpoint "$E/checkpoints/001.wav.fp16"
xcrun coreai-build compile "$OUT/export/phowhisper-cs-fp16-v1.decoder-fixed4.aimodel" \
  --platform iOS --min-deployment-version 27.0 --architecture h18p --output "$OUT/aot"
```

Stage under a distinct name and select it via `--coreai-decoder-path` with case
`four` (or `one-one` for fixed length 1). Never replace the accepted assets. These
controls cannot transcribe growing prefixes. Host compiler warnings and fallback
messages must be retained even when `coreai-build` exits successfully.

## Transcript parity gate

Compare `coreai-asr-probe.json` against the accepted FP16 baseline using the
same normalization rules used for the 22/22 source replay.

Required:

- **22/22 normalized matches**;
- no new code-switch word losses/substitutions;
- no NaN/non-finite failures;
- no app crash or Jetsam.

If any transcript differs, stop before KV-cache work and identify the first
divergent stage:

1. accepted Core ML mel output;
2. Core AI encoder;
3. language token;
4. decoder logits/token sequence;
5. detokenization.

Do not add transcript replacement rules or change thresholds to force parity.

## Performance evidence to collect

For every file retain:

```text
mel
encoder
language detection
decoder
total
generated token count
```

Also report one representative short English, Vietnamese, forward code-switch,
reverse code-switch, Yes, No, silence, and long-turn result separately.

The full-prefix decoder may be slower than WhisperKit. That is acceptable for
this parity checkpoint.

## After 22/22 parity

Only then implement the next optimization:

- export/state a KV-cache decoder;
- reuse persistent `InferenceFunction`s;
- rerun the entire 22-file corpus;
- compare phone latency and memory;
- profile actual Core AI compute placement.

The production conversation path must remain on WhisperKit until that
optimized Core AI path passes quality, latency, lifecycle, and resource gates.

## Superseded loading probe

The monolithic `--coreai-load-probe` UI from the prior checkpoint is intentionally removed from the app after its loading gate passed. Its evidence remains in `coreai_asr_handoff.md`; the monolithic export/AOT tools remain in this directory for reproducibility.
