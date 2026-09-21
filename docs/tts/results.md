# On-device TTS results

## Stage 0 - September 20, 2026: PASS

Stages 0–2 accepted. Stage 2's five-phrase phone batch was incomplete; user explicitly waived repeating it and authorized Stage 3. Integrated Talk is human-accepted with captured ASR/Supertonic coexistence evidence; exact offline and transcript metadata checks were not individually confirmed.

- Checkout: existing `mvp`, `f81d6654399191d2aa2f9bac46fc0176b8a71964`, initially clean, one commit ahead of origin. No fetch/reset/commit/push. Only this report and the copied implementation plan added.
- Toolchain: Xcode 27.0 (27A5252f), Apple Swift 6.4. Current paired phone: iPhone 17 / iPhone18,3, iOS 27.2 (24B5084k), wired.
- Baseline Release built, installed in place and launched without arguments or debugger under `com.kevintruong.mural.dev`. Executable SHA-256: `1558868b24fe82313445c31330871114292359305c68e53cc7f62425970a15fb`. Existing signing, history and caches preserved.
- `swift test`: 91 passed, zero failures. These exercise MuralCore, not app audio.
- Build succeeded. Existing warnings: deprecated AVAudioSession interruption API, LiveTransport callback/async alternative, absent AppIntents metadata. No source fixes attempted during baseline collection.
- Actual compiler invocation contains no `MURAL_*` flags. Current source defaults to packed-v3 FP8 Core AI encoder + PAL8 Core ML decoder, `prewarm=always`. The older verify-mural FP16/opt-in recipe is superseded by `docs/asr/README.md` and current source; do not revert to it.
- Runtime launch event confirms the staged backend. Preparation/asset verification, readiness and a real Apple-spoken conversation were subsequently confirmed below. FP8 manifest pin: `73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13`; PAL8 support pin: `430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336`.
- Current Apple resolver is the nested `LocalSpeechVoice` extension in `LibraryViews.swift`, which supersedes the old top-level en-US helper. It preserves all installed English accents and regional preference. Actual selected voice: Karen Premium, en-AU, identifier `com.apple.voice.premium.en-AU.Karen`. Preserve this newer behavior.
- Historical inventory: `docs/coreai/gpu-talk-checkpoint.md` has earlier event-sampled staged footprint near 2.096 GB, not a current memory entitlement. Latest short-reply VAD evidence ran no ASR/tutor/TTS inference; it cannot substitute for this baseline. Existing silence/tutor-quality and historical lifecycle limits are not TTS regressions.
- FluidAudio 0.15.7 checkout matches pin `41540ea237350afe5117a082b5c28eda642d0612`; WhisperKit/Argmax 1.1.0 remains pinned. Supertonic3Manager, `.aneBucketed(.int4)`, M1 style loader and Kokoro detailed samples API exist. No dependency or model changes.
- Kokoro native API explicitly warns that neither CoreML route is known safe on iOS 27. No Kokoro inference authorized or performed. Stage 4 compatibility decision remains future work.

### Model/voice notice inventory (not distribution clearance)

Metadata and exact-revision notices retained locally under `licenses/` in the evidence directory. No model weights or voices downloaded to the phone.

| Intended candidate | Metadata revision inspected | Notice evidence |
|---|---|---|
| `Supertone/supertonic-3` | `3cadd1ee6394adea1bd021217a0e650ede09a323` | Actual LICENSE says BigScience Open RAIL-M, dated August 18, 2022; SHA-256 `0d944a9110fed9a9602d60e0423a272903e7bd21ab060490774efc77c2275e9f`. README applies OpenRAIL-M to model, MIT to sample code. |
| `FluidInference/supertonic-3-coreml`, intended M1 | `9f3606bf5c5ff9d6680cf6226614ac61358a24f3` | Card says `openrail++`; no separate LICENSE listed. M1 preset links to upstream voice styles. Preserve upstream notice and resolve label discrepancy/distribution obligations before shipping. Do not use the desktop benchmark's Apache label. |
| `hexgrad/Kokoro-82M`, intended af_heart | `f3ff3571791e39611d31c381e3a41a3af07b4987` | Card says Apache-2.0; no standalone LICENSE listed. Final frontend/voice provenance remains to be checked when Stage 4 selects a route. |
| `FluidInference/kokoro-82m-coreml` | `1804dbc0aa6507daa4b5d150e2c76963902a67f9` | `ANE/LICENSE` is Apache-2.0, SHA-256 `f29080b0389b53eb15c81fd882c3c71dcbf92b99c5d94ea51df9d7d877fd9fe4`. |

These are metadata snapshot identities, not proof of the eventual acquired asset bytes. FluidAudio's downloader uses its existing cache/repository routing; record actual files, bytes and checksums once after explicit Stage 2 acquisition. Runtime cleanup does not prove native allocations have disappeared.

### Evidence and next action

Local evidence: `.build/verification/tts/stage0-20260920/` (build command/log, compiler command, tests, executable/signing identity, device details, install/launch, scoped device log, notice snapshots).

Stage 0 owns a bounded Mural-only log capture started at 17:43 local time, offset zero, with a 15-minute timeout. Capture ownership/PIDs are in that directory; verify liveness/commands before cleanup. No Device Hub process was running. No device-wide archive or private audio export.

Next: normal On-device Talk > Prepare & start, hear the greeting, Record/Send one short English sentence, hear the response, End. Report audible/visible failures, not timings. Inspect fresh prepared/ready/TTS/memory events before advancing Stage 1. Stop after an error or warning rather than retrying unchanged.

### Stage 0 completed phone check

- User confirmed greeting/reply audible, returned to Ready, End worked. No failure reported.
- Captured actual `asr_staged_prepared`: packed-v3 FP8 named encoder and `phowhisper-cs-pal8-g16-v1`; `asr_ready` preparation 2.364 s. Speculative decoder prewarm 15.208 s; Send waited 3.348 s.
- One turn: Send-to-final 6.538 s, Send-to-audio delegate estimate 10.744 s. Apple startup delegate intervals: greeting 18.4 ms, reply 1.9 ms; not neural synthesis timings. Both have `tts_finished`.
- Highest phase footprint sample: 1,323,812,992 bytes. Kernel process-lifetime footprint high-water in those events: 1,432,455,392 bytes. Neither is a continuously sampled TTS-only peak. Thermal samples nominal; no recorded memory-warning event in this bounded capture.
- Capture stopped after feedback; no ongoing observation. `baseline-events.txt` retains content-free events.
- During Stage 0, an external commit advanced HEAD to `74df98b8865b98c115d53dd257e1c13072a59342` (FireRed diagnostic preservation). Reviewed and preserved; no FireRed probe flags were enabled. The install is identified by its executable hash; exact transient uncommitted source during the build was not snapshotted. The external workflow also staged these two TTS docs. Do not reset or unstage its changes. Stage 1 starts on that new HEAD and has its own source snapshot.

## Stage 1 - September 20, 2026: PASS

### Implemented

- Shared request admission reserved before awaits; owned worker cancellation, drain blocking and stale-ID protection. Playback stop is separate from whole ASR teardown. Coordinator only gains speech-busy readiness guards.
- One session-free PCM player using the actual 24,000/44,100 Hz rates, mixer conversion, render-clock start estimate and `.dataPlayedBack` completion. Quiet one-second signals require explicit Play.
- Release-capable `MURAL_TTS_EXPERIMENT` Settings > Experiments > Speech comparison, plus explicit `--tts-comparison` standalone launch. Apple default and existing voice preference remain. Unintegrated neural choices fail visibly with no fallback or model acquisition.
- Exact 30-phrase corpus; sequential tests, content-free measurements, incremental JSONL, export, memory-warning/3.0 GB sampled-footprint/serious-thermal stops. Apple synthesis/audio duration remain unavailable rather than invented. Native neural preparation/synthesis measurements belong to Stage 2.

### Machine evidence

- `swift test`: 92 passed, zero failures (`core-all.log`). These cover core validation/admission/statistics, not AVAudioEngine.
- Actual app UI test `testTTSExperimentLifecycleAndPCM` passed on iPhone 17/iOS 27 simulator, including both PCM playback completions and actual shared-seam cancellation/drain/failed-prepare checks. Final source rerun: 1 test, zero failures, 30.719 s (`simulator-final-test.log` and `Test-Mural-2026.09.20_18-23-57-+0700.xcresult`).
- Additional simulator actions: Settings navigation; Apple Prepare/Play/completion; Stop during Apple; PCM cancelled before render and during render (422 ms playback elapsed), with cancelled records and no late successful completion. Reports retained in `simulator-runs/`. These are lifecycle evidence, not phone performance or listening evidence.
- Visually inspected native Form, lower controls, Settings entry and final disabled Play styling (`final-settled.png`). A launch-time blank frame resolved; the post-UI-test serve-sim accessibility bridge returned an empty tree, so the settled screenshot and passing native UI test are the evidence, not that empty response.
- Normal Release and experimental Release builds pass. Final phone compiler command contains only the TTS experiment condition, not ASR/FireRed probe overrides. Existing three warnings remain; no new warnings. No dependency pins, ASR assets, signing or saved data changed.
- Source base `74df98b`; `source.diff` and `source-sha256.json` capture the code inputs, including untracked new files by hash. Project edit only registers four app files; no project regeneration.

### Installed checkpoint and next action

- Evidence: `.build/verification/tts/stage1-20260920/`.
- Release 0.1.0 (1), `com.kevintruong.mural.dev`, final executable SHA-256 `15d92402bf2bb99785bb1c73d6daf486ac365838548c3944a0d71e670b21e2cb`, installed in place. This supersedes the earlier intermediate Stage 1 hash.
- Initial launch failed because the phone was locked. User unlocked it; normal launch succeeded at 18:28 local, PID 28168. Fresh `local_talk_asr_backend` confirms unchanged staged backend. No debugger attached.
- Mural-only capture started at 18:27 local, byte offset zero, 15-minute bound. Supervisor 30778 / child 30789, commands/ownership in `capture-ownership.txt`. Initial lock/disconnect produced no app events; after unlock fresh events arrived. Verify live ownership before stopping; do not assume continuous observation beyond timeout. No Device Hub running.
- Owned simulator mirror stopped, app terminated and simulator shut down; no erase/uninstall.
- Phone checklist: Settings > Experiments > Speech comparison; Apple Prepare and Play; explicitly play both quiet PCM rates; Stop a long phrase (29), checking no late sound; return to Talk, Prepare & start, one Record/Send turn, Ready, End. Stop/report any error rather than repeat unchanged.
- User replied **done** to the complete Stage 1 checklist. Human-confirmed Apple speech, both quiet tones, Stop with no late restart, and normal Talk/Ready/End. This is human listening evidence, not an agent acoustic measurement.
- Retrieved only `Documents/TTSComparison` reports: both 24,000 and 44,100 Hz completed (1,048.95 and 1,042.38 ms playback intervals); Apple phrase 06 completed; phrase 29 cancelled after 5,996.32 ms. A corpus attempt completed 01 and cancelled 02 before playback. Max sampled TTS-only footprint across these runs: 63,276,992 bytes. No neural performance claim.
- Fresh logs also confirm correct FP8/PAL8 preparation in 2.292 s and completed Apple greeting. The captured slice lacks a subsequent Record/Send/reply, so that portion is human-reported only, not log-verified. Sampled thermal state nominal. No memory-warning event observed in this bounded capture.
- Capture stopped after feedback; no ongoing observation. `phone-runs/` and `phone-events.txt` retained. Stage 2 standalone Supertonic implementation follows; ASR coexistence, sustained behavior, background/interruption qualification and Kokoro compatibility remain later gates.

## Stage 2 - September 20, 2026: PASS with explicit human smoke-replay waiver

### Implemented, not yet phone-qualified

- One owned `Supertonic3Manager`, explicit `.aneBucketed(.int4)` and `.cpuAndNeuralEngine`, M1, eight steps, speed 1.05, 0.05 s inter-chunk silence. Only the existing `ane-int4` variant and M1 downloader paths are requested. No dependency, model conversion, ASR or public-default change.
- Explicit Prepare shows acquisition/loading progress, records cache-check/acquisition separately from manager initialization, and persists success/failure records. The first synthesis is labeled separately because int4 bucket models load lazily. No warmup is hidden in preparation.
- Artifact inventory hashes only the chosen model/companion/voice files once after acquisition, outside initialization/synthesis timing. It is persisted as `Documents/TTSComparison/supertonic-assets.json`; each run references its checksum. Actual inventory and asset bytes remain **NOT ACQUIRED**. The downloader uses its existing main-ref routing; these eventual byte hashes, not Stage 0's metadata snapshot, identify the tested assets.
- Full bounded text uses the pinned chunker unchanged. The config must report 44,100 Hz; output is checked for finite/nonempty/bounded audio and clipping is flagged, never normalized away. Waveforms are released after playback; retained metrics contain no samples or private text.
- Upstream review found a real truncation hazard: chunker documentation says 110, actual Latin constant is **70**, and a 150-character single word is not split. Actual normalization produces 160 scalars, but the encoder takes 128. Narrow reproduction uses pinned pure source, without models (`truncation-reproduction.txt`). Mural now rejects words beyond the chunk limit and reserves a conservative passage-wide normalization expansion budget before calling the manager. This can reject heavily expanded text that might otherwise fit in separate chunks; visible rejection is intentional, not silent truncation or a second chunker.
- Stop/background/leaving/switching cancels the owned speech worker, discards late results and keeps admission closed through native drain and cleanup. No native cleanup overlaps an outstanding initialization/prediction. Normal completed phrases retain the selected manager. Cleanup does not prove immediate native allocation release.
- Comparison-only dispatch and five-phrase smoke action added. Normal `speak(_:)`, including Talk, remains Apple until Stage 3. Leaving the comparison resets selection to Apple after cleanup. Kokoro remains visibly blocked.
- Reports distinguish first/warm synthesis, generated duration, RTF, request-to-render estimate, sampled footprint and cancellation. Stop-to-silence is only the synchronous stop-API interval, not an acoustic measurement; native worker drain is separate. Native drain behavior is **not phone-qualified** yet.

### Validation and artifact

- Final `swift test`: **92 passed**, zero failures, including all 30 corpus phrases through the conservative preflight and long-word/normalization rejection (`core-all.log`). No claim that core tests exercise CoreML or playback.
- Actual pinned chunker/preprocessor checks pass at 69/70/71/140/1,000 characters; all 30 corpus phrases fit the post-normalization 128-scalar window (`chunker-check.txt`). This is not a pronunciation/listening pass.
- Focused simulator UI test passed on final lifecycle/UI code: 1 test, zero failures, 22.802 s. Actual PCM at both rates and shared admission/cancellation/failed-prepare checks; no neural inference. Evidence: `simulator-test-final.log`, complete `pcm-final.xcresult`, `ui-test-summary-final.json`.
- Earlier attempt passed its test body but the xcodebuild wrapper timed out during result finalization and left an incomplete result bundle. Final run stopped the mirror and used `-collect-test-diagnostics never`, then completed successfully. Do not count the incomplete artifact as an additional passing run. The later input-validation-only patch was covered by core tests and a new Release build, not another UI rerun.
- Native Form and five-phrase button inspected (`simulator-settled.png`). Early blank launch frame resolved; simulator AX helper returned an empty tree after testing, so the screenshot/native XCTest are the UI evidence.
- Ordinary Release build passed; final experiment Release build passed, no new compiler warnings. Existing interruption deprecation, LiveTransport async alternative and missing AppIntents metadata remain. Final experiment compiler includes `MURAL_TTS_EXPERIMENT`, no ASR probe overrides.
- Source: existing `mvp`, HEAD `74df98b8865b98c115d53dd257e1c13072a59342` plus preserved Stage 1/2 work. Final source hashes/diff recorded. No commit, push, project regeneration or dependency update.
- Ready-to-install signed app: `.build/verification/tts/stage2-20260920/Mural.app`, bundle `com.kevintruong.mural.dev`, executable SHA-256 **`7b1c9b485df56cc565766405b0af42cad8a01d8e3ce67d4fac8f6e93624c2b8c`**. This is **not installed**. The earlier intermediate hashes are superseded.

### Blocker and precise resume

The paired iPhone became unavailable before the final device build/install. A generic iOS destination completed the signed build without changing signing or bundle identity; `devices-after-build-blocker.txt` confirms phone unavailability. Stage 1 remains installed. No Stage 2 device logger was started. Owned simulator mirror stopped and simulator shut down; no ongoing capture.

1. Rediscover the reconnected, unlocked iPhone. Install the saved final Stage 2 app in place. Start a fresh bounded Mural-only capture before launching `--tts-comparison`; no ASR/tutor is prepared on that path.
2. Ask the user to choose Supertonic-3 int4, Prepare once on Wi-Fi, then Run smoke check (5 phrases). No sudden automatic audio. Stop/report an error, warning, termination or excessive heat instead of repeating unchanged.
3. Listen to 01/06/11/17/29, then Play 29 again and Stop. Confirm quality and immediate silence/no late restart; capture native drain separately. No precision/voice sweep.
4. After successful setup, force-quit, disable Wi-Fi/cellular, open the same experiment through Settings, select Supertonic, Prepare from cache and play previously unused phrase 28. Do not enter Talk yet.
5. Retrieve only TTS comparison reports/inventory, verify selected file names/bytes/hashes and runtime logs, and update this gate. No current inference, offline, acceleration, memory or listening acceptance. Stage 3 and all subsequent stages remain unstarted.

### Resumed phone checkpoint, 19:47 local

User confirmed the phone is connected and unlocked. Rediscovered paired Kevq; verified saved executable hash `7b1c9b485df56cc565766405b0af42cad8a01d8e3ce67d4fac8f6e93624c2b8c`, installed in place and launched `--tts-comparison` successfully (PID 28630). This supersedes the earlier unavailable/not-installed notes above. Fresh events confirm the unchanged staged ASR configuration and Karen Premium baseline; no ASR/tutor preparation was requested.

Evidence: `.build/verification/tts/stage2-20260920/phone-20260920-194718/`. Mural-only capture started at 19:47:23, offset zero, 900-second timeout (until approximately 20:02). Supervisor 10851 / child 10853; commands recorded in `capture-ownership.txt`. No Device Hub running. Verify ownership/liveness before cleanup. Preparation, smoke listening, Stop and offline reuse were pending at launch. The subsequent feedback/results below supersede this launch status.

### Human feedback and retrieved measurements

- User says Supertonic sounds great and better than the built-in Apple voice. Preparation, long-phrase Stop and offline reuse accepted. This is practical listening preference, not a blinded A/B comparison.
- User reports Run smoke check spoke only “Yes”; repeated attempts again spoke only “Yes” and required Prepare. Retrieved records confirm two runs containing only completed phrase 01, cancelled phrase 29, and completed phrase 28 after process restart. Do not claim the five-phrase phone batch completed.
- Highest sampled **whole-Mural-process footprint: 175,458,288 bytes (175.5 MB decimal)**, during phrase 28. After that playback: 171,263,984 bytes (171.3 MB). Prepared-idle samples roughly 109–132 MB. These are 100 ms samples, not instantaneous peaks, TTS-only allocations or ASR+tutor coexistence figures. Thermal readings nominal; no TTS clipping flags in these records.
- First setup: acquisition/cache work 50.395 s, manager initialize 3.056 s, total 53.576 s. Later fresh-manager initialization 62–100 ms. First phrase 01 synthesis 2.525 s including lazy bucket first use; later 01 synthesis 107.7 ms after reload, 29 synthesis 322.8 ms, offline-reported 28 synthesis 166.5 ms. The batch bug unloaded the manager, so these do not constitute a warm retained-manager distribution.
- Phrase 29 Stop API interval 27.0 ms; worker drain estimate 48.2 ms. Neither is an acoustic measurement or a native-inference cancellation result: the cancellation occurred during playback.
- Acquired inventory: 29 files, 168,943,355 bytes, int4 L128/L256/L512 VectorEstimators, shared graphs/config/indexer and M1. Inventory SHA-256 `560f9b802cd85205c98ce90e11d8abc6b382fb587f9d2b581b37dcc288a0b808`. These are actual acquired byte hashes, not a guarantee of repository revision or license clearance. A relative-path bug prepended `tonic-3/` to enumerated model files because `/var` resolved to `/private/var`; canonical-root correction will write `supertonic-assets-v2.json` once on next preparation. Original evidence remains unchanged.
- Phone evidence: `phone-20260920-194718/phone-reports/` and scoped log. Capture stopped after retrieval; no ongoing observation.

### Smoke-test defect and user decision

At 19:51:18 and 19:51:40, logs show `AVAudioSessionDidBecomeInactiveNotification. Source: App` immediately after completed “Yes.” The comparison treated its normal per-phrase session release as an interruption, cancelled the batch and unloaded the manager. Fixed the shared comparison notification handler to ignore `.app` deactivation while retaining stops for system/unknown deactivation, background and route removal. No change to ASR or model configuration.

Added `testTTSExperimentSmokeContinuesAfterAudioSessionRelease`: all five Apple phrases complete through real session releases in the same runner. It and the existing PCM/lifecycle test pass (2 tests, zero failures; `smoke-fix/tests.xcresult`). This verifies the batch/control fix, not all five Supertonic voices/phrases on phone.

User explicitly says they have heard enough, do not need another smoke test, and want the next step. Accept Stage 2 with this documented waiver; do not ask them to repeat it. Stage 3 Talk integration is now authorized. Integrated readiness, shared memory budget, Help/typed replies, End/background and retained-manager behavior still require their own gate.

Voice question: pinned FluidAudio exposes F1–F5 and M1–M5 (ten presets). Current experiment freezes M1. It exposes language `en`, not a British/Australian/American accent selector; no regional labels or accent guarantees inferred. No extra voice assets downloaded.


## Stage 3 - September 20, 2026: PASS (human-accepted, qualification limits below)

### Resumed implementation and machine checks

- Resumed session `01a0be55-d159-777f-93c2-72d81a755c7f` from its first request and final tool evidence. Preserved all existing changes and the Stage 2 replay waiver. No new voice assets, Kokoro inference, dependency updates, ASR flags, model changes, commits or publication.
- Existing integration prepares Supertonic before ASR, retains the manager across completed speech, routes greeting/reply/Help through `speak(_:)`, waits for outstanding decoder warmup before neural synthesis, and starts greeting decoder prewarm only at PCM playback. Apple retains its prior scheduling. End/background/safety stops cancel and drain before TTS cleanup.
- Explicit Settings > Experiments > On-device Talk speech selector is test-build-only and resets to Apple on process relaunch. Comparison selection remains separate and restores the Talk choice when leaving. No automatic fallback. A 100 ms whole-process footprint/thermal monitor enforces the experimental 3.0 GB/serious-thermal stop while neural Talk is active; this is not a guaranteed instantaneous peak guard.
- Previous run already passed the PCM/lifecycle and five-phrase Apple smoke regression on this app source. Its selection/rollback test failed because an empty accessibility value masked the actual picker label. Saved video confirms the visible selection changed. Corrected only the test assertion to examine both fields; focused rerun passed, 1 test, zero failures, 21.815 s. No app behavior fix was needed for this failure.
- Fresh `swift test`: 92 passed, zero failures. Both ordinary and experimental Release builds passed. Actual app compiler commands contain respectively no MURAL flags and only `MURAL_TTS_EXPERIMENT`. Same three existing build warnings: interruption API, LiveTransport async alternative, AppIntents metadata.
- Working-tree diff whitespace check passed. The previously staged plan snapshot still has five Markdown hard-break trailing-space notices; it was staged externally and was not restaged or unstaged.
- Evidence: `.build/verification/tts/stage3-resume-20260920-203841/`, including core/build logs, selection xcresult, source diff/hashes, app artifact and install/launch. Prior lifecycle/smoke evidence remains in `stage3-20260920/tests.xcresult`. Simulator mirror stopped and inherited verification simulator shut down; no erase/uninstall.

### Installed checkpoint

- In-place Release `com.kevintruong.mural.dev`, executable SHA-256 `b36a5737257a8e16cfcac1ba72a61334d637c1e08cbf776f41e42f5c9eaa8f69`, launched normally at 20:43:58 local, PID 29192. No debugger. Fresh launch confirms the staged Core AI backend; preparation/FP8-PAL8 runtime events remain pending for this build.
- Phone rediscovered as Kevq, iPhone 17, UDID `00008150-000D25942278401C`. Signing, caches and history preserved. No Device Hub process running.
- Fresh Mural-only log capture began 20:43:55 local, offset zero, 900-second bound (until about 20:58:55). Supervisor 89262, logger 89264; ownership/command in `capture-ownership.txt`. Verify liveness and command before cleanup. No continuous observation beyond this window is claimed.

### One integrated phone batch

1. Settings > Experiments > On-device Talk speech > **Supertonic-3 int4 · M1**. Keep English/Vietnamese and On-device mode. Return to Talk, Prepare & start; hear the greeting and wait for Ready.
2. Complete two short Record/Send replies, then one **Type instead** reply. At Ready request **A little help**. Confirm Supertonic remains audible and controls return to Ready without needing another Prepare.
3. During that Help speech tap **End**. Check immediate silence/no late speech. Transcript should retain the completed text with interrupted playback, without duplicates.
4. Start again, background during speech, return and wait for readiness. Confirm no stale speech restarts; do one short Record/Send turn. With cached assets, Wi-Fi/cellular may remain off for this batch to check offline coexistence. Restore connectivity afterward.

Stop at the first error, memory/thermal warning or crash rather than retrying unchanged. Human listening, integrated memory/latency, retained-manager behavior, interrupted playback metadata and offline coexistence remain unverified until feedback/log review. Stage 4 has not started.


### Phone result and acceptance

User replied: “Okay, so it's all good. Everything is all good. Most of the tests are passing. Good job. done”. Accepted as the integrated checkpoint, not an assertion that every substep was individually verified. No failed behavior was reported; do not request another general replay.

- Fresh logs show **seven completed spoken ASR turns**, three additional non-recorded reply/Help generations, two preparations/greetings, a pause during playback and cleanup, then another conversation with five spoken turns. First ASR preparation 2.285 s; second 2.131 s. Both confirm the unchanged packed-v3 FP8 encoder and PAL8 support.
- Supertonic preparation: 3,200.8 ms initially, 146.8 ms at restart. Initial lazy-bucket greeting synthesis 2,900.3 ms; first synthesis after re-preparation 171.9 ms. Ten retained-manager warm syntheses: **102.6–219.2 ms, median 152.4 ms**. `first=false` across completed turns and no intervening cleanup support manager reuse; these are not proof of all native tensors staying resident.
- Seven correlated Send-to-render estimates: **9.443, 7.347, 7.252, 4.735, 4.391, 4.350, 4.436 seconds**. These include ASR/tutor/TTS and are not controlled speed comparisons against Apple. Neural generation is not the dominant interval. Scheduling events confirm decoder prewarm starts at PCM playback, after neural synthesis.
- 2,395 whole-process 100 ms samples: maximum **1,481,230,704 bytes (1.481 GB decimal)**. Process-lifetime footprint high-water **1,482,017,136 bytes**. Sampled thermal state nominal; final cleanup sample fair. No recorded memory warning, 3.0 GB safety stop or clipping flag. These are not instantaneous peak guarantees or TTS-only allocations.
- Cleanup returned after interrupted playback and final End, with process footprints **117.7 / 119.3 MB**. This supports substantial resource release, not zero remaining native allocations. No claim of native-inference cancellation testing; the observed interruption occurred during playback.
- Capture stopped after feedback, owned logger 89264 terminated; supervisor exits with it. No ongoing observation. `phone-events.txt` and `phone-summary.json` retain content-free summaries.
- Offline connectivity and exact saved `playbackCompleted` fields were not independently observed or individually confirmed. Logs show a pause and fresh preparation, not a same-session automatic-resume pass. These remain qualification limits rather than invented passes; no private transcript/database export was taken.
- Retrieved v2 inventory is still byte-identical to the original inventory (`560f9b802cd85205c98ce90e11d8abc6b382fb587f9d2b581b37dcc288a0b808`, 29 files, 168,943,355 bytes), including malformed `tonic-3/` path prefixes. Thus the prior proposed path correction is **not phone-verified**. File-byte checksums remain recorded, but repair/revalidation of relative-path metadata is still needed before a final comparison/distribution report. No additional rehash or model changes were made during this accepted listening batch.

## Stage 4 compatibility gate - BLOCKED pending runtime choice

Rechecked [upstream issue #889](https://github.com/FluidInference/FluidAudio/issues/889) and all seven comments on September 20. It remains open. The maintainer confirms both CoreML routes can terminate the process on iOS 27; PR #902 updates warnings, not execution safety. The proposed Accelerate tail experiment lacks the requested sustained validation in the thread. The current pinned `KokoroAneManager.swift:128–142` still warns that no route is known safe. No relevant verified fix was established, and no Kokoro model was loaded.

Keep native Kokoro blocked. The plan requires an explicit choice before either adding the separate ONNX CPU runtime or performing a known-risk native diagnostic. Recommendation: retain the working Supertonic checkpoint and defer Kokoro unless a matched comparison is still wanted. Stage 5 sustained/comparison work and Stage 6 default promotion are not passed. Apple remains the relaunch default; Supertonic is selected explicitly in the test build.


## Voice picker follow-up - installed; listening BLOCKED by thermal guard

- User requested all available Supertonic voices in Settings. Added F1–F5 and M1–M5 using the pinned native voice enum, with M1 as the unset/invalid preference default. Selection persists across relaunch in UserDefaults. Backend selection still resets to Apple; no public-default promotion.
- Settings > Experiments > Supertonic voice is disabled during conversation, ASR work, speech or cleanup. Changing voice unloads the old selected manager via the existing drain gate; only the chosen voice is requested at explicit preparation. No new dependency, voice sweep, accent labels, ASR change or automatic audio.
- Selected identity now flows through downloader, synthesis style, UI, logs and comparison metadata. Inventories are per-voice v3 files; both root and files are canonicalized, and an out-of-root path fails visibly instead of recording incorrect relative paths. This also avoids reusing the stale M1-only v2 inventory. Actual phone v3 inventory remains unverified because heat blocked preparation.
- Three focused simulator UI tests passed: all ten options, F1 selection/relaunch persistence/M1 restoration; backend selection/Apple rollback; shared lifecycle/PCM including rejection of voice changes while busy. Screenshot visually checked with readable native rows. No neural simulator inference.
- Signed Release initially failed because the prior Mural provisioning profile expired at 20:49:57 local. Renewed via xcodebuild -allowProvisioningUpdates with unchanged team/bundle. Release build then passed, installed in place and launched normally. Executable SHA-256 `e781ced245f4b44b1c06929dedb718b4f61e858dd988c6b6209b9fdd63118a39`.
- Evidence: `.build/verification/tts/voice-picker-20260920-211015/`: tests.xcresult, screenshots, build-renewed.log, install/launch, source identity, bounded Mural-only log. Simulator shut down; capture stopped after feedback.
- User's first F1 Prepare & start showed the thermal-stop alert, not out-of-memory. At 21:23:16 and again after relaunch at 21:23:44, iOS thermal state was 2 (serious) and process samples were 79,939,520 / 82,151,336 bytes. No completed Supertonic preparation or synthesis event. No F1/M2 listening pass claimed. Safety threshold unchanged.
- Next: allow phone to cool, force-close/reopen to reset the latched stop, explicitly select Supertonic backend with F1, prepare/play, then End and select M2. No repeated full conversation suite. Start fresh scoped logging before that short check.
