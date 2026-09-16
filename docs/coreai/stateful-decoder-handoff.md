# Continue the approved stateful Core AI decoder proof

Status: **Historical approved handoff, now executed.** See
[stateful-decoder-checkpoint.md](stateful-decoder-checkpoint.md): Mac proof passed,
first stateful phone inference aborted; stopped for review. The preparation-only
notes below describe the incoming state, not the current implementation.
Date: September 16, 2026.

## Latest user authorization

After completing diagnostic checkpoint 1, the user asked whether Core AI was still
worth pursuing. We recommended one additional bounded experiment, not continuing
the crashing full-prefix approach:

1. Build a diagnostic one-token decoder with persistent attention/KV state and
   the exact existing FP16 weights.
2. Feed a short predetermined sequence through successive cached steps. Compare
   each step against PyTorch with identical encoder input.
3. Only if those checks pass, complete fixture 001 and compare its accepted text.
4. Return for review before broader work.

The user replied: **"Okay, let's do your recommendations."** This authorizes that
stateful diagnostic checkpoint, including necessary export, architecture-matching
AOT compilation, in-place app build/install and bounded phone runs. Do not ask
again for those already-approved actions.

We explicitly confirmed normal Talk stays on WhisperKit and existing changes
will be preserved. The user then requested this handoff before implementation.

Stop on a native backend failure without a narrow evidence-backed correction, or
unresolved prediction divergence. No unchanged crashing retries, unrestricted
backend/export sweep, full corpus, production integration, OS/toolchain update,
external publication, or automatic fallback/hybrid implementation. Those remain
later decisions. No subagents. User performs live microphone/listening acceptance.

## Read first

1. This handoff.
2. [Decoder checkpoint 1 result](decoder-diagnostic-checkpoint.md).
3. [Startup plan](startup-plan.md), especially the blocked-full-prefix alternative
   and production-shaped decoder requirements. This new approval advances only
   the bounded candidate proof, not all later gates.
4. `Tools/CoreAI/README.md` and the current source files below.
5. `.agents/skills/verify-mural/SKILL.md`; its feature path is relative to the skill:
   `.agents/skills/verify-mural/features/local-conversation.md`.
6. Applicable global instructions, Swift concurrency and Sosumi documentation skills.

The older [decoder-diagnostic-handoff.md](decoder-diagnostic-handoff.md) describes
checkpoint 1 before its continuation. Its old next-action list is superseded.
Do not rerun that matrix.

## What checkpoint 1 established

- The Core AI encoder runs and returns finite FP16 output. The saved tensor is
  reproducible and handed to the decoder bit-exactly. Encoder numerical parity
  against PyTorch/Core ML is not independently established.
- Dynamic decoder length 1 repeated: finite, bit-exact repeated phone rows;
  winner/top-five agree with the frozen PyTorch reference, with small raw-logit
  differences, not bit-exact numerical parity.
- Dynamic length 4 first and length 1 then 4: both SIGABRT in the ANE/MPSGraph path,
  status `0xe00002bc` / `0x12`.
- Source decoder specialized with `.cpuOnly`, length 4: SIGTRAP in
  `BNNSCoreAIDelegate` / `CoreAIRuntime`.
- Fixed-length-1 control: two successful calls. Fixed-length-4 control: the same
  ANE abort. Static dimensions alone are not sufficient.
- No completed Core AI transcript, 22/22 parity, or usable 12-15-second startup.
- Cause category is native execution of the converted multi-token decoder on
  this toolchain/device. The exact operator and export-versus-runtime root cause
  remain unresolved. It is not merely a shape transition or model co-residency.

Why the new experiment is justified: one-token execution with remembered history
is a materially different graph, and is the natural autoregressive runtime
shape. Merely repeating the existing stateless length-1 control would lose all
context and is NOT a recognizer. KV caching is not a new model or quantization,
but its changed arithmetic/execution still needs numerical and transcript proof.

AOT loading was previously 11.7-14.8 seconds for a monolithic loading-only test.
That does not establish startup for the final stateful artifact. Some on-device
specialization remains after AOT; count first inference/warmup in readiness.

## Checkout and preservation

Root: `/Users/tiger/Dev/ios/mural`
Branch: `mvp`
HEAD: `cedc4a6dc918bb561e763edfd10d66e7c3835165`

Existing uncommitted work at the start of this stateful checkpoint:

- Modified `App/MuralApp.swift`.
- Modified `App/VietnameseEnglishRecognizer.swift`.
- Modified `Tools/CoreAI/README.md`.
- Modified `Tools/CoreAI/export_phowhisper_split_coreai.py`.
- New `Tools/CoreAI/compare_decoder_logits.py`.
- New `Tools/CoreAI/test_probe_contract.py`.
- New `docs/coreai/decoder-diagnostic-checkpoint.md`.
- New `docs/coreai/decoder-diagnostic-handoff.md`.
- New `docs/coreai/startup-plan.md`.

This handoff is an additional new document. No commit or reset was made.
Before writing this handoff, the tracked diff was checked byte-for-byte against
the stateful checkpoint's starting snapshot: **no tracked source edits yet**.

Starting snapshot and fresh preparation evidence:

```text
.build/verification/coreai-stateful-decoder/
  starting-worktree/implementation.diff
  starting-worktree/status.txt
  starting-worktree/Tools/CoreAI/{compare_decoder_logits.py,test_probe_contract.py}
  starting-worktree/docs/coreai/{decoder-diagnostic-checkpoint.md,
                               decoder-diagnostic-handoff.md,startup-plan.md}
  devices.txt
  descriptor-doc.json
  run-doc.json
  views-doc.json
```

Use this evidence directory for the new checkpoint; retain earlier evidence in
`.build/verification/coreai-decoder-diagnostic/`, including `continuation/`.
Do not clear caches, remove historical assets, uninstall Mural, or change learning
data. Preserve the accepted frontend/tokenizer, suppression, accents, weights,
FP16, and existing known recognition errors. No cloud requests or transcript fixes.

## Current device, build and source identities

Rediscovered at the start of this checkpoint:

- Kevq, iPhone 17 / iPhone18,3, available/paired.
- UDID `00008150-000D25942278401C`; rediscover before use.
- Last verified iOS 27.0 `24A435`, Core AI architecture `h18p`.
- Last verified Xcode 27.0 `27A5252f`, SDK build `24A5422a`.
- Mac macOS 26.6.2 `25G83`, 16 GB RAM. About 122 GiB disk available at preparation.
- Existing installed identity: **`com.kevintruong.mural.dev`**. Keep the override.
- Last installed Release executable SHA-256:
  `f0010befefb1ba75734bfdd0c5b8aa7e21f891cb02b88d790071bf303bb29a1e`.
- Last checkpoint ended with no Mural process or owned log capture running.
  This stateful preparation started no persistent processes, builds or phone runs.
  Do not signal historical PIDs.

Reuse the existing Release build path, with the rediscovered device:

```sh
xcodebuild -project Mural.xcodeproj -scheme Mural -configuration Release \
  -destination "platform=iOS,id=$DEVICE_UDID" \
  -derivedDataPath .build/local-mvp-phase-1-device-derived-data \
  PRODUCT_BUNDLE_IDENTIFIER=com.kevintruong.mural.dev build
```

App: `.build/local-mvp-phase-1-device-derived-data/Build/Products/Release-iphoneos/Mural.app`.
Inspect current project configuration before changing files; `project.yml` does
not exist at the repo root. Do not regenerate or manually edit generated project
files unnecessarily. Existing build warnings include the conversation
interruption deprecation and missing AppIntents metadata dependency.

Frozen merged model:

```text
/Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/merge-fp16/model
```

Weights SHA-256:
`264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a`.

Existing Python environment, no dependency installation needed:

```text
/Users/tiger/.cache/uv/environments-v2/export-phowhisper-split-coreai-97c1d1b385bbb09a/bin/python
```

Python 3.11.11, torch 2.11.0, transformers 4.57.3, numpy 2.4.6,
safetensors 0.8.0, coreai-core 1.0.0b2, coreai-torch 0.4.1.
Implicit model attention resolves to SDPA in this environment. The accepted
original Python benchmark selected eager; compare/record both as appropriate.

Fixture 001 checkpoint:

```text
.build/verification/coreai-decoder-diagnostic/checkpoints/001.wav.fp16
.build/verification/coreai-decoder-diagnostic/checkpoints/001.wav.json
```

- Hidden shape `[1,1500,1280]`, FP16, 3,840,000 bytes.
- Tensor SHA-256: `cdf3c3f5300103ad2b0a23e414b070041d21e7f7c0f77f18ce32bc52824957ae`.
- Fixture `.build/coreai/fixtures/001.wav`, 90,560 samples / 5.66 seconds.
- Audio SHA-256: `e9789f09cf31930239ff5842a1b502103844481d4669fb7e0de77b69966b597f`.
- Phone checkpoint: `Documents/CoreAI/PhoWhisper/EncoderCheckpoints-v2/`.
- Accepted baseline: `/Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/coreml-pinned-runtime.jsonl`.
- Fixture 001 accepted language is `vi` / 50278, despite English text:
  `Yesterday I went to the supermarket.` Do not "correct" language detection.

Default phone assets: `Library/Application Support/CoreAI/PhoWhisperSplit/`.
Accepted support: `Library/Application Support/PhoWhisperCS/phowhisper-cs-fp16-v1/`.
All original AOT files were verified equal to the Mac originals. Phone AOT trees
also contain extra specialized graph files, preserved intentionally. The same
Swift fingerprint helper reconciles these trees; Python JSON tree digests are
not interchangeable with Foundation JSON digests. Local accepted support and
phone support fingerprints match. See checkpoint 1 report for hashes.

Stage new stateful assets under distinct names and select an explicit probe path.
Do not overwrite the dynamic or fixed diagnostic assets. Compile only `h18p`,
not every supported architecture, and retain compiler warnings even on exit 0.

## Existing code to reuse

### Swift: `App/MuralApp.swift`

`CoreAIPhoWhisper` is a private actor and `CoreAIASRProbe` is the development-only
observable runner. Normal Talk is independent and remains on WhisperKit.

- `Config.resolve`: existing explicit model/support paths, bounded decoder-case
  flags, CPU-only source guard, encode/decode-only validation.
- `prepare`: fingerprints encoder/decoder/support; loads accepted mel/tokenizer;
  records options and run identity.
- `transcribe`: decode-only path validates fixture/model/support/tensor identities,
  then calls `decodeTurn`. Encoder/checkpoint code is already working.
- `decodeTurn`: currently loads full-prefix `main`, checks hidden-state bits,
  handles existing diagnostic cases, otherwise language-detects then generates.
- `decode`: currently allocates token tensor `[1,prefixLength]`, runs `main`, checks
  all raw logits for finiteness, saves only last-row f32, persists before/after
  events including tokens, timing, memory, thermal, winner/top five.
- `loadAsset`, `inputDescriptor`, `readLogits`, `event`, `checkedArgmax` and hashing
  helpers are reusable. Do not duplicate them into a second probe framework.
- Reports live under `Documents/CoreAI/PhoWhisper/Runs/<UUID>/`; the latest pointer
  is `Documents/coreai-asr-probe.json`. Retrieve the fresh runID, never a stale run.
- The inherited suppression filter excludes special IDs as pinned WhisperKit does;
  lexical token append stops at `Constants.maxTokenContext - 1` (223). Preserve it.
- `test_probe_contract.py` extracts the Swift helper block starting at `sha256`
  through the actor's end for a Mac test. Keep new Core AI-dependent methods out
  of that extracted block, or narrowly update its extraction if necessary.

Add a clearly bounded stateful mode, requiring one explicit fixture and explicit
stateful asset, rather than changing default ASR selection or allowing the entire
corpus accidentally. Teacher-forced proof and fixture transcription should be
separate deliberate runs, so failed comparison cannot silently advance.

### Python

- `export_phowhisper_split_coreai.py`: existing model-shape validation,
  `DecoderModule`, conversion/decomposition, metadata and saving helpers. Its
  current fixed-prefix flags are the completed checkpoint 1 controls, not KV.
- `compare_decoder_logits.py`: frozen weight hash, file hashing, finite-row
  summaries, stable top-five ordering and raw difference metrics. Reuse these.
  Its existing CLI only accepts prefixes of length 1/4; stateful successive-step
  comparison will need the actual accumulated prefixes and position/state identity.
- `test_mel_reader.py`, `test_probe_contract.py`: already passing focused checks.
- Pinned clean WhisperKit checkout:
  `.build/local-mvp-phase-1-device-derived-data/SourcePackages/checkouts/argmax-oss-swift/`,
  commit `1e2a163736dfa5a198e637ae44c114e1c6d5cc2d`.

## API/source findings already gathered

Do not mistake this research for an implemented design. No cache ABI, model
wrapper, exporter flag or Swift stateful mode has been written yet.

### Core AI Swift

Official docs saved in the new evidence directory:

- [InferenceFunction.run](https://developer.apple.com/documentation/coreai/inferencefunction/run(inputs:states:outputviews:)-mqfb):
  `run(inputs: [String: NDArray], states: consuming MutableViews, outputViews: consuming MutableViews) async throws -> Outputs`.
  States are read/write in-out arguments; views for **all** states are required.
  Preallocated output views receive output in place and are omitted from returned outputs.
- [InferenceFunctionDescriptor](https://developer.apple.com/documentation/coreai/inferencefunctiondescriptor):
  `stateNames`, `stateDescriptor(of:)`, input/output names/descriptors.
- [MutableViews](https://developer.apple.com/documentation/coreai/inferencefunction/mutableviews):
  insertion overloads for mutable NDArrays/views.

Use persistent native state/output buffers. Do not round-trip complete caches
through Swift arrays each token. Scope mutable views to one awaited call and keep
actor ownership/cancellation safe. Native aborts are not throwable Swift errors;
a task timeout/cancellation cannot guarantee interruption of a driver call.

The public SDK interface exists at
`$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/CoreAI.framework/Modules/CoreAI.swiftmodule/arm64e-apple-ios.swiftinterface`,
but a search for the concrete definitions there returned nothing. It may reexport
another module; inspect rather than repeat that same search. Sosumi docs provided
the relevant signatures above.

### Installed `coreai_torch`

Base: the existing environment's `lib/python3.11/site-packages/`.

`coreai_torch/converter.py:196-216` documents:

```python
TorchConverter(...).add_exported_program(
    exported_program,
    input_names=...,       # non-stateful forward arguments only
    output_names=...,      # returned values, not mutation outputs
    state_names=...,       # buffers in registration order, then mutated user inputs
    entrypoint_name="main",
)
```

Caller must run the existing decomposition table first. Multiple entrypoints
are supported, but do not add a second function unless the selected cache design
needs one. Standard `aten.scatter` / `index_put` lowerings exist in
`coreai_torch/_aten_to_core.py`; `index_copy` itself had no direct-name match.
No conversion/runtime support for a particular cache update has been proved yet.

### Installed Transformers Whisper

`transformers/models/whisper/modeling_whisper.py` was inspected:

- `WhisperAttention.forward` scales the projected query **before** attention;
  the attention implementation receives `scaling=1.0`. Preserve that arithmetic
  order, not just the mathematically equivalent formula.
- Head layout is batch/head/sequence/head-dimension. For the accepted model,
  verify configuration rather than assuming dimensions when authoring the wrapper.
- `EncoderDecoderCache` distinguishes self/cross caches and reuses cross K/V after
  initialization. The library already has useful cache machinery; inspect before
  writing a manual transformer implementation.
- Decoder layers: self-attention pre-norm/residual, cross-attention
  pre-norm/residual, final pre-norm/FC1/activation/FC2/residual. Decoder final norm
  then output projection. Reuse existing weights/modules and activation exactly.
- Whole decoder accepts `cache_position`, `position_ids`, attention mask and
  `past_key_values`. Be careful not to trace a Python constant position or grow
  the position-ID array; per-step tensor dimensions must remain stable.

`transformers/cache_utils.py:248-354,1031-1107`:

- `StaticCache`/`StaticLayer` are designed for compile/export.
- Early initialization is required for export rather than lazy allocation during
  tracing. Cache buffers are `[batch,heads,max_cache_len,head_dim]` per layer.
- Update uses `index_copy_(2, cache_position, new_values)`.
- Do not presume a Python cache object is automatically lifted as persistent Core
  AI state. Inspect the exported graph signature and prove cross-call persistence.

### Apple authoring guidance, not a mandate to rewrite everything

Inspected this pinned source:
[Neural Engine rules](https://github.com/apple/coreai-models/blob/7359dbcf6c3babb4fbfadfd015ffcc1cb6d87420/skills/skills/model-authoring/references/neural_engine_rules.md).

Relevant guidance: static shapes, rank <=5, careful FP16/layout handling; its
ANE-oriented cache recipe uses readonly past-cache inputs plus per-step new-K/V
outputs, updating cache outside the model. It cautions against IEEE negative
infinity in ANE softmax and describes a finite negative mask. These are possible
implementation leads, not explanations proven for our crashes and not permission
to change model precision or silently alter decoding behavior. This alternate
cache pattern could use native output buffers, but do not build two designs at once.

The attempted path `primitives/macos/cache.py` at that commit returned 404. Do not
repeat that URL. No repository clone or new dependency was installed.

## Design decisions still to make

Pick the smallest supported design after checking the actual export signature.
Potentially reuse HF static caching with lifted buffers; otherwise use a narrow
wrapper reusing the original modules and native state/output buffers. No generic
provider framework, custom kernel suite or full transformer rewrite up front.

Required behavior whichever representation is selected:

- Fixed one-token input, fixed-size position/mask inputs and bounded cache storage.
- Preserve attention scaling, positions, masking, FP16 weights and control tokens.
- Each prefix token is fed once; do not lose history or double-feed SOT.
- Language detection must not contaminate or duplicate transcription state.
- Reset all per-turn caches, including after failure/cancellation. Include a small
  reset/replay check so a second sequence cannot reuse stale state.
- Return the one needed logits row, preserving all-finite checks and raw evidence.
- Keep mask/position bound checks at the host boundary; do not access cache out of range.
- Cross-attention projection caching can require an initialization function or
  separate cache inputs. No final choice was made. A self-cache-only diagnostic
  would still repeat cross projections; label that deliberate limitation and do
  not present its timings as the final optimized runtime.

## Exact next actions

1. Read the current source and this approval, check Git/device state, preserve the
   existing diff. No repeat of the completed full-prefix/fixed-4 crash matrix.
2. Select and implement one minimal fixed-step cache representation using the
   installed APIs. Define its fixed tensor/state ABI before patching Swift.
3. On Mac **PyTorch**, use the saved tensor to compare successive steps with
   full-prefix reference logits, first control tokens then a few lexical tokens.
   Verify state persistence, reset, positions, finite values and actual predictions.
   Do not execute Core AI Swift/Python runtime on this macOS 26 host assuming iOS
   27 runtime availability. Export/compile tooling is available here.
4. Export the unchanged FP16 source under a new name; inspect graph/state
   signatures and record identity, versions and reference outputs. Compile `h18p`
   only, default matching options unless a concrete finding justifies a change.
5. Extend the existing development probe, not production Talk. Build Release,
   install in place with the preserved bundle override, stage distinct assets.
6. Run one fresh-process bounded cached-step diagnostic on the rediscovered phone.
   Capture flushed before/after call records including current token, accumulated
   prefix, position, state reset/run identity and available logits. Correlate any
   native termination with a scoped Mural crash report. Stop its first failure.
7. Compare the phone steps against the saved numerical reference. No post-hoc
   tolerance or output replacement to manufacture a pass. Only if successful,
   run fixture 001 to completion and compare the unchanged accepted transcript.
8. Write the checkpoint outcome and stop for review. No 22-file corpus or
   production integration in this approval. Report all remaining performance,
   encoder-parity, lifecycle and microphone acceptance limits honestly.

All future phone observations need finite budgets and owned-capture cleanup.
Use fresh run IDs. If the phone is locked/disconnected, report that concrete
blocker rather than reset data, silently change devices, or retry native crashes.
