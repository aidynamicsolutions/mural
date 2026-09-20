# Breeze native conversion and bounded iPhone smoke

**Result: implemented, native-built, installed, and partially phone-qualified. Not
approved as the production recognizer.** The user reduced the requested 20-turn
soak to five turns and explicitly deferred the remaining offline/lifecycle checks.
No FireRed implementation or production recognizer change.

## Tested identities

- Repository/branch: `aidynamicsolutions/mural`, `mvp`. Started clean at
  `cf5221f027fb6575cb58dcd25788070c8b35ce6c`; fetch and fast-forward-only sync found
  local and remote equal. No reset, stash, discarded changes, or force push.
- Tested app source: `e44c5c3a9370d7834ecf63107a0db1c877d1ce28`.
  Release executable SHA-256:
  `bd63fbb8c6865fbe2a730950619d81503386f59bbf0c0c6557e436b61f9dafe5`.
  Source remained unchanged throughout phone testing; subsequent changes are docs.
- macOS 26.6.2 (25G83), Apple Silicon, 16 GiB RAM; Xcode 27.0 (27A5252f),
  iOS 27.0 SDK. One physical **iPhone 17 / iPhone18,3, iOS 27.2 (24B5084k)**,
  USB-connected. Other physical iPhone 17s were not available/tested.
- Official source: `MediaTek-Research/Breeze-ASR-25`, immutable revision
  `cffe7ccb404d025296a00758d0a33468bec3a9d0`.
  `model.safetensors`: 3,086,761,032 bytes, SHA-256
  `c5d952b3bc03ea277209aff0ef5b5c4c055d74449ff794c02d8f4e315fdef6b6`.
  Matching processor, lexical tokenizer, configs, model card and Apache-2.0
  notice retained. No community compiled weights or model-hub upload.
- Export: WhisperKitTools `84f77a83c8f530022ae55fbb1a64b3351ef63c7a`
  (0.4.2), argmaxtools 0.1.23, Python 3.11.14, torch 2.5.0,
  transformers 4.53.0, coremltools 9.0, NumPy 2.3.5, scikit-learn 1.9.1.
  Encoder SDPA `SplitHeadsQ`, decoder `Cat`; 448-slot decoder cache.
- One phone candidate: `breeze-asr25-pal8-v1`, k-means PAL8,
  per-grouped-channel/group-16, threshold 2048, four clustering workers.
  FP16 frontend and residual weights retained. PAL8 is not FP8.
  Packaged with the supplied `prepare_breeze.py`; runtime inventory totals
  **1,657,744,068 bytes**, excluding manifest and runtime caches.
  Independently recorded and phone-read-back manifest SHA-256:
  `64021fb776ee2ef4cf02c05b2a9dafde0e0700e9bf7d967b4bc5302558b5fdb4`.
- Runtime pins unchanged: WhisperKit 1.1.0
  (`1e2a163736dfa5a198e637ae44c114e1c6d5cc2d`), FluidAudio 0.15.7
  (`41540ea237350afe5117a082b5c28eda642d0612`), swift-argument-parser 1.8.2
  (`6a52f3251125d74daf04fcbd5e6f08a75d074382`), WebRTC 152.0.0
  (`1d04692697cb642bfebf6ad2dd99fe52649c3d6d`).

## Implementation and host results

- **PASS:** reviewed the guarded installer dry run, applied against engine blob
  `2162ca8d88a5dda8a51487ddd585e4129a6474b3`, then used
  `scripts/generate_project.py`. Generated changes were only the new Swift file
  reference/build entry and group/source-phase registration. Signing and resolved
  package file hashes remained unchanged. In-place install preserved the existing
  development bundle, stores, models and caches.
- **PASS:** default `prepareConversation()` still selects PhoWhisper FP8/PAL8;
  its silence-compaction branch, asset identities and warning latch are unchanged.
  Breeze uses the existing task/audio owner and generation checks. Native build
  covers exhaustive switches; the existing picker includes Breeze and does not
  offer it download repair. The App actor is the single maintained implementation;
  the duplicate Tools candidate and installer were removed after integration.
- **PASS:** 45 Chinese-ASR helper/source-contract tests, 86 Swift Core tests,
  and 129 ASR/CoreAI unittest cases plus their imported executable contracts.
  Initial broad run failed because the default Python lacked torch and the mel
  test still extracted an obsolete forwarding method. Corrected the test to
  exercise the current shared reader; reran using the retained native tools
  environment. No production mel implementation was changed.
- **PASS:** Release build, install and launch. No opt-in flags were required for
  normal FP8/PAL8 Talk. Existing LiveTransport async, audio-interruption deprecation
  and missing-AppIntents warnings remain; no new Breeze compiler warning observed.
- **PASS, numerical only:** FP16 decoder PyTorch/Core ML PSNR 52.4 dB and encoder
  58.5 dB; decoder Torch/Torch argmax matched. The initial export command timed out
  at 1800 seconds during optional encoder compute-plan extraction, after encoder
  inference and compiled output. Preserved those artifacts. Resumed only missing
  support work with package retention and without compute-plan extraction:
  two decoder tests and one 80-mel frontend test passed; frontend PSNR 69.4 dB.
- **PASS:** actual PAL8 inspection found 194 encoder and 321 decoder LUT ops,
  256-entry FP16 palettes and UINT8 indices. Core ML compilation passed. Compiled
  contracts: frontend `[480000] -> [1,80,1,3000]`, encoder output
  `[1,1280,1,1500]`, decoder logits `[1,1,51865]`; FP16 tensor I/O, Int32 token
  and cache-position inputs. A local inspection assertion initially used Python's
  internal type class name; fixed to the library's builtin type mapping and
  re-inspected the saved encoder without recompressing it.
- **PASS, synthetic tensors only:** one deterministic PAL8-versus-FP16 host check
  per component, CPU_AND_GPU, finite outputs and matching shapes. Encoder PSNR
  58.65 dB (max absolute difference 17.21 on synthetic random features); decoder
  logits 76.20 dB with matching argmax; cache/alignment outputs exceeded 35 dB.
  These are not speech/transcript equivalence tests or phone compute-placement proof.
- **FAILED raw-model silence:** supplied `check-audio`, `run_reference.py breeze`
  and `score` completed on one explicitly synthetic three-second zero-PCM WAV.
  Raw PyTorch returned one non-whitespace character: silence_nonempty 1/1,
  speech clips 0, MER undefined. The runner used CPU/FP32, greedy transcribe,
  automatic language, cleared forced English prefix, no timestamps, 220 new-token
  budget. Transformers emitted its missing attention-mask warning. This is not a
  real acoustic corpus and is not the app's VAD-gated silence result below.
- **NOT RUN:** matched human-reference PyTorch/FP16/PAL8 speech replay and MER.
  The user initially had no Chinese recordings/references and requested that
  corpus sourcing be deferred. The authored 16-clip template was copied privately,
  not treated as ground truth. No development replay caller was added without
  a usable matched corpus.

Breeze runtime settings: CPU_AND_NE permission for encoder/decoder, prewarm then
load, automatic-language transcription, sample limit 220, no temperature fallback,
no timestamps/expected-answer prompt, source suppression tokens. The existing VAD
whole-turn gate runs without trimming Breeze's accepted waveform. No script
conversion, translation, grammar repair, or production audio retention was added.
WhisperKit and Transformers heuristics still differ; no exact parity claim.

## Physical results

| Check | Result |
|---|---|
| Missing manifest launch pin | **PASS fail-closed.** User force-closed/reopened after pinned launch; preparation refused before model loading. Relaunched with the same pin, no guard bypass. |
| First verified preparation | **PASS**, 154.863 s including 0.985 s asset verification. Slow first preparation remains a UX limitation. |
| Fresh-process cached preparation | **PASS**, 5.019 s and 4.303 s with retained caches. Not a cold-cache distribution. |
| Two ordinary English turns | **PASS, human-confirmed accuracy**, correlated finalization logs. |
| 3.5-second quiet recording | **PASS**, VAD rejected, zero transcript characters, no decoder call, Send-to-final 0.031 s. Not universal noise/silence acceptance. |
| Five consecutive spoken turns | **PASS bounded completion**, user-confirmed generally accurate. Replaces, not satisfies, the requested 20-warm-turn soak. |
| Yes / No | **PASS human-confirmed** with 2.3 s / 1.5 s captured audio. **Subsecond capture not tested.** |
| Near-30-second continuous speech | **PASS cap**, exactly 480,000 samples / 30.0 s and automatic Send. User had not finished speaking at the cap; later unsampled words are not decoder loss. |
| Live Taiwan Mandarin/English mix | **One human-confirmed match**, including English-to-Chinese and Chinese-to-English switches. User supplied spoken/displayed text after the trial. No saved waveform, pre-frozen reference, matched replay or captured timing for this extra turn. Not a corpus score. |
| Stop after completed work | **PASS, human-confirmed**. Not proof of cancellation during preparation/decoding. |
| Memory/thermal during captured work | Zero recorded warning events; first preparation thermal state fair, subsequent batches nominal. No crash or stale-result report in the completed batches. |
| Offline restart, Stop/End during preparation or decoding, immediate restart while draining, interruptions/backgrounding | **DEFERRED by user**, not passed. |
| Twenty warm turns, other phones, Taiwan names/vocabulary coverage, unseen-speaker/script-error corpus | **NOT RUN**. |

### Measured intervals and resources

All times are seconds. UI Send-to-final is correlated by the existing turn IDs.
Decode wall time is WhisperKit `transcribe` only, excluding VAD/capture/UI overhead;
it is not native decoder-only execution.

| Fresh process / turn | Captured audio | Send-to-final | Decode wall |
|---|---:|---:|---:|
| First spoken batch: first | 4.1 | 2.335 | 2.258 |
| First spoken batch: warm | 6.5 | 1.100 | 1.053 |
| Five-turn batch: first | 2.3 | 0.810 | 0.775 |
| Five-turn batch: warm 1 | 1.5 | 0.691 | 0.671 |
| Five-turn batch: warm 2 | 5.3 | 1.424 | 1.384 |
| Five-turn batch: warm 3 | 5.7 | 1.376 | 1.331 |
| Five-turn batch: warm 4 / cap | 30.0 | 4.428 | 4.351 |

For the four post-first turns in the five-turn process: Send-to-final p50 **1.400**,
p90 **3.527**, using linear interpolation at `(n-1)*p`. Tiny, mixed-duration sample;
not a steady-state performance distribution or 20-turn qualification.

| Process | Highest logged phase footprint | Kernel process-lifetime peak footprint | Process-lifetime RSS peak |
|---|---:|---:|---:|
| Initial preparation | 2,046,134,520 B | 2,048,477,432 B | 1,152,204,800 B |
| First spoken batch | 1,952,418,016 B | 1,953,794,272 B | 330,809,344 B |
| Five-turn batch | 1,950,173,456 B | 2,029,242,640 B | 522,977,280 B |

Footprint peak comes from native `task_vm_info.ledger_phys_footprint_peak`, read
by the content-free memory logger. Phase samples, lifetime physical-footprint
peak and lifetime RSS peak are different metrics. None isolates model-only RAM;
no battery or sustained thermal qualification was performed.

## Known issues and boundaries

- **Deferred formatting defect:** the long English result omitted spaces after
  sentence-ending periods. User requested recording this for later work, not
  altering raw recognition now. Any future display formatting should preserve raw
  ASR and be tested for mixed scripts, abbreviations and punctuation.
- The displayed long result also contains a possible singular/plural mismatch
  against the authored prompt. No retained audio exists to determine what was
  actually spoken, so do not claim exact prompt accuracy or compute WER from it.
- Chinese lexical accuracy, Traditional-versus-Simplified error rates, English
  preservation across a representative corpus, and conversion agreement remain
  unqualified despite the one human-confirmed mixed turn.
- No cache/model/store/history deletion, failed-graph retry after a memory warning,
  cloud fallback, paid job, upload, or FireRed implementation occurred. PhoWhisper
  FP8/PAL8 and its newer VAD trimming remain the normal Talk path.

Full logs, model artifacts, private human feedback and environment locks stay local
under `.build/verification/breeze-qualification/` and the private conversion work
directory. No microphone recordings were retained by the app. All owned captures
are stopped; the app and staged assets remain installed. This report contains no
recordings, full transcripts/logs, personal paths, or device identifiers.
