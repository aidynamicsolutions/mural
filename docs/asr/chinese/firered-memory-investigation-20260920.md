# FireRed idle memory-warning investigation

2026-09-20. **INCONCLUSIVE pressure cause; FireRed remains stopped and unqualified.**
Saved-evidence and pinned-source review, host checks, and one subsequently
approved phone diagnostic are complete. The diagnostic showed stable sampled
idle footprint near 1.57 GB with no observed warning, but missed the full planned
idle interval and delayed release logs. No allocation fix or ASR-default change
is justified. Other apps or wider system pressure are possible causes, **not
established causes**; Mural has not been exonerated.

See [completed phone run](#completed-authorized-phone-run-source-f81d665-plus-diagnostic-diff)
for measured results and limitations, and [archive disposition](#archive-disposition)
for evidence retained after worktree cleanup. Earlier sections preserve the
chronology: statements about no approval, no source changes or no phone run apply
only to the initial read-only stage, not the final disposition.

## Initial read-only stage

## Starting state and identities

- Local `mvp` and `origin/mvp` both resolved to
  `185696849b35fd6b70474f8929232b3a88cb2ec1` at inspection. The handoff's five-commit
  divergence no longer existed. No fetch/reset/checkout of the remote was used.
- No tracked working changes. Three untracked prompts were present:
  `local-agent-breeze-onnx.md`, `local-agent-firered-memory.md` and
  `local-agent-short-reply-vad.md`, under `docs/asr/chinese/`. Preserved unchanged.
- Other local Mural agents were active. Created `firered-memory-investigation`
  in sibling worktree `mural-firered-memory`, **from local mvp**. This report is
  the only repository change. Shared-file/phone coordination is recorded privately
  in the original checkout's `.build/verification/firered-memory-coordination.md`.
  No shared application source is claimed or edited; no phone reservation exists.
- Saved live source: `737a29e7a3b3f9f2ff67033573c05d3afb1b832c`.
  All six entries in saved `live-source.sha256` match this worktree. No application,
  tool, script or project source changed between that commit and this base.
  Preserved Breeze checkpoint: `1b12b77`.
- Saved live executable SHA-256, independently rehashed:
  `22d2ce6772afec3234cda635102f3b5896f15e6571cafc58673c28398a43d89c`.
  Actor SHA-256:
  `094200743c36c88f7c03f739f5397db5a2a8f12a4baf5c495836b640a75df438`.
- Saved physical run: iPhone 17 / `iPhone18,3`, iOS **27.2 (24B5084k)**;
  Release, Xcode **27.0 (27A5252f)**, iOS SDK **27.0**. Current read-only discovery
  lists the same hardware/OS; current Xcode/SDK also match. The discovered phone's
  tunnel was **disconnected**, with DDI services unavailable. Attach/install
  readiness and exclusive access are not established by that cached device listing.
- Exact **FireRedASR2-AED**, official checkpoint revision
  `2304afed56eacfee6256dee5937ed22ffa0b64ec`, released INT8 export dated 2026-02-26.
  sherpa-onnx `a5b4a944c5186a68bcdc0ac3011e4c541781ac84` / 1.13.8,
  ONNX Runtime 1.28.2; CPU, one thread, greedy, batch one. Not v1, CTC or LLM.
- `pin.json` SHA-256:
  `72f9d1ae14bedd1912143f7f03e3504b854a20334a2e8064e0b6f4faa2883cfe`.
  All three cached model files were streamed and rehashed against it; total
  **1,234,657,933 B**. No graphs, sidecars or pins changed.
- ORT archive matches pinned SHA-256
  `2c2299acbb461d26d4bac4bc85985d40e7c7177ed6072703ae0846d88b0b4599`.
  Its extracted arm64 library/header match the archive. All 14 entries in the
  preserved native-build hash inventory match. Relevant cached sherpa sources
  match the preserved source archive. Shared caches remained read-only.

Full export/checkpoint provenance and per-model hashes remain in
[`pin.json`](../../../Tools/ChineseASR/FireRedProbe/pin.json) and the
[qualification result](firered-aed-qualification.md). Ordinary Talk remains
**FP8 Core AI encoder + PAL8 Core ML decoder, prewarm always**, as specified by
[the current ASR index](../README.md), without historical build opt-ins.

## Evidence inspected and missing

Original private evidence: `.build/verification/firered-device-20260920/` in the
main checkout. Inspected `result.md`, complete structured initial report excluding
raw text from derived output, full-log scoped event searches, metrics log/JSON,
warning screenshot, source/executable hashes, compiler/build, install/launch,
restoration and capture-ownership/cleanup records. The raw log, not just its
metrics extract, supplies the VAD-period compiler diagnostics below.

The screenshot confirms Speech unavailable and the memory error, not the instant
of the warning. It also retains the already-known contradictory generic Prepare
again notice. That notice is not permission to retry; no UI fix is claimed here.

September 19 `memory-warning-20260919-171606/` and the original
`vad-20260919-162329-530/fast-reject/device.log` are present and inspected for
relevant events. The original has redacted E5RT errors at 17:00:48 and two UIKit
warnings at 17:00:58/17:01:10. Follow-up captures show prewarm-boundary diagnostics
and completed replays, not an established pressure cause.

**Missing:** `.build/verification/coreai-load-reliability/` and
`.build/verification/coreai-hybrid-memory/`. Their checkpoint documents were read;
the underlying historical allocations/kernel evidence was not inspected. In
particular, the documented iOS 27.0 per-process-limit termination is not evidence
of an equivalent limit in this iOS 27.2 CPU run.

**Not recorded for the FireRed failure:** allocation stacks/live allocation
counts, VM-region categories, allocator in-use versus reserved bytes, independent
VAD footprint boundaries, delayed whole-app samples after actor property release,
system-wide pressure attribution, and microphone waveforms. The September 20 VAD
artifact was not independently inventoried in this evidence. September 19's
five-file, 1,063,425-byte Silero inventory is historical, not a verified new pin.

## Reconstructed timeline: observations

Times below are local device-log times. Native uptime and owner turn IDs correlate
the live intervals; IDs and raw recognized text are intentionally omitted.
All memory columns are **whole-process current physical footprint**, not model RAM.
Kernel lifetime peak footprint and lifetime RSS peak are separate metrics.

### Initial file gate: different process and ownership path

Six identical 5.1-second file replays, two native recognizer lifetimes; no VAD,
LearningStore, normal coordinator or live audio owner. The gate lasted about
14.040 seconds from initial validation to completion, not a long idle test.

| Checkpoint | Device uptime (s) | Current footprint (B) |
|---|---:|---:|
| Validation begins | 184698.594513 | 15,664,872 |
| Before first constructor | 184699.427024 | 18,794,288 |
| First constructor complete | 184701.433263 | 1,430,998,080 |
| Replay 1 handles released | 184703.033889 | 1,514,343,584 |
| Replay 2 handles released | 184704.551158 | 1,459,604,640 |
| Replay 3 handles released | 184706.081257 | 1,459,702,944 |
| First recognizer released | 184706.120123 | 364,268,368 |
| Second constructor complete | 184707.872784 | 1,262,341,256 |
| Replay 4 handles released | 184709.460961 | 1,274,596,584 |
| Replay 5 handles released | 184710.987301 | 1,276,447,976 |
| Replay 6 handles released | 184712.579138 | 1,275,677,928 |
| Second recognizer released / final cleanup | 184712.632219 / .634835 | 30,051,008 |

Verification 0.811020 s; constructors 2.002556 / 1.748851 s. Decode times:
1.591558, 1.508082, 1.520313, 1.580331, 1.515782, 1.582160 s.
Kernel lifetime footprint peak **1,517,849,760 B**; lifetime RSS peak
**1,547,059,200 B**. All report checkpoints: zero warnings and nominal thermal.
The substantial difference between the two immediate release samples rules out
calling the first residual a demonstrated permanent leak. It does not prove
leak freedom or identify what was retained/reclaimed.

### Live actor preparation and seven submissions

- 10:32:21: main audio-owner backend selection logged. No ASR preparation follows
  until the probe is used. 10:37:04: second audio-owner initialization logged.
- 10:37:25: FireRed asset verification finishes in **0.726163 s**. No before/after
  footprint samples surround this specific verification.
- 10:37:25-26: two MIL mappings, 176,918 and 882,304 B, then **eight ANE compiler
  errors about a 256-by-1 kernel requiring dimensions that are multiples of 8**.
  This is between asset completion and native AED entry, where source awaits VAD
  loading. Paths are redacted. This supports association with VAD preparation,
  not a proven failed VAD load, ANE placement, allocation leak or later-warning cause.
- Native constructor: uptime **185758.208158 -> 185759.908083**, 1.699925 s.
  Ready at 10:37:27: total **2.716548 s**, post-verification preparation/loading
  **1.990321 s**. Roughly 0.290 s is outside native construction in that interval;
  VAD and owner overhead were not separately timed. Current footprint at native
  return: **1,465,011,360 B**.

| Turn | Capture begins | Send / native return | Samples / duration | Gate | Native (s) | Send-final (s) | Post-native footprint (B) |
|---|---|---|---:|---|---:|---:|---:|
| 1 | 10:37:42 | 10:37:47 / 48 | 70,400 / 4.4 s | Accept | 1.077683 | 1.146468 | 1,433,423,080 |
| 2 | 10:38:03 | 10:38:05 / not called | 36,800 / 2.3 s | Reject | Not called | 0.031979 | Not sampled |
| 3 | 10:38:09 | 10:38:11 / 12 | 36,800 / 2.3 s | Accept | 0.495553 | 0.518996 | 1,443,515,624 |
| 4 | 10:38:21 | 10:38:27 / 29 | 94,400 / 5.9 s | Accept | 1.456929 | 1.493256 | 1,480,920,320 |
| 5 | 10:38:36 | 10:38:39 / not called | 44,800 / 2.8 s | Reject | Not called | 0.029704 | Not sampled |
| 6 | 10:38:46 | 10:38:50 / not called | 54,400 / 3.4 s | Reject | Not called | 0.035437 | Not sampled |
| 7 | 10:40:38 | 10:40:46 / 48 | 123,200 / 7.7 s | Accept | 1.936636 | 2.056272 | 1,506,741,528 |

All VAD rows report complete evidence. All captures used 48 kHz input and matching
16 kHz converted counts including converter tail. Last native return uptime:
**185960.600151**. No further inference is recorded before the warning. There is
UI/haptics activity, so idle ASR must not be described as an allocation-free app.
No tutor `model_request`, TTS start or other ASR preparation is recorded in this
scoped live log. Such absence does not inventory all framework allocations.

### Warning, stop and release

At **10:43:05**, one UIKit process warning:

1. Idle main owner samples 1,492,438,344 B, then logs its handler at
   uptime 186097.621378: previous state Prepare speech models, prewarm inactive.
2. FireRed owner samples **1,492,454,728 B** and requests Stop at
   **186097.621938**, `draining=false`.
3. Native destruction completes and actor deinit samples **391,711,688 B**.
4. FireRed warning handler completes at **186097.725257**: previous state Ready
   to record, prewarm inactive. The warning latch remains set. No retry follows.

Warning arrived **337.714 s after constructor return**, **137.022 s after last
native return**. Current footprint had **fallen 14,286,800 B** since that return.
Kernel lifetime peak reached **1,507,396,936 B**, only 655,408 B above the last
post-native sample; lifetime RSS peak was **1,563,279,360 B**. These data do not
show a large new footprint peak during the final idle interval.

The process footprint drops **1,100,743,040 B** across native destruction. That is
strong evidence of releasable residency, not allocation-site attribution. The
391 MB sample is **inside deinit, before automatic Swift property release**, so
it includes a potentially still-owned VAD manager and is not a final app baseline.
The capture ends immediately after the handler; no delayed cleanup sample exists.
Nominal thermal was logged throughout. No observed crash/termination; no independent
Jetsam inventory was collected for this run.

## Ownership and actual residents

The source paths below are at the unchanged tested source identified above.

- `MuralApp.init/body` and `FireRedFileProbe`: `--run-firered` bypasses the store
  and normal owners. Normal launch instead creates RootView/coordinator/main
  `LocalConversationEngine`; the flask sheet owns another engine in `@State`.
  The main selected PhoWhisper label is not proof of prepared weights. The two
  initialization/handler logs agree with these two owners, not two loaded ASRs.
- `RootView.swift` probe controls call `selectASR`, `prepareASR`, `record`,
  `finishRecording`, and `stop`; Close, disappearance, background, route loss
  and interruption also route to Stop. The flask entry is disabled while main
  conversation resources are active. `prepareConversation()` explicitly selects
  PhoWhisper; no product route selects FireRed.
- `LocalConversationEngine.prepareASR` has one stored task. The prepared actor is
  a strong local until preparation and cancellation/generation checks finish.
  `record` snapshots the strong actor into that task, then the concurrent capture
  helper calls `fireRed.transcribe`. Stop cancels but **does not nil the task**;
  its defer clears it after drain. Prepare/Record remain blocked meanwhile.
- Actor `busy` is set before awaited VAD work, blocking reentrant prepare/decode.
  No suspension occurs while a C stream/result exists. Deferred result/stream
  destruction follows synchronous C return on success, Swift error and cancellation.
  This does not promise recovery from a C++ exception/native termination.
  Actor destruction releases the recognizer only after the task no longer owns it.
  All FireRed construction/transcription callers are in this existing owner.
- The capture queue is bounded to 32 packets; turn PCM is local to one helper
  invocation and limited to 480,000 Float32 samples, **1,920,000 B of payload**.
  Copies, packet backing and framework memory are additional, not covered by that
  payload bound. No turn-PCM archive or actor history array retains past turns.
- One FireRed recognizer deliberately owns **two ORT sessions**, encoder and
  decoder. That is not duplicate model loading. The native factory selects AED
  directly. Per-turn features, cross/self-KV and output tensors are scoped values;
  the dynamic v2 self-cache is bounded by estimated tokens plus four, not an
  ever-growing actor cache. Stream fbank/result storage dies with its stream.
- VAD is an additional resident: pinned FluidAudio
  `41540ea237350afe5117a082b5c28eda642d0612` / 0.15.7 owns an MLModel, converter and
  `ANEMemoryOptimizer`. The streaming path resets recurrent state per recording,
  uses one autorelease pool per synchronous prediction, and retains three fixed
  input buffers (4,160 + 128 + 128 Float32 values: 17,664 payload bytes).
  The pool has fixed keys, not one key per turn. This does not bound Core ML's
  compiled plans, internal buffers, mapped weights or service memory. The pinned
  `ModelHub.loadModels` also has a load-error cache purge/redownload path unless
  offline mode is enabled. No such recovery is established in this run; an approved
  diagnostic must disable that existing recovery path before loading any model.
- Normal UI/store, synthesizer objects, framework clients and availability checks
  are present in the live route but not the file gate. No allocation recording
  separates them. No second prepared speech model or retained tutor session was
  identified in the observed source/log path.

Pinned implementation evidence:
[sherpa C handle create/delete](https://github.com/k2-fsa/sherpa-onnx/blob/a5b4a944c5186a68bcdc0ac3011e4c541781ac84/sherpa-onnx/c-api/c-api.cc#L692-L949),
[AED model sessions](https://github.com/k2-fsa/sherpa-onnx/blob/a5b4a944c5186a68bcdc0ac3011e4c541781ac84/sherpa-onnx/csrc/offline-fire-red-asr-model.cc#L41-L62),
[turn-local decoder/KV](https://github.com/k2-fsa/sherpa-onnx/blob/a5b4a944c5186a68bcdc0ac3011e4c541781ac84/sherpa-onnx/csrc/offline-fire-red-asr-greedy-search-decoder.cc#L17-L112),
[VAD prediction lifetime](https://github.com/FluidInference/FluidAudio/blob/41540ea237350afe5117a082b5c28eda642d0612/Sources/FluidAudio/VAD/VadManager.swift#L216-L328),
[VAD buffer pool](https://github.com/FluidInference/FluidAudio/blob/41540ea237350afe5117a082b5c28eda642d0612/Sources/FluidAudio/Shared/ANEMemoryOptimizer.swift#L44-L65).

## Causes: confidence and limits

| Proposed explanation | Classification | Evidence / missing discriminator |
|---|---|---|
| Persistent ORT session/allocator residency | **Supported hypothesis** for high idle footprint, not a confirmed warning cause | Two sessions intentionally remain loaded; large destruction-time drop. Session memory planning, arenas and prepacked weights can remain reusable while outputs are freed. Need allocation stacks and reserved/in-use attribution. |
| App retain cycle, accumulating streams/results/turn PCM | **Inconclusive as a general leak claim; no defect found in the reviewed path** | One observed preparation, four completed native decodes, scoped cleanup and deinit. Idle current footprint falls. Missing live-object/allocation trace and post-release baseline prevent proving leak freedom. |
| Old Foundation hashing-buffer accumulation | **Confirmed absent mechanism in the current verifier** | Actor drains each 1 MiB FileHandle read with autoreleasepool; native file gate hashes with a fixed 64 KiB C buffer. Exact 256 MiB host hashes pass with about 8.6 MB peak RSS. This does not exclude other device I/O/runtime memory. |
| VAD/Core ML retained or faulty resources | **Inconclusive** | VAD is actually used, with compiler errors during its preparation interval. Fixed Swift buffers are small and pooled. No VAD-specific before/after footprint or allocation trace, and no September 20 artifact inventory. Not the same recorded E5RT failure as September 19. |
| Wider system pressure acting on a resident app | **Inconclusive** | Consistent with an idle warning at a slightly lower footprint; no contemporaneous system attribution exists. A Mural-only recording cannot identify another process as the trigger. |
| A fixed FireRed/process RAM ceiling or model unsuitability | **Inconclusive; unsupported by this warning alone** | No kernel limit/kill record in this run. Different model peaks and iOS 27.0 historical limits are not controls. |

ORT's v1.28.2 tag resolves to `33ca9628233dc8f002435e868d4c2e9f82766ca1`.
Its C API header is byte-identical to the pinned binary archive's header.
[sherpa session setup](https://github.com/k2-fsa/sherpa-onnx/blob/a5b4a944c5186a68bcdc0ac3011e4c541781ac84/sherpa-onnx/csrc/session.cc#L139-L242)
leaves arena/memory-pattern defaults unchanged for provider `cpu`.
[ORT defaults](https://github.com/microsoft/onnxruntime/blob/33ca9628233dc8f002435e868d4c2e9f82766ca1/onnxruntime/core/framework/session_options.h#L113-L128)
enable both. [Allocator eligibility](https://github.com/microsoft/onnxruntime/blob/33ca9628233dc8f002435e868d4c2e9f82766ca1/onnxruntime/core/framework/allocator_utils.cc#L79-L94)
can override arena use for alternate allocator/sanitizer builds.
[BFCArena Free/Shrink](https://github.com/microsoft/onnxruntime/blob/33ca9628233dc8f002435e868d4c2e9f82766ca1/onnxruntime/core/framework/bfc_arena.cc#L474-L554)
distinguishes reusable arena chunks from returned allocations;
[destruction](https://github.com/microsoft/onnxruntime/blob/33ca9628233dc8f002435e868d4c2e9f82766ca1/onnxruntime/core/framework/bfc_arena.cc#L78-L90)
releases its regions. This is a concrete retained-memory lead, **not a measurement
of this phone's arena composition**, nor a reproducible binary-build attestation.
No allocator option was changed and no custom arena/statistics bridge was built.

[Apple's warning documentation](https://developer.apple.com/documentation/uikit/responding-to-memory-warnings)
describes system low-memory notifications to running apps and requires reclaiming
resources. It does not provide a universal warning threshold. The existing
stop/drain/latch response remains appropriate even with an unresolved cause.

## Checks and commands

Run from the isolated worktree unless noted. `$MVP` denotes the preserved main
checkout, `$E` this worktree's `.build/verification/firered-memory-analysis`, and
`$SAVED=$MVP/.build/verification/firered-device-20260920`. Local absolute paths,
private output and initial state are retained in that evidence directory.

```sh
git status --short --branch
git rev-parse HEAD mvp origin/mvp
git rev-list --left-right --count origin/mvp...mvp
git worktree list --porcelain
# Executed from main checkout, with the sibling path:
git worktree add -b firered-memory-investigation ../mural-firered-memory mvp

python3 -m unittest discover -s Tools/ChineseASR -p 'test_*.py' -v
python3 Tools/CoreAI/test_asset_verification_memory.py
python3 -m unittest Tools.CoreAI.test_asr_final_review.SourceContractTests -v
swift test --filter SpeechPresencePolicyTests
swift test --skip-build
python3 "$E/check-firered-hash.py"
git diff --name-only 737a29e HEAD -- App Tools scripts Mural.xcodeproj

xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
xcrun devicectl list devices --timeout 15 --json-output "$E/device-discovery.json"
xcrun xctrace list templates
xcrun xctrace record --template Allocations --instrument 'VM Tracker' --show-recording-options
codesign -d --entitlements :- "$SAVED/live/Mural.app"
```

| Check | Result this investigation |
|---|---|
| ChineseASR suite, including FireRed owner/drain contracts | **47 passed** |
| CoreAI final-review source contracts, including latch/default/empty-turn guards | **7 passed** |
| SpeechPresencePolicy tests | **21 passed**, policy unchanged |
| Full core suite using the same compiled tests | **86 passed** |
| Existing actual Talk hash loop, exact 256 MiB input | **Passed**, host peak RSS 8,617,984 B |
| Same existing host harness with actual FireRed hash loop substituted | **Passed**, host peak RSS 8,634,368 B; private runnable script retained |
| Model/runtime/source/executable hash checks | **Passed**, streamed reads; inventories retained |
| Ordinary generated project excludes native FireRed links/flags/bridge | **Passed**, read-only assertion; not regenerated |
| Saved opt-in and ordinary Release builds/install/restore | **Passed in original logs**, not new builds |
| New opt-in/ordinary builds and phone replays | **Unrun**, no source code changed; approval/access required |
| Real in-flight cancellation, long soak, leak freedom, pressure attribution | **Not established** by host/source checks |

Host command issues retained rather than hidden: `xctrace record --help` rejected
that spelling but printed usage; the supported show-recording-options command
passed without recording. First entitlement parsing used a non-seekable pipe;
parsing the saved plist corrected it and confirmed `get-task-allow=true`. Initial
private hash harness left an unused counter; removed it and reran warning-free.
None required a production code, toolchain or dependency change.

## Smallest next experiment: approval required, not executed

**Hypothesis:** most idle footprint is session/allocator residency, rather than
continued accumulation of live turn objects. VAD/framework or UI growth remains
an alternative. One app-scoped allocation/VM recording can discriminate these
without changing weights, inference configuration or normal Talk.

Propose **one fresh-process live-actor diagnostic, maximum eight-minute capture**:

1. Obtain exclusive phone handoff from all active agents, rediscover/connect/unlock
   the same physical phone, and close Device Hub before speech. Keep the existing
   `com.kevintruong.mural.dev` slot/signing; no app uninstall or asset transfer.
2. Prepare only minimal opt-in diagnostics: reuse `logMemory` at verification,
   VAD/native preparation boundaries and after owner drain; pair boundary markers
   with uptime. Add a finite diagnostic deadline and thermal-change Stop using the
   existing owner, active only for this explicitly selected diagnostic. The thermal
   observer must read `thermalState` before registration per
   [Apple's API](https://developer.apple.com/documentation/foundation/processinfo/thermalstatedidchangenotification).
   No generic monitor, allocation-policy change, PCM retention or forced periodic
   cleanup. Before any diagnostic VAD load, use the existing `ModelHub.offlineMode`
   to prevent load-error cache purge/download; stop if cached VAD is unavailable
   rather than treating a fail-open ASR-only run as the intended experiment.
   Successful VAD compute/gating remains unchanged. Coordinate the shared owner
   edit before implementation.
3. Build opt-in Release with `python3 scripts/generate_project.py --firered-file-probe`
   and the README's existing signed build recipe in this isolated worktree, using
   separate derived data and read-only pinned native inputs. Preserve the signed
   diagnostic app, regenerate ordinarily, build the ordinary path too, and verify
   both identities. Do not use historical Core AI opt-in flags.
4. Launch normally, **not `--run-firered`**, and attach to that Mural PID before
   Prepare. Record a baseline, then flask > FireRed > Prepare once, two ordinary
   spoken turns of approximately 5 and 8 seconds, then **360 seconds loaded/Ready
   idle after the final native return**. No tutor, extra qualification turns or
   background transitions. These are new unmatched live inputs, not replays of
   the lost recordings or an accuracy comparison.
5. Stop normally by about 420 seconds after Ready, or immediately on the first
   warning, crash, serious thermal state, unusable UI/resources, missing diagnostics
   or completed native operation over 60 seconds. Cancel through the owner and
   allow synchronous native work to drain. Never destroy handles from the observer.
   If healthy cleanup is possible, retain up to 30 seconds of **post-stop observation
   only**, with no inference, to measure final property/framework release. Eight
   minutes is an outer capture bound, not permission to continue after a failure.
6. Preserve failed/incomplete traces. Stop only this run's capture processes after
   verifying ownership. Restore the ordinary app in place after drain; no default
   ASR inference retry. No unchanged second run without new evidence/review.

Capture ownership would belong to this investigation, with commands, PID, start
wall time/uptime and output file recorded before the user acts. Mural-only
`idevicesyslog -u "$DEVICE_UDID" --no-colors -x -p Mural` plus:

```sh
# Proposal only. Options were inspected on host; no recording has started.
xcrun xctrace record --template Allocations --instrument 'VM Tracker' \
  --device "$DEVICE_UDID" --attach "$MURAL_PID" --time-limit 480s \
  --recording-options "$E/allocation-options.json" --output "$E/idle.trace"
```

The proposed options enable automatic VM snapshots every three seconds, keep
allocation/free events and C++ identification, disable reference-count/zombie
recording, and exclude unscoped OS logs from Points of Interest. Separate scoped
Mural logs provide the existing phase/uptime correlation. Keep all trace contents,
screenshots and logs private. No all-process capture, Core AI system template,
device-wide archive or system-pressure injection is authorized. Allocation tracing
adds memory/timing overhead; its latency values are diagnostic, not a replacement
for the original uninstrumented startup results.

**Discriminating evidence:** growing outstanding allocations during inference-free
idle, with symbolicated stacks, would identify a concrete allocation lead. Flat
outstanding work with persistent ORT-origin regions reclaimed after Stop supports
retained runtime memory. Growth in Core ML/VM categories around VAD boundaries
supports investigating that owner instead. Persistent residual allocations after
all owners drain require their own stack/region attribution before calling them a
leak. An app-only trace cannot identify which external process triggered pressure;
request separate, specifically scoped system-diagnostic approval only if needed.

A warning-free eight-minute run is still **inconclusive about the original event**.
If profiling cannot attach or lacks useful stacks, stop and report that evidence
gap instead of proceeding with an uninstrumented soak. No unload-every-turn policy
is proposed. Reload/first-turn cost after a correction remains unmeasured because
there is no correction yet.

## Preservation and disposition

The original ordinary executable was rehashed as
`d28e55d04bfae778e0c674fbc00124882ba08a2285cbb8868d403618cbb53584`;
saved restoration logs confirm its in-place install/launch. This investigation did
not change the currently installed app or read learning data. Original failure
logs/screenshots, native assets and the old FireRed worktree are retained.
No capture was started by this analysis, and no commit or push was made.
The approval form ended without a response. **No diagnostic approval or exclusive
phone handoff was obtained; the proposed source instrumentation and phone run
remain unimplemented/unrun.**


## Authorized diagnostic preparation follow-up

The user subsequently released iPhone 17 and explicitly authorized the proposed
bounded diagnostic. The earlier unanswered approval form is no longer an
approval blocker. This isolated branch was fast-forwarded to current local `mvp`
`f81d6654399191d2aa2f9bac46fc0176b8a71964` before instrumentation, preserving the
accepted short-speech VAD and converter corrections. These differ from the
original failing live source; the diagnostic is not an exact source replay.

Uncommitted diagnostic instrumentation is confined to the FireRed actor, existing
audio owner, and focused source-contract test. The explicit probe build plus
`--firered-memory-diagnostic` enables phase samples, one Prepare per owner,
two submissions, a 420-second deadline from Prepare, three-second residency and
thermal checks, cancellation through the existing owner, and samples after task
and audio drain plus 2/10/30 seconds. It does not change allocation/session policy.
Diagnostic VAD loading sets FluidAudio offline mode before load to forbid its
cache-repair/download path; VAD failures stop instead of silently omitting VAD.
Existing warning latching and synchronous native-handle ownership remain intact.
The periodic thermal observation has up to approximately three seconds of latency,
plus scheduling delay. This is not instantaneous notification-based protection.

### Checks and artifacts

Private evidence: `.build/verification/firered-memory-device-20260920/` in the
investigation worktree. Full source diff, build output, source/pin/executable
hashes, entitlements, discovery and installation errors are retained there.

- Diagnostic Release: **passed**, `build-diagnostic-clean.log`.
- Ordinary Release: **passed**, `build-ordinary.log`; generated project restored
  without native FireRed links or build condition.
- Core Swift tests: **91 passed**.
- Chinese ASR checks: **48 passed**, including bounded diagnostic source contract.
- Core AI final-review checks: **16 passed**.
- Existing 256 MiB hash regression: **passed**, host peak RSS 9,699,328 bytes.
- Exact FireRed hash-loop extraction: **passed**, host peak RSS 9,732,096 bytes.
- Whitespace check: **passed**. Phone scheduling/drain behavior remains **unrun**.
- Diagnostic executable SHA-256: `c24fa226cc75f421df5c369cf05acba5b981486f27b781a60781008c247dc931`.
- Ordinary executable SHA-256: `fc8c79c5dc53b7f7c19bbcc5e47948400527f39f92383b452a0e82e0dcdcac8a`.

Build command, from the isolated worktree, after generating the appropriate variant:

```sh
python3 scripts/generate_project.py --firered-file-probe
xcodebuild -project Mural.xcodeproj -scheme Mural -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .build/firered-memory-clean-derived \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  PRODUCT_BUNDLE_IDENTIFIER=com.kevintruong.mural.dev build
# Preserve signed diagnostic app, then use the same build command after:
python3 scripts/generate_project.py
python3 -m unittest discover -s Tools/ChineseASR -p 'test_*.py'
python3 -m unittest Tools.CoreAI.test_asr_final_review
python3 Tools/CoreAI/test_asset_verification_memory.py
python3 .build/verification/firered-memory-analysis/check-firered-hash.py
swift test
```

Initial diagnostic compilation failed on accessing an observable main-actor task
from nonisolated deinit; using Swift's `isolated deinit` fixed the build. The first
build also exposed a build-cache isolation mistake: cloning the entire existing
DerivedData copied stale absolute output paths. Xcode reported removing stale
WebRTC/include/static-library outputs under the main checkout's DerivedData.
This violated the intended read-only build-cache boundary; no source, model,
phone cache, or shared FireRed native artifact was intentionally changed. Failed
output is preserved. Subsequent builds used a fresh DerivedData with only copied
SourcePackages, avoiding the copied build database. Do not reuse the failed
DerivedData clone. Main generated build products may need regeneration on its
next build; no destructive cleanup or repair was attempted.

### Phone outcome: blocked before inference

Fresh discovery confirmed available paired iPhone 17 / iPhone18,3, iOS 27.2
(24B5084k). The signed diagnostic installed in place using the existing
`com.kevintruong.mural.dev` bundle. Launch with `--firered-memory-diagnostic`
failed: CoreDevice 10002, FBSOpenApplicationErrorDomain 7, device locked.
The readiness interview then ended with a lost heartbeat and returned no answer.
No allocation capture, audio capture, Prepare, VAD/native load or inference was
started. This is a **blocked diagnostic**, not a second FireRed resource failure.
The freshly built ordinary signed Release was successfully restored in place;
launch/UI verification remains blocked by the lock. No owned captures remain.
No app uninstall, cache deletion, model substitution or ASR-default change.

Next action is unlock and human readiness confirmation, followed by the already
authorized bounded recording attached before Prepare. Do not count this preparation
as a warning-free residency test or alter the earlier inconclusive cause findings.


## Completed authorized phone run: source f81d665 plus diagnostic diff

After the user unlocked the phone, the same saved diagnostic was installed and
launched with `--firered-memory-diagnostic`, PID 27724. Multiple-choice interviews
confirmed Mural unlocked, both turns completed, manual Stop without a visible
warning, the ended screen with Prepare disabled, and ordinary Mural restored.
No extra turn, retry, model substitution or broader system diagnostic occurred.
The previously blocked launch was not a model run.

### Capture and timing limitations

One Mural-only Allocations + VM Tracker recording was attached before Prepare.
The profiler initially waited for the device despite Mural already running.
Trace metadata records **17:29:22.031 to 17:37:23.115**, 481.084 seconds for the
requested 480-second time limit (including ending overhead). All times here are
local device/host time, UTC+07:00. The process-filtered log had an independent
480-second deadline beginning at 17:28:51 and ended around **17:36:51**.

This was an investigation orchestration defect: the log and trace deadlines were
not aligned to actual profiler readiness or the subsequent human Prepare. The
planned 360-second post-decode idle plus full delayed release log could not fit.
The user was informed and asked to end the shorter run, rather than silently
extend or repeat it. Their Stop occurred after the log deadline. Consequently,
owner-drained and +2/+10/+30-second Mach samples are **missing**, not zero.
No conclusion about the exact post-release whole-app footprint is justified.
Before any future approved phone run, attach first, verify readiness, and budget
human navigation/turns plus idle/drain inside the capture deadline; start the
bounded process log at actual trace readiness. Reuse this trace for offline
analysis before requesting another run.

### Measured timeline

| Boundary | Device uptime (seconds) | Process footprint (bytes) |
|---|---:|---:|
| Owner baseline, 17:31:11 | 210584.353857 | 81,086,400 |
| Verification begin | 210584.395214 | 81,840,064 |
| Verification end | 210585.129022 | 82,855,872 |
| VAD prepare begin | 210585.129435 | 82,855,872 |
| VAD prepare end | 210588.492658 | 92,342,208 |
| Native constructor return, 17:31:26 | 210598.450415 | see private metrics |
| First native return, 17:31:46 | 210618.994547 | 1,512,672,560 |
| Second native return, 17:32:03 | 210636.104581 | 1,593,216,352 |
| Settled idle begins, 17:32:20 | 210652.629044 | 1,573,965,152 |
| Last logged checkpoint, 17:36:49 | 210922.165642 | 1,574,538,592 |

- Verification: **0.733808 s**; VAD preparation: **3.363223 s**;
  native construction: **9.957712 s**; total Prepare: **14.057106 s**.
- Turns were **7.1 and 9.6 s**, not the requested approximate 5 and 8 s.
  Both VAD gates passed. Native decodes: **2.231971 / 2.536794 s**.
- All logged thermal samples were **nominal**. Zero UIKit memory-warning messages
  and zero warning-handler events in the bounded app log. The human reported no
  visible warning and confirmed Stop. No observed crash; no independent Jetsam
  or device-wide diagnostic was collected.
- The final logged checkpoint is **286.061061 s after the last native return**
  and **323.715227 s after constructor return**. This does not cover the full
  original approximately 338-second prepared interval with process logs.
- **89 settled-idle samples across 269.536598 s** ranged from 1,573,965,152 to
  1,574,620,512 bytes, a spread of **655,360 bytes**. This supports stable loaded
  residency in that interval, not monotonically accumulating idle allocations.
- Kernel lifetime footprint peak: **1,593,527,648 bytes**; lifetime RSS peak:
  **1,550,024,704 bytes**. These are distinct whole-process lifetime metrics.
- Prepare was about **5.17 times** the original unprofiled 2.716548-second run.
  Instrumentation overhead, VAD load/cache state, changed accepted VAD/converter
  baseline and different speech confound comparison. This is not evidence of a
  shipping startup regression or a measured reload policy cost.

### Allocation/VM evidence and limits

The **1.9 GiB private trace** is preserved as `idle.trace`. Its metadata identifies
Mural PID 27724 as the attached target. Points of Interest OS log messages were
excluded; no system-wide archive was collected. These exports succeeded:

- `allocation-statistics.xml`: exported default Statistics view reports
  **35,556,432 persistent bytes** for Heap + Anonymous VM, comprising
  **27,167,824 heap bytes** and **8,388,608 anonymous VM bytes**. It reports
  **6,361,969,504 cumulative allocated bytes**, of which **6,326,413,072** are
  transient. Cumulative allocation is neither peak RAM nor a leak total.
- `vm-regions.xml`: default Regions Map includes mapped files, allocator regions,
  framework pages and **33,849,344 resident bytes tagged Performance Tool Data**.
  `Malloc Small` rows include substantial swapped memory (188,645,376 bytes).
  These are not model-only allocations. Region rows may overlap; summing every
  row is not a valid replacement for Mach footprint.

The small exported persistent allocation total is consistent with substantial
cleanup by the end of the trace, in agreement with the human Stop report. It is
**not** a timestamped proof of all owner properties releasing, nor a final
whole-app footprint. Default view exports do not supply a snapshot timestamp
or the before/after retained call-stack attribution needed for stronger claims.

A bounded attempt to export Allocations List hit the deliberate file-size limit
(exit 153); the output XML is empty. The successful trace, Statistics and Regions
Map remain intact. The first TOC export attempted while the trace was saving
failed with Document Missing Template; the completed trace exported successfully.
Both failed export logs are preserved. No allocation-stack cause was invented.

### Updated cause classification

| Proposed explanation | Classification | What this run adds |
|---|---|---|
| Original asset-hash autorelease accumulation recurring here | Not supported | Verification increased footprint about 1.02 MB; exact host hash test passed |
| Continuing idle allocation/lifetime growth | Not supported in sampled interval; broader cause inconclusive | 269.5 seconds of settled samples stayed within 0.66 MB |
| Loaded runtime/session/allocator residency | Supported hypothesis | About 1.57 GB persists while Ready; exported persistent totals are much smaller after reported Stop |
| VAD alone accounts for the prepared footprint | Not supported by these boundary samples | VAD preparation added about 9.49 MB before the native constructor |
| Underlying Core ML/VAD or wider system pressure caused the original warning | Inconclusive | No pressure attribution or independent system evidence |
| Universal per-process RAM ceiling / model inherently unsuitable | Not established | Profiled process exceeded the original warning footprint without a captured warning; thresholds cannot be inferred |
| A proven leak requiring an allocation fix | Inconclusive | No surviving allocation-stack evidence establishes one |

**No allocation fix is justified or applied.** Only diagnostic instrumentation
was added. No per-turn unloading, allocator switch, warning suppression, retry
latch bypass, VAD retune, model/default change or Talk promotion. No reload or
first-turn tradeoff for a fix has been measured.

Smallest next investigation is **offline**: open the preserved trace in
Instruments, select pre-Prepare, loaded idle and post-Stop ranges, inspect live
allocation call trees and timestamped VM snapshots, and attribute retained
regions to ORT, Core ML/VAD, malloc and app/UI. If that does not establish a cause,
report the missing attribution before proposing one fresh, properly budgeted
idle/drain run for explicit review. A short warning-free run does not exonerate
the original configuration.

### Exact operational commands and cleanup

Identifiers below refer to the freshly discovered device and run-local PID;
rediscover rather than copying them for a future run. `$E` is the private evidence
directory in this isolated worktree. Installed bundle stayed unchanged.

```sh
xcrun devicectl list devices
xcrun devicectl device install app --device "$DEVICE_UDID" "$E/diagnostic.app"
xcrun devicectl device process launch --device "$DEVICE_UDID" \
  --terminate-existing com.kevintruong.mural.dev --firered-memory-diagnostic
xcrun xctrace record --template Allocations --instrument 'VM Tracker' \
  --device "$DEVICE_UDID" --attach 27724 --time-limit 480s \
  --recording-options "$E/allocation-options.json" --output "$E/idle.trace"
# Separate subprocess owner terminated this process-filtered logger after 480 s:
idevicesyslog -u "$DEVICE_UDID" --no-colors -x -p Mural
xcrun xctrace export --input "$E/idle.trace" --toc --output "$E/trace-toc.xml"
xcrun xctrace export --input "$E/idle.trace" \
  --xpath '/trace-toc/run[@number="1"]/tracks/track[@name="Allocations"]/details/detail[@name="Statistics"]' \
  --output "$E/allocation-statistics.xml"
xcrun xctrace export --input "$E/idle.trace" \
  --xpath '/trace-toc/run[@number="1"]/tracks/track[@name="VM Tracker"]/details/detail[@name="Regions Map"]' \
  --output "$E/vm-regions.xml"
xcrun devicectl device install app --device "$DEVICE_UDID" "$E/ordinary.app"
xcrun devicectl device process launch --device "$DEVICE_UDID" \
  --terminate-existing com.kevintruong.mural.dev
```

Ordinary signed Release installation and argument-free launch **passed**; human
multiple-choice confirmation says ordinary Mural is open. All owned captures
ended, phone access released. Data/models/caches preserved. Source remains
uncommitted in the isolated investigation worktree; no push. Builds and host
checks listed above apply to the exact saved diagnostic and restored ordinary app.


## Archive disposition

At the user's request, the reviewed diagnostic source, focused regression and
this sanitized report are being committed and integrated into local `mvp`.
The tested source is `f81d665` plus the exact source diff in private evidence;
integration adds no further behavioral change. No push is authorized or performed.
The temporary `mural-firered-memory` worktree and its disposable build caches are
removed after integration. Other agents' changes/worktrees are preserved.

**Current private evidence locations in the main Mural checkout:**

- `.build/verification/firered-memory-analysis/`: 31 files.
- `.build/verification/firered-memory-device-20260920/`: 325 files, including
  `idle.trace`, signed diagnostic/ordinary apps, logs, failed exports and reports.
- `.build/verification/firered-memory-relocation-manifest.json`: before/after
  SHA-256 inventory verifying all 356 relocated files (2,187,969,217 bytes).

Earlier references to evidence in the investigation worktree are historical;
use these main-checkout locations now. Exact past commands and captured absolute
paths remain unchanged as provenance, not commands to recreate the removed tree.
No private logs, trace, screenshots, signing material or binaries enter Git.
Original failure evidence under `firered-device-20260920`, the shared native
`.build/firered` target and the older `mural-firered` worktree remain intact.

**Final conclusion remains inconclusive.** No inference should be made that
another app probably caused the alert; identifying an external trigger requires
evidence not collected here. Preserve the warning latch and stop status. Offline
inspection of the saved trace is the smallest remaining investigation.
