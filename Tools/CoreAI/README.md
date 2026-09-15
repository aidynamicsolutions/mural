# Core AI PhoWhisper loading spike

This directory implements the first decision gate for moving Mural's accepted
`phowhisper-cs-fp16-v1` model from WhisperKit/Core ML to Core AI.

The goal is **loading time**, not a model change.

## Invariants

- Keep the existing PhoWhisper Large-v2 lineage and VI/EN code-switch LoRA.
- Keep FP16 for this spike.
- Do not switch to Whisper Large-v3.
- Do not quantize/palettize during this spike.
- Do not replace the working Core ML conversation path yet.
- The current model uses **80 mel bins**. Apple's stock CoreAISpeech Whisper
  preset currently uses 128 mel bins for v3 and is not a drop-in frontend.

## 1. Prefer the already-frozen merged source

The previous Mural PhoWhisper work may already have a verified merged Hugging
Face checkpoint under the local benchmark/evidence directories. Reuse it if
available.

Only if that exact source is missing:

```bash
uv run Tools/CoreAI/merge_phowhisper.py \
  --output /absolute/path/to/phowhisper-cs-fp16-v1-hf
```

The script pins the base and adapter revisions recorded by the MVP evidence.

Before conversion, replay the frozen Mural ASR corpus against the source model.
Stop if it no longer reproduces the retained baseline.

## 2. Export to `.aimodel`

```bash
uv run Tools/CoreAI/export_phowhisper_coreai.py \
  --model-dir /absolute/path/to/phowhisper-cs-fp16-v1-hf \
  --output-dir .build/coreai/export
```

The exporter refuses the model unless it sees the expected Large-v2/PhoWhisper
shape, including `[1, 80, 3000]` input features and vocabulary size 51,865.

It is adapted from Apple's `apple/coreai-models` Whisper exporter. See
`APPLE_COREAI_MODELS_LICENSE.txt`.

## 3. AOT compile

```bash
Tools/CoreAI/compile_aot.sh \
  .build/coreai/export/phowhisper-cs-fp16-v1.aimodel \
  .build/coreai/aot
```

Do not force a preferred compute unit on the first run. Core AI's default
specialization is the baseline.

AOT should produce an architecture-specific asset such as:

```text
phowhisper-cs-fp16-v1.<arch>.aimodelc
```

## 4. Stage the asset on the iPhone

Mural's load probe searches, in order:

1. `--coreai-model-path=<absolute path>` when supplied at launch.
2. `Application Support/CoreAI/PhoWhisper/`
3. `Documents/CoreAI/PhoWhisper/`
4. the app bundle.

The canonical filename is:

```text
phowhisper-cs-fp16-v1.<AIModel.deviceArchitectureName>.aimodelc
```

Use the installed Xcode's `devicectl` help to choose the supported copy command
for the current seed. Do not uninstall Mural and do not reset learning data.

## 5. Build and launch the load probe

Use the normal Mural Release/device workflow and preserve the existing bundle
identifier override.

Launch with:

```text
--coreai-load-probe
```

For a controlled uncached Core AI run, add:

```text
--coreai-reset-cache
```

That flag deletes only the cache entries derived from the selected Core AI test
asset. It does not touch Core ML caches, learning data, or other Core AI models.

The probe measures:

- cache lookup
- specialization when needed
- `loadFunction("main")`
- total ready time
- cache hit/miss
- device Core AI architecture

It writes:

```text
Documents/coreai-load-probe.json
```

and emits content-free `CoreAIProbe` OSLog events.

## Decision gate

Historical Core ML/ANE cold preparation was ~215 s and cached preparation ~6 s.

Continue to the full Core AI transcription runtime only if the AOT asset is
materially better:

- cold AOT ready: **<= 55 s** minimum useful gate
- warm/cached ready: **<= 5 s**
- stretch cold target: **<= 15 s**

If AOT is still >60 s, stop and report. Do not build a new decoder merely
because Core AI is newer.

## After the loading gate passes

The next implementation step is transcript parity:

1. add a Mural-specific 80-mel Core AI PhoWhisper frontend;
2. preserve the current tokenizer/control-token behavior;
3. start with the simplest correct greedy decoder;
4. replay the frozen corpus;
5. only then optimize the decoder (for example KV cache) and integrate normal
   on-device conversation.

See `coreai_asr_handoff.md`.
