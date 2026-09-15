# Core AI PhoWhisper migration tools

This directory contains the staged migration of Mural's accepted
`phowhisper-cs-fp16-v1` model from WhisperKit/Core ML to Core AI.

The goal is **startup + inference runtime migration without changing ASR
weights or transcript quality**.

## Current checkpoint

The first AOT loading gate passed on the physical iPhone 17 (`iPhone18,3`,
Core AI architecture `h18p`):

- previous Core ML / ANE first prepare: ~215 s historical;
- Core AI AOT cold ready: 11.73–14.82 s across three controlled cache misses;
- Core AI cached ready: 5.35–5.78 s, dominated by `loadFunction("main")`;
- no correlated Mural crash, Jetsam, memory-pressure termination, or thermal warning;
- `.aimodel` / `.aimodelc` stayed ~3.087 GB, so Core AI solved loading, not model size.

The cached <=5 s target is now an optimization target rather than a blocker.
The migration proceeds to **transcript parity**.

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

Do not optimize the decoder before transcript parity is proven.

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

The probe writes after every fixture:

```text
Documents/coreai-asr-probe.json
```

The JSON contains:

- encoder and decoder cache/specialization/loadFunction timings;
- mel/tokenizer preparation timings;
- exact transcript per fixture;
- detected language token;
- generated token count;
- mel, encoder, language detection, decoder, and total inference timings;
- per-file errors.

Normal `Talk > On-device` still uses the old WhisperKit/Core ML recognizer.

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
