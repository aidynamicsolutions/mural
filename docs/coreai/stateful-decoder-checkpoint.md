# Stateful Core AI decoder checkpoint

Status: **COMPLETE / blocked at first native inference; stopped for review.**
Date: September 16, 2026.
Authorization: [stateful handoff](stateful-decoder-handoff.md).

## Outcome

The fixed-one-token, persistent-self-KV candidate passes the bounded Mac PyTorch
checks, exports with 64 mutable state buffers, and compiles for `h18p`. Its first
phone inference, SOT at position zero with reset caches, **SIGABRTs in the
ANE/MPSGraph execution path**, with `0xe00002bc` / `0x12`.

No phone logits returned. There is no cached-step phone numerical comparison,
phone reset/replay success, completed transcript, corpus parity, or usable-startup
result. Fixture 001 transcription was **not attempted**, because its prerequisite
failed. No unchanged native-crash retry, backend sweep, or production integration.
Normal Talk remains WhisperKit/Core ML.

The failure category is native execution of this converted stateful graph on the
recorded device/toolchain. It is not a growing-prefix input: the only attempted
input token was `[50258]`, position zero, with fixed shapes. Its backend signature
resembles checkpoint 1, but the exact failing operator and export-versus-runtime
cause remain unresolved. No narrow evidence-backed native correction was found.

## Candidate and fixed ABI

`Tools/CoreAI/export_stateful_decoder.py` reuses the original HF decoder, weights,
attention implementations, and `StaticCache`; no transformer-layer rewrite.
Buffers are registered and rebound through module attributes during forward so
Torch export lifts the mutable storage instead of capturing Python-object aliases.
A fresh `EncoderDecoderCache` wraps the persistent self-cache for each step.

**Deliberate limitation:** cross-attention projections are recomputed every step.
This is a self-cache-only diagnostic, not the final optimized runtime.

| Value | Shape | Type |
| --- | --- | --- |
| `decoder_input_ids` | `[1,1]` | Int32 |
| `encoder_hidden_states` | `[1,1500,1280]` | FP16 |
| `cache_position` | `[1]` | Torch Int64, converted Core AI Int32 |
| `attention_mask` | `[1,1,1,224]` | FP16 |
| `key_0` / `value_0` through `key_31` / `value_31` | each `[1,20,224,64]` | FP16 mutable state |
| `logits` | `[1,1,51865]` | FP16 output |

Mask entries through the current position are zero; future positions use -65504,
not negative infinity. Host checks bound tokens/positions and require sequential
steps. The original query scaling order, embeddings, normalization, activations
and projection remain inside the original HF modules.

The existing Swift probe has distinct explicit `--coreai-stateful=steps` and
`--coreai-stateful=transcribe` modes. Both require `001.wav`, decode-only, an
explicit asset path, and no legacy diagnostic/CPU-only flags. Neither is a normal
Talk selection. Transcription requires a separate deliberate launch after review
of successful step evidence; it never follows automatically from the steps run.

The probe validates every state/input/output descriptor before inference. It owns
one shared-mode native Metal buffer with disjoint 4 KiB-aligned state regions,
using each descriptor's minimum size, preferred strides and interleave layout.
`MutableRawView`s borrow that buffer only across one awaited `run`. A persistent
NDArray receives preallocated logits. Complete caches are not copied through Swift
arrays per token. Storage belongs to one `decodeTurn`, is zeroed before sequences,
and is reset on normal/throwing/cancellation return. Native abort prevents Swift
cleanup but terminates the process; no storage survives into another process.

Teacher forcing schedules the eight-token sequence twice with an intervening
reset. The unexecuted transcription branch separately resets after language
detection and feeds each prefix token once. Existing suppression and token bounds
are retained. Phone persistence/reset/cancellation and transcription are unproven.

## Mac numerical and export evidence

Frozen weights SHA-256:
`264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a`.
Saved encoder tensor SHA-256:
`cdf3c3f5300103ad2b0a23e414b070041d21e7f7c0f77f18ce32bc52824957ae`.
Same fixture/support/encoder identities as checkpoint 1; no new encoder execution.

Predetermined sequence:
`[50258,50278,50359,50363,56,4690,286,1437]`.
The final four are the first four lexical tokens of the accepted fixture text,
not a replacement for model output. Every position is compared with the actual
accumulated full prefix and identical saved hidden states.

Before execution the script declared a **diagnostic**, not corpus-parity, gate:
all logits finite, identical raw winner, maximum absolute logit error <=0.125,
and bit-exact reset/replay. The absolute bound is eight FP16 ULPs at magnitude 16;
it is not an Apple accuracy guarantee and was not adjusted after seeing outputs.
Top-five ordering and full-row error metrics are reported separately.

| Reference attention | Steps | Same winner / top-five order | Largest absolute error |
| --- | ---: | --- | ---: |
| SDPA, implicit export selection | 8 | 8/8 for both | 0.015625 |
| Eager, accepted Python benchmark selection | 8 | 8/8 for both | 0.0263671875 |

Both modes reset and replay all eight steps bit-exactly. Full reference and cached
Float32-widened rows are retained. Torch capture plus Core AI decompositions has
exactly 64 registered mutation outputs, no dynamic dimensions, and its executable
Torch module passes successive-step comparisons. This proves Torch state reuse,
not Core AI state reuse or encoder numerical parity.

The first capture failed during decomposition with
`expected compiled_fn to be GraphModule, got <class 'function'>` and lifted-tensor
warnings. The narrow correction disabled unnecessary parameter gradients and
explicitly rebound cache tensors through registered buffers. The corrected export
passed; the failed attempt remains in evidence. No dependency was installed.

Versions: Python 3.11.11; torch 2.11.0; transformers 4.57.3; coreai-core 1.0.0b2;
coreai-torch 0.4.1; numpy 2.4.6. CPU, FP16, four Torch threads, offline local loading.
Source asset: 1,813,298,356 bytes. AOT asset: 1,816,242,407 bytes. Compiled only
`h18p` with default options. The retained compiler log contains only
`Compiling h18p: 1 of 1`, with no emitted warning. Export retains the existing
TreeSpec deprecation warning. Phone runtime warns about 6 versus 5 GPU cores;
this does not prove the crash cause or complete compute placement.

## Phone runs and crash correlation

Rediscovered Kevq, iPhone 17 / iPhone18,3, UDID
`00008150-000D25942278401C`, iOS 27.0 `24A435`, Core AI `h18p`.
Xcode 27.0 `27A5252f`, SDK `24A5422a`; host macOS 26.6.2.
Release installed in place as **`com.kevintruong.mural.dev`**.
Final executable SHA-256:
`c9585500383156a5182cd6f751c092e5188466c38a4bcd25d70edada8aebdf90`.

| Run ID | Reached | Outcome |
| --- | --- | --- |
| `68BD24B1-9493-4097-ADFE-D4B13F9039B9` | Path validation | No inference: in-place install relocated the data-container URL. Corrected using fresh container discovery. |
| `D376E084-1E4B-47B9-BDEE-8D9134B23371` | Load and ABI validation | No inference: host expected Int64 position; converter narrows it to Int32. Corrected host ABI based on installed converter source. |
| `8DD5F737-3687-4A72-AD6F-4B1A07C31529` | First stateful `run` | PID **42094**, native SIGABRT, no output. Stopped. |

The load-only ABI-blocked run had a specialization-cache miss: lookup 0.002 s,
specialization **94.768 s**, function load 5.057 s. The final run hit that cache:
lookup 0.002 s, specialization 0, function load 6.606 s. Preparation fingerprint,
mel and tokenizer work was 4.001 s in the final run. These are diagnostic samples,
not a timing distribution or evidence for the 12-15-second readiness objective.

The final flushed event records state reset ID
`1BDA127D-FC16-4E63-8D32-5BA40DD78F12`, token `[50258]`, position 0, call 1.
There is no corresponding `decoder-after` or logits file. Sampled footprint at
that boundary is 1,919,946,032 bytes; process-lifetime RSS peak 2,150,055,936 bytes;
thermal state nominal (0). These are boundary samples, not peak driver-memory or
soak measurements.

Crash: `Mural-2026-09-16-085749.ips`, capture 08:57:44 +0700, PID 42094,
`EXC_CRASH / SIGABRT`, with `MTLReportFailure` and
`GPU::ANERegionCallOpHandler::encodeAsynchronousWithIOFences` frames.
Crash SHA-256:
`1802fdc920b92d6eeb5b948f69fd358e256208f9d0ff0e3f9237440fb8cd4935`.
Scoped Mural logs show ANE `0xe00002bc` / `0x12` immediately after the first call.
The Mural crash inventory grew by this one report. No full-device logs collected.

Phone pre-load decoder fingerprint:
`7be77e33bf8a56706f7c43bf6d09b38f742f18046c37053412f4ad3b8c1b73de`.
Phone encoder/support hashes match checkpoint 1. New stateful assets have distinct
names under `Library/Application Support/CoreAI/PhoWhisperStateful/`; original
assets and caches remain. Local original source/AOT file hashes are recorded in
`artifact-files.json`; no post-run multi-GB phone rehash is claimed.

## Preservation, validation and evidence

All incoming uncommitted work is retained. Starting tracked diff and untracked
files are backed up in `resume-starting-worktree/`. `MuralApp.swift` extends the
existing probe; `VietnameseEnglishRecognizer.swift` and the original exporter and
helper tests are unchanged by this checkpoint. Documentation updates link this
outcome without erasing prior results. No commit, reset, uninstall, learning-data
change, cache deletion, precision change, cloud request, toolchain update,
subagent, publication or hybrid implementation.

Release build/install passed. Initial compile errors in scalar-type naming and
borrowed-view lifetimes were corrected using the documented Core AI API; native
state storage gives the views a single call-scoped owner. Current project remains
Swift 5 language mode / targeted concurrency; no strict-Swift-6 audit is claimed.
Existing interruption deprecation and missing-AppIntents warnings remain.
Probe-contract, accepted-mel-reader, comparison self-test, Python syntax/boundary
checks and diff whitespace checks passed. Mac export is itself a runnable
numerical/persistence/reset check; no inference on the unsupported macOS Core AI
runtime was attempted.

Evidence root: `.build/verification/coreai-stateful-decoder/`:

- `candidate/`, `export.log`: first capture failure plus passing PyTorch rows.
- `candidate-buffer-binding/`, `export-buffer-binding.log`: corrected export,
  raw/decomposed signatures/graph, references, comparisons and report.
- `compile-h18p.log`, `artifact-files.json`; AOT under
  `.build/coreai/stateful-decoder/aot/`.
- `path-blocked/`, `abi-blocked/`, `steps-run/`: distinct fresh run evidence.
- `steps-launch.json`, `steps-runtime.log`, `phone-comparison.json`: one attempted
  inference and explicitly unavailable numerical outputs, not a false pass.
- Named IPS, `crash-summary.json`, before/after crash inventories.
- Build/install logs, executable hash, device/project settings, final process list.
- Owned capture cleanup files: all captures exited. No Mural process remains.

## Review gate

This bounded experiment is finished and blocked. Do not retry this asset, run
fixture transcription, broaden to 22 fixtures, or connect Core AI to Talk.
A toolchain change, external bug submission, different backend/cache design or
hybrid experiment needs review. The current evidence does not identify a safe
small native fix, and does not establish usable Core AI recognition. Keep the
working WhisperKit path. Encoder parity, quality, startup, memory coexistence,
lifecycle and user microphone/listening acceptance remain later gates.
