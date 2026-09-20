# FireRedASR2-AED qualification

## Current result: implemented, stopped on live memory warning

2026-09-20. **Not qualified for production or further blind retries.** The exact
v2 AED file probe passed first; only then was the opt-in recognizer actor added
through the existing audio owner. Live testing completed seven submissions, then
iOS delivered a memory warning while the recognizer was loaded but idle. The
warning latch stopped/released it and prevented preparation in that process.
Testing stopped as required. The ordinary Mural build was restored in place;
Breeze, PhoWhisper, asset caches, learning data and defaults were preserved.

### Memory investigation follow-up

A separately approved, instrumented two-turn run showed stable sampled idle
footprint near 1.57 GB without an observed warning. Capture timing missed the full
planned idle and delayed release logs, so the original pressure cause remains
**inconclusive**. Wider system pressure is possible, not established; Mural is not
exonerated. No allocation fix, model change or Talk promotion. See the
[memory investigation and preserved evidence](firered-memory-investigation-20260920.md).
The original qualification identities below remain historical and unchanged.

### Tested implementation and identities

- Source: `737a29e7a3b3f9f2ff67033573c05d3afb1b832c`, on `mvp` after the preserved
  Breeze checkpoint `1b12b77`. The tested app was built from these exact source
  bytes before committing; later changes to this result are documentation only.
- Explicit variant: `python3 scripts/generate_project.py --firered-file-probe`,
  Release, followed by ordinary project regeneration. Same iPhone 17 / iPhone18,3,
  **iOS 27.2 (24B5084k)** and Xcode 27.0 / SDK 27.0 as the initial file gate.
- Live executable SHA-256:
  `22d2ce6772afec3234cda635102f3b5896f15e6571cafc58673c28398a43d89c`.
- Actor SHA-256:
  `094200743c36c88f7c03f739f5397db5a2a8f12a4baf5c495836b640a75df438`.
- Exact checkpoint/export/runtime pins remain those recorded below and in
  `Tools/ChineseASR/FireRedProbe/pin.json`. They were checked again before live
  preparation. No v1, CTC, LLM or full-system substitution.
- `FireRedEnglishRecognizer`: one actor-held C recognizer; synchronous AED work
  on its executor, CPU/one thread/greedy/batch one. Config C strings live through
  construction. Streams/results use deterministic deferred cleanup; cancellation
  checks after native return cannot free handles during inference. The existing
  audio task retains the actor through cancellation, serializes preparation and
  capture, and rejects stale generations. No additional worker/service/decoder.
- Existing microphone, 48 kHz-to-16 kHz resampler and tail drain, 30-second bound,
  and whole-turn VAD gate reused. FireRed does not trim accepted audio. VAD failure
  remains fail-open, as in the existing probe policy. No recorded audio is retained.
- The selector is compile-time opt-in only. Ordinary builds omit the native
  sources, bridging header, library links and selector. `prepareConversation()`
  still explicitly selects PhoWhisper. Breeze actor, shared VAD thresholds,
  signing files and resolved package pins were unchanged.

### Human observations and accuracy limits

- **Long English replies:** user reports accurate words, including the requested
  name/number phrase, but all-uppercase output. Uppercase English was also
  observed in the maintained sherpa host replay. No case repair or punctuation
  postprocessing was applied. User explicitly deferred a possible separate
  display-only sentence-casing policy; preserve raw output and proper names.
- **Short Yes: failed 2 of 3 attempts, human-reported.** Logs show three blank
  submissions rejected by `firered_vad mode=gate complete=true`, with **no AED
  decoder call** for those turns. One spoken Yes passed. The remaining rejection
  is consistent with the requested silence check, but the user's response did
  not independently map each blank to its exact intent/time. Silence is not a
  fully confirmed acceptance, and rejected speech must not count as fast success.
- **One Mandarin control:** a native Traditional-Chinese user judged the lexical
  content correct except for a Simplified/Traditional distinction: output
  **后 (U+540E)** versus expected **後 (U+5F8C)**. This is a real raw script mismatch,
  consistent with this Mainland-oriented candidate, not a silently normalized
  match. Full utterance and human feedback stay private.
- The shared VAD gate averages the three strongest 4,096-sample windows and
  requires a score of 0.85. That policy can reject brief replies even when the
  recording includes seconds of surrounding quiet. Logs establish where these
  turns were rejected, not their exact probability traces or acoustic cause.
  No waveform was saved for matched replay; no threshold/default change made.
- **No human-reference MER/CER/WER.** No frozen, independently checked matched
  recordings or representative Mainland code-switch corpus exists here. Do not
  score prompt text against unsaved live speech. One Chinese turn and English
  observations do not establish switch-direction, dialect or unseen-speaker
  coverage. Host `evaluate.py` agreement below remains model-to-model only.

### Physical latency and memory

Live preparation: **2.717 s total**, including **0.726 s** asset verification and
**1.990 s** preparation/loading (VAD plus **1.700 s** native constructor).
All following durations are seconds; Send-to-final uses correlated owner turn IDs.
Native decode spans stream creation, waveform frontend, decoder and result copy,
not VAD or UI overhead.

| Submission | Captured audio | VAD outcome | Send-to-final | Native decode |
|---|---:|---|---:|---:|
| First English phrase | 4.4 | Accepted | 1.146 | 1.078 |
| Blank 1 | 2.3 | Rejected | 0.032 | Not called |
| Successful Yes | 2.3 | Accepted | 0.519 | 0.496 |
| English name/number phrase | 5.9 | Accepted | 1.493 | 1.457 |
| Blank 2 | 2.8 | Rejected | 0.030 | Not called |
| Blank 3 | 3.4 | Rejected | 0.035 | Not called |
| Mandarin control | 7.7 | Accepted | 2.056 | 1.937 |

For the **three nonempty post-first turns only**, Send-to-final p50 **1.493 s**,
p90 **1.944 s**, linear interpolation at `(n-1)*p`. Very small mixed-duration
sample, excluding rejected turns; **not** a 20-turn or steady-state distribution.
Preparation and first-turn values each have one live observation, not percentiles.

- Kernel process-lifetime peak footprint: **1,507,396,936 B**.
- Process-lifetime RSS peak: **1,563,279,360 B**.
- At the warning: approximately **1,492,454,728 B** current footprint.
- Immediately after native recognizer destruction: **391,711,688 B**. This sample
  precedes automatic release of the actor's remaining Swift properties; it is not
  a final whole-app baseline or proof of leak freedom.
- Logged thermal states were **nominal**, including at the warning. No crash or
  termination occurred during the observed batch. No sustained/battery test.

### Hard stop and lifecycle result

At **10:43:05 local device-log time**, UIKit logged **one memory-warning event**,
about 338 seconds after native preparation and 137 seconds after the last decode.
Both existing audio-owner instances observed the same process notification: the
idle main Talk owner (selected PhoWhisper but unprepared) and the FireRed probe
owner. Their two handler logs are **not two independent iOS warnings**, and the
main owner's selected-model label is not evidence of loaded PhoWhisper weights.
Only FireRed preparation/inference occurred in this live process.

The FireRed owner was Ready, with no native operation in flight. It stopped,
released the recognizer and entered Speech unavailable; the screenshot confirms
the visible memory-warning error. There was no automatic retry or fallback.
This is **observed idle memory-warning cleanup**, not a passed in-flight
cancellation/interruption test. Root cause of the system pressure is unknown;
process footprint alone does not establish an isolated FireRed allocation limit.
The generic stop notice still mentions preparing again, but the warning latch
prevents it; do not follow restart wording to retry this qualification failure.

| Remaining requested check | Result |
|---|---|
| At least 20 warm turns | **Not run: resource stop after seven submissions** |
| Near-30-second continuous speech | Not run |
| Offline restart/reload | Not run |
| End/Stop during native preparation or decode, immediate restart while draining | Not run |
| Background/foreground and external interruptions | Not qualified |
| Matched mixed Mandarin/English, both directions, monolingual controls, noise | Incomplete; corpus and device gates remain |
| English preservation over a representative corpus / script-error rate | Unqualified |
| Other physical devices or OS releases | Not tested |

### Validation and cleanup

- Both opted-in and ordinary Release builds passed, with no new source warning.
  Existing interruption deprecation, async-alternative and AppIntents warnings remain.
- ChineseASR **47 tests passed**; Swift core **86 passed**. Two old source-string
  assertions were updated for the added owner argument and equivalent repair
  policy switch; two additional AED ownership/source contracts passed.
- Existing CoreAI discovery: **129 unittest cases passed** plus executable
  contracts; one compression import failed because the split-export environment
  lacks `coreai_opt`. The same retained compression test then **passed separately**
  in the dedicated installed compression-capable environment. No package install
  or production compression change. Failed run retained, not relabeled a full pass.
- Ordinary signed app restored in place, SHA-256
  `d28e55d04bfae778e0c674fbc00124882ba08a2285cbb8868d403618cbb53584`.
  Fresh normal launch and screenshot confirmed the idle Talk UI and unchanged
  default backend log. No FireRed or baseline-ASR inference was retried afterward.
- No app uninstall, model/cache/store deletion, signing change, push or upload.
  The isolated FireRed staged files remain on the phone; normal Mural ignores them.
  All owned captures stopped; Device Hub closed before microphone testing.
- Reviewed source and this sanitized result are committed. Private logs, raw
  feedback/transcripts, screenshots, source/build hashes and reports remain under
  `.build/verification/firered-device-20260920/`. Microphone WAVs were not retained.

## Physical file gate passed, 2026-09-20

Merged the FireRed work fast-forward onto completed Breeze checkpoint `1b12b77`
in `mvp`, preserving all existing changes. Initial standalone installation was
blocked by the free-development-profile three-app limit. At the user's request,
added a compile-time-only file-probe entry inside the existing Mural installation.
No app uninstall, data reset, live-capture integration or default-model change.
Normal project generation omits all FireRed native sources, bridge and runtime
links. The special launch bypasses LearningStore and normal audio/model startup.

- Device: physical **iPhone 17 / iPhone18,3, iOS 27.2 (24B5084k)**.
- Release source snapshot: `d6c0287` (built from `e6beb35` plus that reviewed change);
  `Probe.mm` SHA-256 `41bb4f53e05c3cc07cd8ee20dc07a2da0acf55127d816b8d0616c3857905b7a2`.
- Tested signed executable SHA-256:
  `8664ecc159a1e2db134b940d67cf711034fea058711d0758f88b5a3a6dde6239`.
- Exact model/runtime pins below verified on the phone. CPU, one thread, greedy,
  batch one. Upstream 5.1-second example 1, no independent human reference.
- **PASS:** six identical nonempty outputs, exact raw match to the Mac INT8 output;
  two recognizer creations/destructions and six result/stream cleanups completed.
- Verification **0.811 s**; model preparation **2.003 / 1.749 s**.
- Cycle 1 decode **1.592 / 1.508 / 1.520 s**; cycle 2
  **1.580 / 1.516 / 1.582 s**. Includes stream/frontend/result copy, not live
  Send-to-final. These six repeats are not a speech latency distribution.
- Kernel lifetime peak footprint **1,517,849,760 B**; lifetime RSS peak
  **1,547,059,200 B**. Before load **18,794,288 B**, after first recognizer release
  **364,268,368 B**, after second/final cleanup **30,051,008 B**. These are process
  metrics, not isolated model memory or a proof of leak freedom.
- **Zero recorded memory warnings**, nominal thermal state at every checkpoint,
  no crash during the completed run. UI screenshot confirms completed replay,
  readable raw text and disabled run/stop controls.
- Embedded and ordinary Release builds passed. Ordinary generated-project check
  confirms no FireRed native links/flags. Signing and resolved-package hashes
  unchanged. ChineseASR **45** and Swift core **86** tests passed again.
- Private reports, screenshot, scoped app logs, source diff/hashes and signed apps
  retained under `.build/verification/firered-device-20260920/`. Owned capture
  stopped. No device-wide archive or recording/transcript publication.

This passed only the initial resource gate. It permitted the actor implementation
and live trial above; that later trial hit the memory-warning stop. The historical
Mac preparation below is retained as evidence, not current physical status.

## Historical Mac preparation, before phone handoff

Date: 2026-09-20. **Not an iPhone qualification or an accuracy acceptance.**
The user requested finishing Mac preparation and waiting for an exclusive phone
handoff. No probe installation, model transfer, launch, or inference on the
physical phone was performed. The user has no Mainland Chinese recordings and
does not speak Chinese; suitable public code-switching audio and independent
transcript review are a later work item, not a passed gate.

## Source and isolation

- Repository: `aidynamicsolutions/mural`.
- Preserved `mvp` checkpoint: `cf5221f027fb6575cb58dcd25788070c8b35ce6c`.
- Separate worktree/branch: `mural-firered`, `firered-aed-probe`.
- Tested native source snapshot: `7d8f105557aa4e8c370a8be5c32d4b86e95017ba`.
  The signed build was produced from exactly these source bytes before committing.
- Native source SHA-256 (`Probe.mm`):
  `f897dec657a3573564605120192b443a2a292cc09bce06709f4c13a1dd3a279b`.
- Signed Release executable SHA-256:
  `05ac28b67614fc9c99daa8b534cbd01ce1c6f28b674184b885243d3b4e0cadb9`.
- Separate development app; Mural source/project/defaults, WhisperKit/FluidAudio
  pins, assets, signing configuration, and learning data are unchanged by this
  branch. Concurrent Breeze edits remain in the original checkout. No merge into
  that active checkout and no push.

The implementation is a 298-line Objective-C++/UIKit file probe calling the
maintained C API, not a custom decoder or a product recognizer. A single serial
worker owns all C handles; RAII releases results/streams/recognizers after native
work returns. Inactivity, Stop, memory warning and serious thermal state prevent
further work. It verifies fixed local model hashes and input WAV format, retains
atomic private checkpoints, and plans two owner lifetimes with three identical
file replays each. Source review/static analysis do not establish phone lifecycle
correctness. `FireRedEnglishRecognizer` and live capture are deliberately **not
implemented** before the physical gate.

Build/replay instructions and the runnable post-device acceptance check:
[`Tools/ChineseASR/FireRedProbe/README.md`](../../../Tools/ChineseASR/FireRedProbe/README.md).

## Exact model/export/runtime identities

| Item | Inspected identity |
|---|---|
| Official checkpoint | `FireRedTeam/FireRedASR2-AED`, HF revision `2304afed56eacfee6256dee5937ed22ffa0b64ec` |
| Official checkpoint SHA-256 | `4677cbd30988d63ed3e777f6a42a1e5260a3865317f6e15e488bef40954f7054`; 4,731,558,506 bytes, verified against HF LFS metadata |
| Official inference source | `FireRedTeam/FireRedASR2S`, `4e7d9aaf4482a47cec1724807026b9b151926eb5`; only `FireRedAsr2.from_pretrained("aed", ...)` instantiated |
| Conversion recipe | `csukuangfj/FireRedASR2S`, `5febe49b840d976a52aaa8e50d5f49df14e550e8`, `export_aed_onnx.py` |
| Released export | `sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26.tar.bz2`; SHA-256 `43015b3f1643a5688b4821e8ed323473d38b798c4ec291471fe00df1bcfc4f1c`, matched GitHub asset digest |
| Maintained runtime | sherpa-onnx `a5b4a944c5186a68bcdc0ac3011e4c541781ac84`, version 1.13.8; source-built for host Python and iOS C API |
| ONNX Runtime | 1.28.2; maintained static iOS archive SHA-256 `2c2299acbb461d26d4bac4bc85985d40e7c7177ed6072703ae0846d88b0b4599`, matched release digest |

Every runtime model file is pinned by size/SHA-256 in
[`pin.json`](../../../Tools/ChineseASR/FireRedProbe/pin.json). Total model files:
**1,234,657,933 bytes**. ONNX inspection used `load_external_data=False` and found
**zero external tensor files** in both INT8 graphs; no `.weights` sidecars are
required for these particular released graphs. The recipe's unquantized export
uses external weights, which must not be confused with this package.

Direct inspection established:

- Encoder metadata: `model_type=fire-red-asr-aed`, `version=2`, author FireRedTeam,
  explicit `FireRedASR2-AED` comment and official v2 URLs. ONNX opset 17.
- Real encoder/attention-decoder pair: cross-K/V outputs, 16 decoder layers,
  20 heads, head dimension 64, 8,667 logits, SOS 3/EOS 4, max length 1,024.
- Dynamic self-K/V cache length in the actual decoder graph. Matched runtime
  `InitDecoder` distinguishes fixed v1 from dynamic v2; the maintained greedy
  decoder calls `GetInitialSelfKVCache(cache_len)` with estimated need.
- Official dictionary is byte-for-byte identical to export tokens. Embedded
  80-bin CMVN means/inverse standard deviations match the official frontend
  constants as float32. The maintained frontend receives waveform samples and
  applies its own scaling/fbank/CMVN, not Whisper features.
- Both graphs contain quantized operators. CPU execution, one inference thread,
  greedy search, batch 1, no correction FSTs/homophone replacement. No ANE or
  Core ML placement claim; a linked system CoreML framework is not evidence of use.

**Provenance limit:** the recipe commit postdates the model package upload on the
same day. The release does not attest an exact producer-build commit. This run
inspected the maintained recipe and released metadata and compared with the
pinned official checkpoint; it did not reproduce the export byte-for-byte.
The package is verified as the v2 AED artifact, not the 2025 v1 example, CTC-only,
LLM, or entire ASR2S pipeline. Numerical/export accuracy retention is not proven.

Licenses/notices are recorded in
[`NOTICES.md`](../../../Tools/ChineseASR/FireRedProbe/NOTICES.md). Official weights
explicitly declare Apache-2.0 in their model card. The ONNX package itself lacks a
separate license file; preserve upstream model/conversion attribution and resolve
redistribution packaging before shipping. No audio/model binaries are published.

## Host observations, not iPhone measurements

Host: Apple M1 Pro, 16 GiB RAM, macOS 26.6.2 (25G83).
Toolchain: Xcode 27.0 (27A5252f), iOS SDK 27.0 (24A5422a), Apple Swift 6.4,
CMake 3.29.0, XcodeGen 2.46.0. Isolated replay Python 3.11.11, torch/torchaudio
2.11.0, ONNX 1.20.1, source-built sherpa 1.13.8 with ORT 1.28.2.

Four bundled upstream examples were run through `run_reference.py firered-onnx`
and separately through official v2 AED PyTorch on the **same files**. No private
recordings existed or were uploaded. Manifest references are explicitly marked
unreviewed runtime fixtures, not human ground truth. No accent/demographic claims.

Official comparison: CPU FP32, one thread, beam 1, softmax smoothing 1,
length penalty 0, EOS penalty 1. These are a bounded greedy comparison, not the
publisher's default beam-search benchmark. Only one checkpoint was resident per
reference process. Host processes overlapped with other work, so these are
observations, not a controlled performance benchmark.

| Observation | Official PyTorch, Mac | Released INT8 AED, Mac |
|---|---:|---:|
| Preparation, one observation | 48.673 s | 2.686 s |
| Example 0, 10.053 s audio | 18.071 s | 4.803 s |
| Example 1, 5.100 s audio | 5.204 s | 2.734 s |
| Example 2, 4.690 s audio | 7.334 s | 1.974 s |
| Example 3, 8.830 s audio | 8.157 s | 4.204 s |
| Process peak RSS | 4,690,821,120 bytes | Not instrumented |

Model-to-model agreement using `evaluate.py`, **not recognition accuracy**:

- Raw exact matches: **0/4**. Official API lowercases English; sherpa preserves
  uppercase English tokens. This script/case behavior is not hidden.
- Casefold-only matches: **3/4**.
- One clip additionally ends with **去** (U+53BB) in ONNX and not in the official
  result. Without independent speech annotation, neither result is designated
  correct. Exact parity failed; do not claim lossless INT8 conversion.
- Declared normalized token disagreement: **1/80 = 1.25%**, three normalized
  matches. This number uses model output as the reference and must **never** be
  presented as human-reference MER/CER/WER or Mainland code-switch accuracy.
- Raw detailed outputs are retained locally and are not committed.

## Build and regression gates

| Check | Actual result |
|---|---|
| ChineseASR standard-library suite | 45 passed |
| Existing Swift core suite | 86 passed, zero failures |
| Existing CoreAI Python suite in base Python | 124 attempted; 3 import failures, 2 skipped; Torch absent and stale mel-reader extraction |
| CoreAI suite in isolated replay environment with Torch | 131 attempted; 129 passed, 2 import failures: unavailable Core AI Python module and the same pre-existing mel-reader extraction |
| Pinned sherpa iOS C API | Release arm64 build passed; final deployment target iOS 17.0 |
| Standalone native probe | Signed Release build and signature verification passed |
| Clang static analyzer | Final pass, no source issues; initial hash-loop/pin-nullability findings corrected |
| Dependency diagnostics | ORT headers emit documentation/quoted-include warnings; no probe-source warnings. Upstream iOS 13 libc++ warning resolved by building for 17.0 |
| Mural unused/default path | Source/project/package pins unchanged; no new full Mural build or default-path device run claimed |

The stale existing `test_mel_reader.py` extracts a forwarding function without its
owner. The concurrent Breeze checkout already has a narrow correction in progress;
this branch did not duplicate or overwrite that work. Core AI compression tests
need the existing dedicated export environment, not a sherpa dependency change.
Neither unrelated baseline failure is labeled passed.

Retained preparation failures: unsupported no-TTS **Python** build imported a
missing `GenerationConfig`; rebuilding the same pinned source with supported
TTS-enabled Python configuration resolved it. iOS C API remains no-TTS. Initial
new-bundle provisioning and XcodeGen project-root issues were corrected without
changing Mural or runtime APIs. Failed logs remain local. No runtime fallback.

## Physical results and remaining gates

| Requested physical measurement/check | Status |
|---|---|
| Exact pinned AED loading/output on iPhone 17 | **Not run: awaiting phone handoff** |
| Repeated execution, handle cleanup and reload | Not run; native probe prepared |
| Preparation / first / warm latency | Not measured on phone |
| Live Send-to-final p50/p90 | Not measured; no live integration |
| Peak footprint, warnings, thermal state | Not measured on phone; never infer from Mac RSS |
| Recognition accuracy / English preservation / script review | Blocked on independently transcribed suitable speech and bilingual review |
| Mandarin/English controls, both switch directions, short replies, names/numbers | Unqualified; upstream examples do not cover this matrix |
| Silence/noise, near-30-second speech, 20 warm turns | Not run |
| Offline restart, interruption/background, End/restart during native work | Not run |
| Actor/live-capture integration | Deliberately gated on physical probe success |

Next step: obtain the user's exclusive iPhone handoff, install only the standalone
probe, transfer the pinned three model files and upstream 5.1-second WAV, and
collect the first physical report. Review readable output, warning/crash state,
peak/current footprint, preparation/replay costs and post-cleanup behavior before
implementing the small actor through Mural's existing audio owner. Any identity
uncertainty, native/API failure, memory warning, crash or unusable resources means
stop, retain evidence and report the blocker. No hosted fallback or model switch.

The original Mainland recording script was copied to a private folder but remains
**unrecorded and unreviewed**. Do not ask this user to validate Chinese speech they
do not understand. Research licensed Mainland-accent code-switching material and
arrange independent reference review later. No product locale routing promotion.

Private evidence stays under `.build/verification/firered-aed/` in the FireRed
worktree, including metadata, per-artifact/native-library hashes, reference reports,
model-agreement score, source build logs, analyzer output and executable identity.
No device identifier, personal path, full transcript, audio or model bytes are in
this result. No device/log-capture process was started by this work.
