# FireRedASR2-AED memory research handoff

Date: 2026-09-28. Repository: `aidynamicsolutions/mural`, branch **`mvp`**.

**Purpose: research practical reductions in real iPhone memory use, then return a small, evidence-backed implementation/experiment plan to the local agent. Do not run or promote the stopped candidate.** This is a source and sanitized evidence checkpoint, not production qualification.

The commit containing this handoff is the delivery checkpoint. Resolve it with `git log -1 --format=%H -- docs/asr/chinese/firered-memory-research-handoff.md`; record the full SHA in your report. The preceding local checkpoint was `dde6b5ff8e7d94b87b58841cd13baddea7f3f6e3`. No original candidate patch needs reapplying. The retained FireRed worktree is already ancestral to `mvp`, not missing code to merge.

## 1. User priority and non-negotiable behavior

The user reports that native Mandarin speakers found recognition accuracy **pretty good in a brief earlier test**. This is useful human feedback, not a measured corpus score, a matched quantization comparison or long-duration acceptance. Memory reduction and sustainable use are now the primary investigation, not another broad accuracy research project. Preserve that quality: any changed weights, graph or decoding path need a focused, matched accuracy regression before adoption.

Intended product:

- Settings: learning **English**, meaning/support **Simplified Chinese**; normal **Prepare & start**.
- Mandarin, English and mixed speech through **FireRedASR2-AED**; Apple's local English tutor; English speech; Simplified meanings, word lookup and on-screen Help.
- No automatic ASR fallback, transcript/script repair, second language picker, new cloud service or Chinese Help playback. Chinese assessment stays disabled.
- Traditional Chinese stays on Breeze. Vietnamese stays on PhoWhisper, preserving this phone's explicit Core AI Release configuration.
- A successful download is not loaded readiness; a short warning-free run is not proof of sustainable memory use. Do not suppress memory warnings, raise/guess memory limits or attribute pressure to another app without evidence.

## 2. Read first and where the implementation lives

1. `AGENTS.md` and [current qualification plan](simplified-talk-qualification-plan.md), especially its current table and latest dated entries.
2. This entire handoff, [original memory investigation](firered-memory-investigation-20260920.md), [historical qualification](firered-aed-qualification.md) and [candidate product checkpoint](simplified-talk-candidate.md). Historical commands/outcomes are dated, not current authorization.
3. `App/FireRedEnglishRecognizer.swift`: actor-held C recognizer, managed asset verification, VAD, native construction/decode/destruction and diagnostic markers.
4. `App/LocalConversationEngine.swift`: the single audio/task owner, admission, model selection, stop/drain, warning handling and co-resident voice resources. `App/ConversationCoordinator.swift`: real Talk setup/tutor/support, resource-only observer and complete-owner drain.
5. `App/Native/FireRedRuntime.h/.mm`, `scripts/build_firered_runtime.sh`, `scripts/generate_project.py`, `Tools/ChineseASR/FireRedProbe/pin.json` and `NOTICES.md`. The tiny runtime bridge identifies ORT; the maintained sherpa C API owns native inference. The old file probe is separate tooling.
6. `Core/SpeechPackage.swift`, `Core/SpeechPackageCatalog.swift`, `Core/LocalSpeechProvisioning.swift`: trusted managed acquisition and activation, not an alternative model-loading framework.
7. `scripts/verify_device.py`, `scripts/verify_simulator.py` (`stop_group`), `UITests/MuralUITests.swift`; `.agents/skills/verify-mural/SKILL.md` and its `features/local-conversation.md`; [physical lessons](../../physical-iphone-e2e-lessons.md), read completely before proposing runner changes.
8. `CONTEXT.md`, `mvp_plan.md`, [physical plan](../../physical-iphone-e2e-plan.md) and [Core AI checkpoint](../../coreai/gpu-talk-checkpoint.md) for preserved product/backend boundaries.

### What this checkpoint implements

- Reproducible checkout-owned, device-only native runtime build in ignored `.build/firered-runtime`; pinned archive verification and selected upstream notices. Runtime-only `MURAL_FIRERED_RUNTIME` variant is separated from legacy `MURAL_FIRERED_FILE_PROBE` UI. Ordinary builds still refuse FireRed early; no public promotion.
- Exact bundled package metadata plus explicit upstream file mapping through the **existing** installer. Pinned HTTPS origins, narrow signed-CDN redirects, exact ranges, storage checks, cancellation/resumption, full hashes and atomic activation remain enforced. No weights in the app bundle, fake remote manifest or second downloader.
- Talk resolves only the active managed package, rehashes all three artifacts before native loading, and never falls back to the old Documents probe directory.
- Acquisition-only `provision` stage and narrowly reviewed retained-state recovery. A real token redirect defect was fixed: preserve the empty route-echo query item and quoted ETag from the actual upstream response. Both graphs were retained; only the missing tokens were fetched during recovery.
- Existing native XCTest/runner extended for model-free capture readiness and a one-turn combined resource experiment. Exact prepared executable/runner/fixture identity, locks, scoped console, actual microphone, speaker-playback acknowledgment, safety abort and preference restoration remain in place.
- Launch/Make failure lessons and `AGENTS.md` checklist. No generic new harness, tester agents or memory-policy fix.

## 3. Exact model, runtime and current configuration

This is **v2 AED**, not v1, CTC, LLM or the full ASR2S pipeline. The current graphs are already INT8; “quantize to INT8” is not a new proposed optimization.

| Item | Pinned identity |
| --- | --- |
| Official weights | `FireRedTeam/FireRedASR2-AED`, revision `2304afed56eacfee6256dee5937ed22ffa0b64ec` |
| Official checkpoint | 4,731,558,506 bytes; SHA-256 `4677cbd30988d63ed3e777f6a42a1e5260a3865317f6e15e488bef40954f7054` |
| Official inference source | `FireRedTeam/FireRedASR2S` at `4e7d9aaf4482a47cec1724807026b9b151926eb5` |
| Reviewed conversion recipe | `csukuangfj/FireRedASR2S` at `5febe49b840d976a52aaa8e50d5f49df14e550e8`, `fireredasr2s/fireredasr2/export_aed_onnx.py` |
| Actual downloaded export | [Immutable Hugging Face package](https://huggingface.co/csukuangfj2/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26/tree/374cff185e952c40fcf2f6da972a3b6cf340608d) |
| sherpa-onnx | `a5b4a944c5186a68bcdc0ac3011e4c541781ac84`, version 1.13.8 |
| ONNX Runtime | 1.28.2; upstream tag resolves to `33ca9628233dc8f002435e868d4c2e9f82766ca1` |
| ORT device archive SHA-256 | `2c2299acbb461d26d4bac4bc85985d40e7c7177ed6072703ae0846d88b0b4599` |
| Managed package | `firered-asr2-int8-374cff18-v1`, manifest SHA-256 `a302683c199acb2b37e664fd8ba52d7a5d47503d49dfdff06ba861a264329e3d` |

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `encoder.int8.onnx` | 817,286,833 | `54048d66b6e8f3c80ea7ce95efe794587b0fd81d7271651d0decd3803852ae82` |
| `decoder.int8.onnx` | 417,291,928 | `b840ce7196ae4a14d05ae84bbf56082b6b61ccec5610fda907dddbcea37354ff` |
| `tokens.txt` | 79,172 | `1bc613de2112d257e61a349c3e72d1b1a9cf19c33d3ca954197ad2171e5ea07b` |
| **Total on disk** | **1,234,657,933** | Not a RAM measurement |

Both released ONNX graphs were inspected as self-contained, with no external tensor files. The conversion recipe's producer commit is not attested by the release; byte-for-byte re-export reproducibility has not been proved. The cached reviewed recipe uses `quantize_dynamic`, explicitly `QUInt8` for the encoder and the function's default weight type for the decoder. That recipe alone does not inventory every actual released tensor/operator type or prove all activations/weights are eight-bit.

Current native policy: **CPU EP, one inference thread, greedy, batch one, 16 kHz mono, maximum 30 seconds per turn**. No Core ML/ANE execution claim for FireRed. One recognizer intentionally owns encoder and decoder ORT sessions; two sessions alone do not mean the same model was loaded twice. Existing session options leave CPU arena/memory-pattern defaults unchanged. Per-turn stream/result handles are destroyed deterministically; native synchronous work must return before its owner releases the recognizer. VAD uses the existing FluidAudio/Silero path. Resource diagnostics disable VAD repair/redownload and fail on VAD errors.

The v2 decoder has 16 layers, 20 heads, head dimension 64, 8,667 logits, SOS 3/EOS 4 and dynamic self-K/V cache length. Upstream runtime already estimates needed cache length; do not propose “fix a full 1,024-token v1 cache” without checking the actual v2 implementation. The latest warning preceded the first decode, so a turn-cache-only proposal cannot by itself explain that failure.

### Existing pinned-source leads, not proven causes

- [AED session construction](https://github.com/k2-fsa/sherpa-onnx/blob/a5b4a944c5186a68bcdc0ac3011e4c541781ac84/sherpa-onnx/csrc/offline-fire-red-asr-model.cc).
- [Greedy decoder and cache lifetime](https://github.com/k2-fsa/sherpa-onnx/blob/a5b4a944c5186a68bcdc0ac3011e4c541781ac84/sherpa-onnx/csrc/offline-fire-red-asr-greedy-search-decoder.cc).
- [sherpa session options](https://github.com/k2-fsa/sherpa-onnx/blob/a5b4a944c5186a68bcdc0ac3011e4c541781ac84/sherpa-onnx/csrc/session.cc).
- [ORT session defaults](https://github.com/microsoft/onnxruntime/blob/33ca9628233dc8f002435e868d4c2e9f82766ca1/onnxruntime/core/framework/session_options.h) and [BFCArena allocation/free/shrink](https://github.com/microsoft/onnxruntime/blob/33ca9628233dc8f002435e868d4c2e9f82766ca1/onnxruntime/core/framework/bfc_arena.cc).
- [Reviewed conversion recipe](https://github.com/csukuangfj/FireRedASR2S/blob/5febe49b840d976a52aaa8e50d5f49df14e550e8/fireredasr2s/fireredasr2/export_aed_onnx.py).

## 4. What was found in the old quantization worktree

Read-only inspection of `/Users/tiger/Dev/ios/mural-firered`:

- Branch `firered-aed-probe`, clean at **`e6beb3576ee87321a483f9b23fcc0d3feb97ab60`**. `git merge-base --is-ancestor firered-aed-probe mvp` succeeds. No branch-only changes need merging, and no files there were modified.
- Relevant commits: `880d286` added the isolated v2 AED probe; `e6beb35` documented the host gate. Later embedded/live work reached `mvp` as `d6c0287`, `737a29e`, and memory-investigation preservation `74df98b`.
- Its tracked `pin.json` is identical to current `mvp`. The retained `.build/firered` tree contains the official 4.73 GB checkpoint, released encoder/decoder INT8 files, matching staged copies, upstream conversion source, native builds and host replay evidence.
- No separate Q4/Q6/lower-bit FireRed artifact, local conversion patch or committed lower-bit experiment was found in the scoped tracked history and inspected model/staging/conversion/evidence directories. This is a scoped inventory, not a claim about every unrelated directory on the Mac.
- The repository's PAL4/PAL6/Core AI investigations concern the separate PhoWhisper/Core ML path. For example, [PAL4 mixed result](../combined-pal4-mixed-result-20260918.md) is English/Vietnamese, not FireRed evidence.
- Earlier host comparison ran official PyTorch against the released INT8 package on four upstream clips: 3/4 matched after case-folding, one had an extra character, 0/4 raw exact matches. It was model-to-model agreement, **not human-reference accuracy or lossless quantization proof**. No fresh export or model execution was performed for this handoff.

## 5. Resource observations: three different runs

All byte values below retain their original metric definitions. Decimal GB, GiB, file size, RSS, Mach footprint, cumulative allocations and live allocation bytes are not interchangeable.

### September 20 original live warning, unprofiled

- Seven microphone submissions, four native decodes; warning while Ready/idle, approximately 338 seconds after constructor return and 137 seconds after the last decode.
- Warning footprint **1,492,454,728 B**; process-lifetime peak footprint **1,507,396,936 B**. Footprint had fallen about 14.3 MB since the last native return.
- Immediate recognizer destruction sample **391,711,688 B**, taken inside deinit before all Swift property release. No delayed final baseline. Native load approximately **1.700 s**, total prepare **2.717 s**.
- No tutor/TTS turn was established in that ASR-only probe. Two owner warning logs describe the same notification, not two loaded recognizers or two separate OS warnings.

### September 20 separately approved profiled diagnostic

- Two actual spoken turns; native constructor **9.958 s**, total prepare **14.057 s**. Profiling/cache/source/input differences confound comparison with the unprofiled run.
- 89 settled samples across **269.537 s**, footprint **1,573,965,152 to 1,574,620,512 B**. Peak footprint **1,593,527,648 B**. No warning observed in its bounded log or by the user.
- Capture/log timing missed the full 360-second post-turn idle and +2/+10/+30 owner-release samples. This run did not exonerate the first warning.
- Later offline time-selected Statistics from this saved trace: persistent heap + anonymous VM **25,038,144 B at 100 s**, **1,725,419,104 at 200 s**, **1,725,379,776 at 430 s**, **35,556,432 at 480 s**. These are allocation totals, not footprint. Default final view hides the large loaded interval.
- A bounded partial constructor export at 119-120 s contains ORT graph-transform/type-inference and protobuf stacks. Only 7,524 complete rows / 330,192 allocated bytes were recovered before truncation; it cannot attribute the approximately 1.7 GB loaded total. Small constructor allocations do not establish a protobuf leak.

### September 28 managed combined-Talk continuation: **FAIL / STOP**

Run **`20260928-125336-34898`**, physical iPhone 17 / `iPhone18,3`, iOS **27.2 (24B5084k)**. Pinned managed package, runtime-only Release candidate, explicit Vietnamese Core AI build configuration preserved. Allocations + VM Tracker attached before Prepare after a useful same-PID baseline export. Instrumented timings are not shipping performance benchmarks.

| Boundary | Mach footprint (B) | Device uptime (s), if recorded here |
| --- | ---: | ---: |
| Talk owner baseline | 84,330,480 | See private log |
| Sampled pre-warning peak | 1,523,698,920 | Sampled, not asserted kernel lifetime maximum |
| Real Ready | 1,407,307,104 | 718101.667879 |
| iOS warning during Recording | 1,406,668,128 | 718109.998038 |
| Owner drained | 437,423,024 | 718110.372701 |
| +2 seconds | 313,887,568 | See private log |
| +10 seconds | 106,432,904 | See private log |
| +30 seconds | **Missing** | Test teardown ended observation |

- Hash verification approximately **0.830 s**, VAD preparation **4.640 s**, native preparation **13.138932 s**. Constructor start/return uptimes **718058.111443 / 718071.250375**.
- Initial speech completion event `tts_finished backend=pcm` occurred before Ready. Actual microphone and frozen Mac-speaker playback began. The warning occurred **before any FireRed decode**, before a completed learner/tutor turn. No successful playback-completion/turn acceptance or human listening confirmation. No room audio recorded.
- Warning reported headroom **2,133,324,448 B**, thermal state **1 (fair)**. This does not invalidate the warning or identify an iOS threshold/global pressure cause.
- Native safety teardown stopped the session and released resources. XCTest **0 passed / 1 failed / 0 skipped**. No full combined workload, six-minute idle or full delayed release qualification.
- Original host cleanup **FAIL**: profiler finalization exceeded 60 seconds, then process-group teardown raised `PermissionError`. Total runtime **232.178 s**, including **84.625 s** cleanup. Native settings restoration/readback and app/runner termination were recorded.
- Separate recovery inspection found empty owned host/phone inventories and a readable saved trace. Original failure/cleanup are preserved. Trace target exit zero is not evidence of profiler exit zero. No automatic native retry.

Offline Statistics from a clone of that trace:

| Selected trace time | Persistent heap + anonymous VM (B) | Heap (B) | Anonymous VM (B) |
| --- | ---: | ---: | ---: |
| 85 s, loaded before warning | 1,410,619,792 | 1,293,441,424 | 117,178,368 |
| 104 s, after drain | 34,990,256 | 22,145,200 | 12,845,056 |

At 85 s the three largest malloc classes were **427,048,960 B / 65 live allocations (6.27 MiB class)**, **344,195,072 B / 208 (1.58 MiB)** and **316,145,664 B / 48 (6.28 MiB)**: **1,087,389,696 B combined**. This is a useful size-pattern lead, **not attributed weight/prepack/arena ownership**. `VM_MEMORY_109` accounted for another 99,368,960 B in four allocations, without established component attribution. Cumulative allocation at 85 s was 8,613,951,968 B across many events; it is neither resident RAM nor a leak total.

Detailed allocation export hit its 60-second bound and a subsequent cleanup permission error. No broader retry. Existing evidence supports substantial releasable loaded residency; it does not prove leak freedom, a specific allocator defect or an external pressure trigger.

## 6. What has passed, and what remains unverified

| Check | Scope and evidence |
| --- | --- |
| Managed network acquisition | Originally empty managed location; first 4 MiB decoder chunk, cancel/drain and exact-offset resume; both full graphs transferred in failed run `20260928-114321-74679` |
| Token defect recovery | `20260928-121115-36976`: one native test/cleanup PASS, 49.47 s; only 79,172 new network bytes; entire 1,234,657,933-byte package rehashed and atomically activated; original failure remains failed |
| Download UI | Error card gone, no fabricated Record/Ready; native movie decoded 485/485 frames, 24.30 s; original meaning preference restored/read back |
| Current signed candidate | Prepared `20260928-120554-25215`, build/cleanup PASS, 122.28 s; compiler/linker/symbol/pin/notices/signing proof |
| Current model-free capture/UI gate | `20260928-122726-70556`, one native test/cleanup PASS, 162.39 s; no models/audio |
| Focused host regression | 37 Swift package/HTTP/installer checks and `scripts/test_verify_device.py` PASS, repeated for this handoff; shell syntax and diff whitespace checked |
| Speech quality | User's earlier brief native-Mandarin-speaker feedback is positive. No new native transcript or scored corpus result from the failed resource run |
| Resource safety | **FAIL/blocked**, as above; no production-safe memory budget or long-term acceptance established |
| Remaining product qualification | Actual speech/support/persistence, native lifecycle/offline, focused existing-pair regression, ordinary promotion and support-asset cold-cache evidence remain unverified, not erased by the memory-focused priority |

This is **first-download provisioning in an existing installation**, not a literal whole-app clean install. The latter is deferred to preserve data/app slots. Fresh-install-capable acquisition code is implemented. No paid dataset, publication or owned production hosting is implied.

Prepared app executable SHA-256: `f29a9a21a579cfc4668fec4484ded12f2918b9bb2147ff9954866445cd04ece1`. XCTest executable: `846401d0a7e266bdbb8c2b3fdf6abb35aae62f440296e49e442d6d952e0101b2`. Build input identity: `1ab7d14ce2a790922be15d6c67e1a94571273393d897e90f2b9199dc9276ad4f`. Read-only host revalidation for this handoff confirmed all current input, native-library and prepared artifact identities match; no duplicate build/phone/model run was needed for documentation changes.

## 7. Research questions and requested output

Review existing code and pinned upstream sources before choosing a solution. Separate **observations**, **hypotheses**, **supported implementation options** and **unmeasured estimates**. Do not promise a numeric reduction without a measurement or defensible calculation tied to real tensor shapes/runtime behavior.

Investigate and rank approximately **three concrete options**, including why weaker alternatives should be rejected:

1. **Runtime/session residency without changing weights.** Distinguish actual weights, duplicated initializers, prepacked matrices, ORT arenas, memory patterns, graph optimization/transient model loading and live tensors. Inspect whether the large size/count classes match any actual graph parameters or kernels. Are supported memory options exposed through this sherpa C API? If not, what is the smallest version-pinned upstream/source-build change? Explain load, first/warm decode, CPU/energy and correctness tradeoffs; smaller serialized files alone are insufficient.
2. **Further or selective compression.** The starting point is already released INT8. Assess lower-bit/weight-only or selective mixed precision only with actual operator coverage, iOS arm64 CPU/ORT support, quantization recipe/calibration requirements and maintained sherpa compatibility. A desktop CUDA/TensorRT kernel or a Core ML PAL4 result is not proof for this path. Avoid blind re-quantization of already quantized weights. If conversion must start from official weights, preserve separate identities and obtain quality comparisons; never overwrite the active pin/package in place.
3. **Lifetime/co-residency changes, if justified.** Identify which ASR/VAD/voice/tutor resources must overlap in real Talk, and whether a targeted release policy can reduce steady/peak memory without unsafe handle destruction or unacceptable reload latency. Per-turn unloading, session splitting or a new backend are not default recommendations: quantify or explicitly leave their costs unknown. Fix concrete owner leaks if found, but do not invent one merely from high flat residency.

For each recommended option provide:

- A ranked verdict, expected affected memory component, confidence and what would falsify the hypothesis.
- Pinned source permalinks and exact API/configuration/kernel availability, including limitations of the current iOS binary.
- Minimal source files/change points, dependency/build/notice implications, effect on model/package identity and a rollback that preserves existing artifacts.
- Host-only discriminator first where meaningful, then **one** adequately budgeted iPhone experiment proposal. Do not execute it remotely or ask for unchanged repeated loads.
- Expected quality, preparation/first/warm latency and sustained thermal/energy tradeoffs. Mark unknowns honestly.
- A short implementation handback with focused acceptance/rejection criteria. No broad rewrite, provider framework or automatic model fallback.

A research report with no defensible safe solution is preferable to guessing. Identify any missing local evidence by its smallest useful export/request. Raw private traces are not available in the online checkout; do not claim to have inspected them. This sanitized packet supplies the relevant observations and gaps.

## 8. Local continuation constraints and evidence locations

The local agent will implement approved changes and test on the user's physical iPhone 17. Research is **not** authorization to load, change provider/threads/VAD/model/limits, install a new app or promote ordinary availability.

- Reuse `com.kevintruong.mural.dev` and `com.kevintruong.mural.dev.physicaltests.xctrunner`; free developer account, three-app limit. No new QA app, uninstall, personal reset or model/cache deletion. Discover the current phone identifier; never copy historical PIDs/UDIDs from logs as ownership.
- Preserve main signing/backend, voices, preferences, history and developer/managed assets. Already-active managed FireRed content must not be deleted to repeat an empty-location test.
- Existing `make agent-verify-device` / `scripts/verify_device.py` only. Fix and qualify any capture/cleanup repair model-free before native replay. Do not repeat full suites for a narrow change.
- Prepare code/builds/fixtures first. Then obtain explicit review of a causal continuation and current exclusive idle/unlocked/cool readiness, closed owner-coordinated mirroring, agreed moderate built-in speaker output/placement and listening. Previous approval is not a current audible window. No room recording.
- Capture readiness precedes Prepare. The current resource design budgets one real acoustic Talk turn, **360 seconds loaded idle after final completed turn**, native drain and **30 seconds observation**. Existing ceilings: 1,020 s whole runtime including cleanup, 780 s test command, 720 s XCTest, 660 s app resource deadline. Never fit it into the ordinary 300 s XCTest allowance or truncate idle/cleanup to make it pass.
- Stop at the first warning, crash, serious thermal state, model/asset failure or native operation over 60 s. Preserve failures and distinct recovery evidence; no automatic retry. Longer sustainable-use acceptance remains separate from a single bounded diagnostic.
- Real acoustic checks use reviewed frozen audio through Mac speakers into the phone microphone, not injected transcripts/file probes. Six independently reviewed MELI clips exist locally, manifest SHA-256 `11704fc265b19de99b899e668d1b3b3de3d87d1b873c31d3e0406c9811f25cbc`. The attempted M00A-switch clip was 7.8782 s. Preserve raw recognized script. References must not be edited after seeing model output. Names/numbers/short replies remain coverage gaps, not a reason to delay memory research.
- MELI release 1.1 metadata/official terms were checked as CC-BY 4.0; selected speakers' Mainland upbringing reviewed individually. Recorded in Vancouver, overseas experience limits coverage. No private audio or full references are being published here. CS-Dialogue's commercial-use restriction remains disqualifying without permission.

Private evidence retained on the Mac, **not in Git or this online handoff**:

| Location under `.build/verification/` | Contents |
| --- | --- |
| `firered-device-20260920/` | Original file/live warning, source/build hashes and scoped logs |
| `firered-memory-analysis/`, `firered-memory-device-20260920/` | Original analysis, diagnostic result and `idle.trace` |
| `simplified-talk-offline-20260928/` | Streaming/default and selected-time old-trace exports, bounded failures and partial constructor stacks |
| `simplified-talk-meli-20260928/` | Reviewed frozen corpus, provenance/terms, references, audio and approval |
| `physical-iphone-e2e/20260928-114321-74679/` | Failed real download and separate recovery cleanup |
| `physical-iphone-e2e/20260928-121115-36976/` | Passing retained-token recovery, video and cleanup |
| `physical-iphone-e2e/20260928-125336-34898/` | Latest warning, compact summary, original cleanup failure, separate recovery inspection, `resource.trace` |
| `simplified-managed-20260928/resource-analysis/` | Latest selected Statistics, summary and allocation-export blocker |
| `firered-memory-handoff-20260928/` | Commit-time focused checks and exact build identity revalidation |

No raw console logs, audio, transcripts, trace binaries, app/model binaries, signing material, personal screenshots or signed CDN credentials are part of the commit. Source plus this sanitized handoff is the online research package. The repository workflows run on `main` pushes or PRs, not a direct `mvp` push; local focused checks are not a claimed green CI run.
