# Plan B — FireRedASR2-AED for Mainland Mandarin + English

## Decision and scope

Run this after the Breeze checkpoint, as a separate change. The first question is
whether the exact v2 **AED** model is useful on the physical iPhone 17 within the
app's memory and turn-latency budget. Prove that before adding it to Talk.
Do not add a server or assume that a desktop speed figure proves mobile suitability.

The maintained sherpa-onnx source includes logic for FireRedASR2's dynamic decoder
cache. That supplies a more pragmatic investigation route than a custom Core ML
port, but is **not an iPhone 17 qualification result**. The first implementation
should use its existing C API/Swift example patterns, not a new beam-search decoder.

Sources:
[official FireRedASR2S](https://github.com/FireRedTeam/FireRedASR2S),
[sherpa v2 cache handling at the inspected revision](https://github.com/k2-fsa/sherpa-onnx/blob/a5b4a944c5186a68bcdc0ac3011e4c541781ac84/sherpa-onnx/csrc/offline-fire-red-asr-model.cc),
[AED API example](https://github.com/k2-fsa/sherpa-onnx/blob/a5b4a944c5186a68bcdc0ac3011e4c541781ac84/python-api-examples/offline-fire-red-asr-decode-files.py),
[sherpa platform documentation](https://k2-fsa.github.io/sherpa/onnx/index.html).

## B1. Verify identity and the maintained runtime

Pin the official FireRedASR2-AED checkpoint, conversion source, ONNX export and a
sherpa revision containing v2 AED cache support. Keep source/export/runtime identities
separate. Confirm redistribution notices for weights, sherpa and ONNX Runtime.
Do not assume a GitHub code license automatically describes every model artifact.

Reject these tempting substitutions: the older FireRedASR v1 AED package from 2025,
FireRedASR2's CTC-only export, the LLM variant, or the complete FireRedASR2S pipeline.
The upstream example names an older v1 download even though its AED API is useful.
An `encoder.int8.onnx` filename alone does not prove model generation or accuracy.

Start with the maintained v2 AED INT8 encoder, decoder, tokens and any external
weight-data files. Verify that its frontend normalization and decoder metadata are
handled by the matched runtime. Hash every required artifact. Do not reuse Whisper
mel features, tokenizer IDs, vocabulary, cache layout or PhoWhisper model assets.
Record batch=1 and the chosen decoding settings; do not sweep many runtime variants.

Use `run_reference.py firered-onnx` on a few short Mainland Mandarin/English clips,
then the fixed local corpus. It invokes `OfflineRecognizer.from_fire_red_asr`, not
`from_fire_red_asr_ctc`. Its output is a **converted-model baseline**, not agreement
with official PyTorch. Compare a small matched sample against the official v2 AED
implementation separately before claiming export parity or INT8 accuracy retention.
The helper does not download weights or prove their identity for you.

## B2. One bounded native phone probe

Build the pinned sherpa iOS library/XCFramework using its maintained build method
and the local Xcode toolchain. Add this dependency only in this FireRed phase; do
not upgrade existing Mural dependencies along the way. Resolve the exact available
Swift/C API from the built headers and examples. Do not invent a wrapper signature.
Start with the supported CPU execution provider. Do not claim ANE acceleration
because the host framework is ONNX Runtime or because Core ML exists on the device.

Before adding live capture, replay one local 3–10-second WAV in a small native
probe with only FireRed resident. Confirm readable output, repeated invocation,
resource release and memory behavior. No proof of v2 identity, failed native build,
unsupported external-data loading, a memory warning, termination, or obviously
unusable latency means stop and produce a concrete blocker. Do not silently switch
to CTC or a remote service to make the demonstration work.

If the file probe passes, add `FireRedEnglishRecognizer` using the same limited
pattern as the existing `VietnameseEnglishRecognizer`: `prepare`, `transcribe`,
one native recognizer owner, and no concurrent inference. Reuse Mural's capture,
16 kHz mono audio, resampler drain, 30-second bound, VAD policy and generation checks.
Pass waveform samples to sherpa's own frontend. Create/destroy each native stream
with deterministic cleanup and release recognizer handles only after native work
returns. Swift task cancellation does not interrupt a synchronous C inference call.
Keep decoding off the UI/audio callback, with one serial owner; no extra service,
queue hierarchy or global model registry is needed.

Add one opt-in probe selector and local verified asset directory. Do not run Breeze,
PhoWhisper and FireRed together, add another detector, punctuation model, speaker
identifier, or enable a production Mainland locale yet. Ensure the app still builds
and runs its current default with this probe unused.

## B3. Physical qualification and a separate product decision

Use the Mainland recording template and unseen spontaneous speech. Check Mandarin,
English, both switch directions, Mainland vocabulary, names, numbers, hesitation,
short answers, silence and noise. Compare on the **same audio**, not different live
utterances. Preserve the actual English words; translation is an error. Report raw
script behavior separately from a future display normalization policy.

Collect per-device preparation, first/warm Send-to-final p50/p90, long-turn behavior,
native peak memory, warnings and temperature state during at least 20 turns. Test
offline restart, End during native inference, attempted restart, interruptions and
backgrounding. No late transcript should reach the tutor/history after cancellation.
The user judges whether the measured latency is acceptable. A single-speaker smoke
is not a Mainland-accent coverage claim, and average Mandarin CER cannot establish
mixed-language accuracy.

Only if accuracy and phone resources justify the extra dependency, connect an
explicit Mainland Mandarin selection at the existing preparation boundary and pin
accepted artifacts. Otherwise leave the current app unchanged and publish the
measured blocker. A hosted FireRed service would introduce a new privacy/operations
boundary and requires its own explicit decision; it is not this plan's fallback.

## Deliverable boundary

This preparation commit includes the plan, recording scripts and a local AED replay
helper. It does **not** include a built iOS runtime, converted weights, a FireRed
Swift bridge or measured iPhone results. Those are real implementation gates, not
work that can truthfully be described as already complete.
