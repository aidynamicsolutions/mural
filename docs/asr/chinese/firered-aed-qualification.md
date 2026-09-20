# FireRedASR2-AED: Mac preparation complete, physical gate pending

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
