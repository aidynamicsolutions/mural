# Plan A — Breeze-ASR-25 for Taiwan Mandarin + English

## Decision and scope

Implement one local, non-streaming ASR probe through the existing audio owner.
The target is Taiwan **Mandarin**, with English preserved verbatim; this is not a
claim of Taiwanese Hokkien support. Keep the working Vietnamese Talk default.
Do not add a provider abstraction or start FireRed in the same change.

Breeze is a Whisper-large-v2 fine-tune. Its published contract is 80 mel bins,
1280 hidden width, 32 encoder/32 decoder layers and 51865 vocabulary entries.
That makes reuse of the existing runtime practical, but **does not make the
PhoWhisper encoder, decoder, tokenizer vocabulary or compiled assets interchangeable**.
Sources: [official card](https://huggingface.co/MediaTek-Research/Breeze-ASR-25),
[config](https://huggingface.co/MediaTek-Research/Breeze-ASR-25/blob/main/config.json),
[generation config](https://huggingface.co/MediaTek-Research/Breeze-ASR-25/blob/main/generation_config.json).

## A1. Freeze the model and establish one candidate

Resolve a full immutable revision of `MediaTek-Research/Breeze-ASR-25`. Keep the
weights, processor, tokenizer, generation settings and license notices together
outside Git; record source hashes and the exact conversion environment. Check
model and dependency notices before distribution. A model-card license label is
not a complete audit of every dependency or training-data right.

Replay a few private short recordings using `run_reference.py breeze` before a
full corpus run. The published `config.json` contains an older forced English
prefix, while `generation_config.json` allows automatic language. The helper
clears that forced prefix in memory and requests **transcribe**, not translate.
Never mutate the frozen source or force English to obtain a fluent-looking result.

Use the existing Mac WhisperKit conversion environment and
[WhisperKitTools](https://github.com/argmaxinc/whisperkittools). Inspect its installed
CLI help rather than guessing flags. Freeze the tool revision and keep the app's
current dependency pins. Build an FP16 host reference, then **one PAL8 Core ML
encoder/decoder candidate** with the matching 80-mel frontend. Do not repeat the
historical eager FP16 phone experiment, start a PAL4/PAL6 campaign, or borrow a
community binary without reproducing provenance. PAL8 is palettization, not FP8.

Inspect compiled input/output contracts and actual compression on the Mac.
Replay the same recordings on the converted model; align token budgets, language
policy and decoding heuristics before attributing a difference to conversion.
Separate conversion agreement from human-reference accuracy. Quantization may
change transcripts; log and review differences rather than editing references.

`prepare_breeze.py` packages the already compiled three-model set and source
support. It checks topology, files and hashes, but cannot prove precision or
publisher provenance. Save its manifest digest separately from the phone bundle.
First phone location: `Application Support/BreezeASR25/breeze-asr25-pal8-v1`.
Do not overwrite that directory with changed weights during a qualification run.

## A2. Apply the prepared probe integration

Execution update: this guarded integration is now applied and native-built. The
App actor is the single maintained source; the duplicate Tools candidate and
installer are removed. See [the result](breeze-native-result-20260920.md). The
commands and blob pin below preserve the original preparation procedure.

Run `install_breeze_probe.py` without `--apply`, inspect the diff, then apply it.
It requires engine blob `2162ca8d88a5dda8a51487ddd585e4129a6474b3`; an updated engine
requires a narrow manual rebase, not resetting user work or disabling the guard.
Use the repository's project generator to register `App/BreezeEnglishRecognizer.swift`.
Review generated changes; preserve signing and all dependency pins.

The patch adds one enum case and actor reference, one preparation branch, and
one final transcription branch. Existing capture, resampler tail, 30-second limit,
UI timings and generation checks remain. `prepareConversation()` still selects
PhoWhisper: **Breeze is a probe, not a changed Talk default**. Check all exhaustive
switches and the existing ASR probe picker in the native build.

The candidate independently loads Breeze's lexical BPE and validates zh/en and
large-v2 control IDs. It reuses the existing `PhoWhisperTokenizer(base:)` wrapper
only for those control IDs; it never calls that type's PhoWhisper-specific loader.
No word timestamps are requested. It uses the existing VAD implementation and
whole-turn thresholds; unavailable VAD permits ASR instead of inventing silence.
The newer `cfa0999` PhoWhisper silence-compaction path remains untouched. The first
Breeze probe deliberately keeps the entire accepted waveform, so model and trimming
changes are not evaluated together. Distinguish VAD rejection from decoder errors,
especially for short answers; the existing gate requires three strong windows. No script
conversion, translation, expected-answer prompt or cross-turn text is injected.

One task retains the actor until native work returns. Cancel stops accepting
results; it must not unload memory beneath native inference. Check the existing
memory-warning latch on the actual probe build. A warning/crash is a stop signal,
not permission to clear caches, reset the latch or keep retrying unchanged graphs.
Missing or mismatched Breeze assets fail explicitly with no network fallback.
The `--breeze-manifest-sha256=...` pin is development-only; do not ship an unpinned
user-selectable model loader.

## A3. Qualify on the user's physical iPhone 17s

Start with one device and 3–10-second turns. Record source/build/model identities,
OS/build number, actual device model, preparation time, first-turn time and warm
Send-to-final p50/p90. Keep model-only decode wall time distinct from UI latency.
Measure memory warnings and peak footprint with native instrumentation; phase
samples and process-lifetime RSS are not model-only peak RAM. Simulator speed is
not phone evidence. Report each phone separately before aggregating results.

Use the Taiwan template for an initial 16-clip smoke. Review both switch directions,
English inserted mid-sentence, multiple switches, all-English speech, Traditional
characters, names, hesitation, short answers and silence. Add unseen spontaneous
speech and native Taiwan Mandarin speakers before claiming general coverage.
Repeat after offline restart with assets installed. Exercise End during preparation
and decoding, immediate attempted restart, interruptions/backgrounding, and at least
20 consecutive warm turns. No stale transcript, overlapping native owner, memory
warning, termination or silent network use is acceptable in this bounded trial.

A pronunciation/English-preservation error must remain visible even with a low
aggregate MER. Agree whether measured latency is usable with the user; this plan
makes no invented iPhone latency promise. If PAL8 memory or latency is inadequate,
stop and report. Only then consider porting the *Breeze weights* through the existing
staged Core AI encoder path with new manifests/AOT/cache identities. Do not reuse
PhoWhisper AOT binaries, relax h18p guards or start another compression ladder.

## Later product change — after acceptance, not bundled with this probe

Route an explicit Taiwan Mandarin learning selection to Breeze for the whole turn,
never from IP location, script detection or individual English words. Add the
selection at the existing coordinator/preparation boundary; do not build a registry.
Keep only one ASR model resident. Replace the diagnostic manifest argument with a
reviewed fixed asset pin and remove the duplicate Tools candidate after integration
has a single maintained App source. Keep script formatting separate from the raw
transcript. A Taiwan teaching/TTS module is a distinct requirement, not something
this ASR probe silently implements. Commit the native-tested integration and its
sanitized phone result separately from this preparation work.
