# Investigation: iOS memory warning during Taiwan/Breeze Talk

**Status: OPEN / STOP.** A real iOS memory-warning notification interrupted a Taiwan/Breeze conversation on Kevq. The workload is a likely material contributor, but the logs do not prove it was the sole cause. The unexpected presence of two `LocalConversationEngine` warning handlers is unresolved. Two owner-requested sequential Vietnamese-then-Taiwan runs were completed on 2026-09-25; neither produced a logged warning. The second began after an app-container wipe and showed cold app-owned caches, but neither run proves native deallocation or clears the original incident. Do not repeat native ASR preparation on this device until engine ownership and the memory peak have been reviewed.

This is an investigation record, not a fix or an acceptance claim. The checklist progress fix is separate and does not address memory or engine lifetime.

## Incident

- Device: iPhone 17, identifier `kevq`; daily Mural development bundle `com.kevintruong.mural.dev`.
- Build: the existing-signing Release build installed in place. No app was removed, no app data/cache/receipt was cleared, and no backend or model was changed.
- Flow: Taiwan Mandarin-English (`zh-TW-en`), `Breeze TW-EN (test)`, setup job `46BBF7AA-8EA9-49EA-A6A9-7801B2A0485E`.
- At device-local 14:10:04 on 2026-09-25, UIKit logged `Received memory warning.` in the Mural dev process. Mural then ran its ASR memory-warning handler, stopped local speech, and the coordinator surfaced the message in the `A little interruption` alert.
- This was a real OS notification, not a checklist/progress state or an alert fabricated by the setup UI. The app did cause the visible alert in the sense that its safety handler translated the OS notification into an app error and the root view displayed it.

## Owner-reported test sequence and hypothesis

The owner recalls that the test started with Vietnamese selected and its Whisper-family ASR prepared. They then switched the support language to Traditional Chinese and pressed **Prepare & start**, which selected the Taiwan Breeze path. The owner suspects the earlier Vietnamese ASR stayed resident while Breeze loaded, contributing to memory pressure.

This is useful firsthand context, but the filtered incident log has not yet been correlated against the full sequence. The exact first model/backend should be confirmed from content-free `local_talk_model_selected` and `asr_ready` events. In the current production coordinator, Vietnamese selects `.phoWhisper` and Taiwan selects `.breeze`; the owner's phrase “Whisper model” is recorded as reported, not treated as proof of the exact loaded implementation.

The requested invariant for review is: **only the ASR model needed for the currently selected local language pair should remain actively resident; switching pairs should drain and release the previous ASR before preparing the next one.** Keep the verified on-disk packages and their security contracts. Do not solve this by deleting caches, weakening receipts/validation, changing the selected model or precision, or allowing a second preparation owner.

Current source already tries to enforce reference-level exclusivity inside one engine: `canPrepare` requires the recognizer fields to be empty, `selectASR` calls `stop()`, and `stop()` nils the engine's recognizer fields. The coordinator also calls `stop()` when resetting a local conversation before a supported language-pair change. That does not prove native memory has been reclaimed before the next model load, nor does it prevent a separate `LocalConversationEngine` instance from retaining another model. `stop()` logs that release was requested, including whether work is still draining; it is not itself evidence that an opaque native allocation is gone. The distinction between one model reference, one process-wide engine owner, and actually released native memory must be checked before proposing code changes.

## Follow-up: bounded Vietnamese-then-Taiwan preparation run

On 2026-09-25, the owner requested one physical-device sequence to test whether preparing Vietnamese and then Traditional Chinese reproduced a warning. The test used Kevq's existing `com.kevintruong.mural.dev` Release 0.1.0 (1) install and one Mural process (PID 65747). No rebuild, reinstall, app-data/cache/receipt clearing, user audio input, or tutor-generation step was requested. The Mural log did record one `greeting` event after Vietnamese setup; it recorded no recognition event or Foundation Models tutor event.

- At 15:28:51, the app prepared pair `vi-en`, model `PhoWhisper CS`, job `820DC1AF-E6FD-4328-A0C3-72EC5785FE3E`. It reached ASR Ready and validated setup at 15:28:55. Encoder cache was a hit. No memory warning was logged.
- The owner tapped End. At 15:33:58 the app logged `asr_owner_release_requested model=PhoWhisper CS draining=false assets_retained=true`. `LocalConversationEngine.stop()` clears the recognizer references, and the log indicates no ASR task or staged decoder warmup was active. This is evidence of Swift-owner release, not proof that Core AI/Core ML or accelerator allocations were physically reclaimed.
- At 15:35:27-15:35:31, the same process prepared the Taiwan path, model logged as `Breeze TW-EN (test)`, job `A48D263C-468B-440F-A87C-1823D0CD5BC5`. It reached ASR Ready and validated setup at 15:35:31. The logged load duration was 2.886 seconds. The process-wide current footprint was about 81 MB before load, 204 MB at `load-begin`, 2.047 GB at `load-end`, and peaked at 2.049 GB in sampled current-footprint readings at 15:35:32. The process-lifetime footprint peak field reached 2.096 GB; the logged process RSS peak field was 1.360 GB. These are separate process-wide metrics, not per-model allocations. The current footprint reading fell to about 187 MB by 15:37:37; thermal state remained nominal (`0`).
- The Mural-only log contained no `Received memory warning` or `asr_staged_memory_warning` event during this sequence. The app remained on the same PID. This single no-warning run does not prove the sequence cannot cause a warning under different system pressure, nor that the first model's native memory was fully deallocated. The second model's load itself did coincide with a large transient process-wide footprint increase. The previous incident also included a Foundation Models tutor creation while Breeze was resident, which this run did not test. The only `greeting` event was after the Vietnamese setup; no recognition or tutor-generation event was logged during the Taiwan model load.

**Interpretation:** this run does not reproduce the prior warning and gives some evidence against a large PhoWhisper allocation remaining in the app-accounted footprint after End. It cannot rule out native/accelerator caches or prove exclusive native residency. It does show a substantial transient footprint during Breeze preparation even without the tutor step, so Breeze loading remains a plausible contributor to overall pressure. Keep the original warning and duplicate-handler ownership anomaly open; do not claim the model-switch hypothesis is disproved or that memory safety is qualified.

Content-free event summary is retained locally at `.build/verification/asr-model-switch-investigation/20260925T082441Z/progress.md`. The raw `mural-only-device.log` is private local evidence and must not be attached or dumped into a review. No screenshot, user audio, transcript, app data, or model assets were retained or changed for this test.

## Follow-up: fresh app-container sequential preparation

The owner approved wiping Mural's app data and requested a reinstall to exercise both ASR models without app-owned caches. Only `Mural` (`com.kevintruong.mural.dev`, Release 0.1.0 build 1) was uninstalled; no other app was touched. Its old app and data containers changed after reinstall. The same already-signed executable was installed in the same bundle identity (SHA-256 `2ce12a53880300f9e921b1d5428830ac8665723a283f66b0e4370b5b4999a7e8`). Conversations, preferences, model files and receipts in the old app container were erased as approved.

Because the production speech-package catalog is empty and the exact converted ASR artifacts are not hosted, the test could not fetch the ASR models from a clean install. Before uninstall, only the three verified model inputs were copied to private local staging and restored afterward: PhoWhisper PAL8 support (manifest `430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336`), packed Core AI FP8 source/AOT (manifest `73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13`), and Breeze PAL8 support (manifest `64021fb776ee2ef4cf02c05b2a9dafde0e0700e9bf7d967b4bc5302558b5fdb4`). Every support-file hash/size and the Core AI source/AOT fingerprints passed. Receipts, Core AI runtime cache, user data and other app-owned caches were not restored. This is a fresh app-container/native-preparation test, not a hosted first-use download qualification or proof that iOS-wide caches were empty.

Both language stages ran in fresh Mural process PID 66614:

- Vietnamese job `ACC88913-2517-468F-B6C0-B86A80F81232` reached validated Ready at 18:15:41. Core AI logged `speech_encoder_cache result=miss`, then specialization begin/end. PhoWhisper's Core ML receipt was `missing`; prewarm took 15.803 seconds, load took 0.186 seconds, and a new receipt was written. The setup log reported 25.948 seconds preparation. The full app-data wipe also caused voice assets to be downloaded/reprepared, so this was not an ASR-only cold-start path.
- After End, PhoWhisper logged `asr_owner_release_requested ... draining=false` at 18:22:18. Current whole-process footprint was about 101 MB. This is consistent with no large app-accounted allocation remaining, but is not proof that framework or accelerator allocations were released.
- Taiwan job `3C11FCD1-E5C9-4417-9CED-07C111B3086B` began at 18:23:39 and reached validated Ready at 18:26:35. Breeze's Core ML receipt was `missing`; a fresh prewarm took 171.878 seconds, followed by a 2.469-second load and a new receipt. The ASR log reported 175.665 seconds preparation. Mural again requested PhoWhisper release before the Breeze work, with `draining=false`.
- During Breeze preparation, whole-process current footprint was 208,947,328 bytes at prewarm begin, 820,939,048 bytes at prewarm end and 2,046,527,856 bytes at load end. Maximum sampled current footprint was 2,095,712,624 bytes. The process-lifetime footprint peak field reached 2,105,166,264 bytes; process RSS peak was 1,370,619,904 bytes. Thermal state became fair (`1`). At 18:27:04 the current footprint had fallen to about 193 MB.
- After End, Breeze logged `asr_owner_release_requested ... draining=false` at 18:28:22; current footprint was 110,332,248 bytes. No `Received memory warning` or `asr_staged_memory_warning` event appeared in the Mural-only capture through release. No user speech, transcript, or tutor-generation step was requested.

**Interpretation:** the requested fresh app-owned-cache sequence did not reproduce the warning. PhoWhisper's measured app footprint was low after End before Breeze preparation, which weighs against a large PhoWhisper allocation remaining in ordinary process footprint; it cannot rule out native/accelerator caching or prove the old model was fully deallocated. Breeze preparation by itself still produced a transient process-wide footprint above 2.1 GB and fair thermal state. This supports Breeze loading as a material pressure contributor, but not the theory that both ASR models were simultaneously resident. The original incident also included Foundation Models tutor creation and two warning observers, and system memory conditions differ between runs. Keep the original warning and ownership anomaly open.

Content-free summary: `.build/verification/asr-model-switch-cold-reinstall/20260925T105810Z/result.md`. The Mural-only raw log is private ignored evidence; do not attach or dump it into review. Temporary staged model copies were deleted after verifying restoration to the phone; manifest pins, byte totals and verification status remain in the local result. The log capture was stopped after the release event.

## Relevant sequence and measurements

1. 14:04:51: Taiwan pair selected and setup job started.
2. 14:05:18: encoder preparation was interrupted while foreground was required. At 14:09:38 the cancelled prewarm drained after 266.513 seconds; the same setup owner rechecked and continued.
3. 14:09:43-14:09:46: Breeze Mel, TextDecoder, and AudioEncoder load completed. `process_validated` and `ready` were recorded at 14:09:46.
4. 14:09:57: one Breeze decode completed.
5. 14:09:58: Apple's on-device Foundation Models 3B tutor path began model creation while the Breeze recognizer remained resident.
6. 14:10:04: UIKit delivered the warning. The Breeze engine's previous state was `Ready to record`; no decoder prewarm was active.

Memory samples from the Mural process:

| Sample | Bytes | Approximate size |
| --- | ---: | ---: |
| Breeze load-end footprint | 2,134,853,928 | 2.135 GB / 1.988 GiB |
| Process lifetime footprint peak | 2,178,320,728 | 2.178 GB / 2.029 GiB |
| Footprint at warning | 1,981,205,064 | 1.981 GB / 1.845 GiB |
| Process RSS peak | 1,363,116,032 | 1.363 GB / 1.270 GiB |

Footprint and RSS are different metrics and must not be conflated. Thermal state was `1` (fair), not serious. The Mural process remained listed after the warning and no Mural crash/termination appeared in the process-filtered log slice. Because capture was Mural-only, this does not establish that no system Jetsam event occurred.

## Unresolved ownership anomaly

Two `asr_staged_memory_warning` handler records followed the same notification:

- Breeze: previous state `Ready to record`, footprint sample about 1.981 GB.
- PhoWhisper: previous state `Prepare speech models`, footprint sample about 114.9 MB.

`LocalConversationEngine.init` registers one warning observer per engine instance, and its `deinit` removes that observer. This supports the conclusion that at least two engine instances were alive when the warning was delivered. It does **not** prove that two native model sets were loaded, that both were actively preparing, or that the PhoWhisper instance materially caused the warning. Several `local_talk_asr_backend` initialization notices also appeared in this process; their ownership/lifetime relationship has not been established.

A separate Mural QA app was installed, and a later process listing showed two Mural-named processes. The warning capture only identified the dev process, so QA activity and its contribution at the warning time are unknown. No app was removed or stopped for this investigation.

## Assessment

The timing strongly supports Mural's ASR/tutor workload as a material contributor: the warning followed validated Breeze readiness and a decode, occurred while the large Breeze recognizer was resident and Apple's on-device tutor model was being created, and the Mural process had reached a 2.178 GB footprint peak. It is not possible to claim sole causation from a process-filtered log because iOS memory pressure depends on total system state and no system-wide memory trace was captured.

The app's sampled 3.0 GB safety guard is not the same thing as an iOS warning. The observed OS warning arrived with the logged footprint sample below that threshold, so the guard did not prevent this warning. Sampling is not a hard memory ceiling and cannot prove the absence of a transient higher peak.

## Next-session investigation, before any mitigation

1. Preserve the current post-test app container, model assets, native caches and receipts. Do not clear data, remove apps, change ASR backend/precision/compute, or repeat native preparation without a reviewed hypothesis.
2. Keep both 2026-09-25 sequential runs distinct from the earlier warning incident. Correlate the earlier incident's content-free model-selection, ASR-ready, owner-release, drain and warning events, and confirm what “Whisper model” meant in that original run. Neither new run establishes the earlier process's engine/model ownership.
3. Trace every `ConversationCoordinator` and `LocalConversationEngine` construction path, including `RootView` state lifetime, app/scene recreation, retained callbacks, and teardown. Correlate instances with content-free stable engine/coordinator IDs and observer-registration/removal events if additional logging is approved.
4. Explain why two engine warning handlers and several backend-initialization notices were present. Confirm which instance owned Breeze, which reported PhoWhisper state, whether either had active native work, and whether old owner references drained. Do not infer that two models were loaded from callbacks alone.
5. Review pair switching and the recognizer release path. Establish whether `stop()` only clears Swift references or whether the WhisperKit/Core ML native resources actually leave the process before the next pair is prepared. Also review the serialized `LocalTutorModel` path and whether Foundation Models creation overlaps the Breeze peak.
6. If an owner-approved repeat is later justified, use a bounded, content-free physical capture with phase-aligned footprint/RSS, native stage and actor/engine lifetime events, OS warning events, and relevant system memory evidence. Record baseline, selected pair/backend, active owners, thermal state, and whether the tutor model was requested. Stop immediately on another warning, crash, Jetsam, overlapping native work, or ambiguous ownership.
7. Only after root cause is supported should a mitigation be proposed. Evaluate explicit release/lifetime or sequencing options against normal load/validation, cancellation drain, reuse, and conversation behavior. Preserve the selected model, precision, tokenizer, compute placement, package pins, validation and no-fallback rules unless a separately reviewed qualification authorizes a change.
8. Add a regression check for the demonstrated ownership/release failure mode once the owner model is understood. Existing state/control tests do not prove native engine teardown or device memory safety.

## Evidence and source references

### Incident evidence (local, ignored verification artifacts)

Directory: `.build/verification/phone-smoke/20260925T065239Z/`.

- `memory-warning-report.md`: sanitized incident summary, timeline, figures and limitations.
- `result.md`: bounded physical smoke outcome.
- `mural-only-device.log`: raw process-filtered device log. Treat as private; filtering by process is not a guarantee that every line is free of user content. Inspect only narrow warning/job/engine/memory events, and do not attach or dump the whole file into a report.
- `source-snapshot.txt`: source/build identity captured for the run.
- `release-build.log`, `install.log`, and `launch.log`: local build/install/launch evidence; private signing and device artifacts in this directory should remain private.

### Related validation evidence

- `.build/verification/speech-setup-checklist/20260924T164806Z/core-tests-darwin.log`: Darwin Core suite for the checklist progress regression.
- `.build/verification/speech-setup-checklist/20260924T164806Z/checklist-ui-final.log` and `checklist-ui-final.xcresult`: focused simulator UI run; the progress regression and conversation handoff passed 2/2.
- `.build/verification/speech-setup-checklist/20260924T164806Z/after-checklist.mov` and exported transition frames: visual checklist inspection. This is simulator UI evidence, not native-memory qualification.
- Earlier resumable setup portable tests and their limits are recorded in `docs/asr/background-speech-setup-implementation-status.md`. Passing Core/simulator tests do not explain the second warning handler or prove that native model memory was released.

### Current code locations

Line numbers refer to `local/resumable-speech-setup-qualification` at the time this issue was written and may move.

- `App/LocalConversationEngine.swift:530-553`: backend-init log and per-instance `UIApplicationDidReceiveMemoryWarningNotification` observer; handler logs memory, stops the engine and calls `onTTSSafetyStop`.
- `App/LocalConversationEngine.swift:556-562`: observer removed in `deinit`.
- `App/LocalConversationEngine.swift:448-453`: recording/preparation admission; `canPrepare` requires the recognizer references to be nil. `App/LocalConversationEngine.swift:661-678` logs release requested, cancels current work, and clears recognizer references while retaining downloaded assets. `App/LocalConversationEngine.swift:789-814` drains setup work and selects/prepares the requested conversation model. `App/LocalConversationEngine.swift:875-883` switches the selected ASR by calling `stop()` before changing the model.
- `App/ConversationCoordinator.swift:9-20`: coordinator owns `localAudio` and the setup controllers. `App/ConversationCoordinator.swift:263-272` routes the safety stop to `endLocal` and publishes the error. `App/ConversationCoordinator.swift:400-431,563-582` starts preparation and selects `.phoWhisper` for Vietnamese or `.breeze` for Taiwan. `App/ConversationCoordinator.swift:840-875` ends local ownership and stops the engine. `App/ConversationCoordinator.swift:933-947,1206-1222` changes the support language and resets the local conversation when it is safe to do so.
- `App/RootView.swift:5-20`: coordinator is created and retained in SwiftUI `@State`. `App/RootView.swift:42-44,70-72` displays the error as `A little interruption` unless it is the thermal alert.
- `App/BreezeEnglishRecognizer.swift:90-124,147-169,222`: Breeze preparation, CPU/Neural Engine choices, receipt/prewarm/load validation and release logging. This source does not establish the cause of the memory peak.
- `App/LocalTutorModel.swift:8-20,95-134`: Foundation Models availability and session-generation path (`LanguageModelSession`); the incident log records the Apple 3B model creation at 14:09:58.
- `App/VietnameseEnglishRecognizer.swift:101-115`: existing content-free process footprint/RSS/thermal sampler and its distinction between current footprint and process-lifetime peaks.
- `App/ConversationCoordinator.swift` also owns `localTutor`; `docs/asr/taiwan-talk-implementation-plan.md` describes the intended shared serialized local tutor and one audio owner. Verify actual construction/lifetime rather than treating that design statement as runtime proof.

### Related project records and constraints

- `docs/asr/speech-setup-checklist-regression-plan.md`: the checklist fix and its physical STOP status. It records that phone UI-order acceptance is inconclusive and the progress fix does not resolve this memory issue.
- `docs/asr/background-speech-setup-plan.md`: single-owner/drain principles and the mandatory stop condition for memory warnings, crashes/Jetsam or overlapping owners.
- `docs/asr/background-speech-setup-implementation-status.md`: resumable setup is not automatically an accepted feature; native stages remain foreground-only pending qualification.
- `docs/asr/taiwan-talk-implementation-plan.md`: Taiwan/Breeze path, tutor/audio ownership intent, and boundaries for native preparation and receipts.
- `docs/asr/speech-setup-ux.md`: earlier scoped physical memory samples had no warning in those runs. Those bounded observations are not a safety guarantee and do not supersede this real warning.
- `docs/asr/local-speech-qa.md`: earlier simulated memory-guard evidence and explicit limits; it did not induce a real iOS memory warning.
- `docs/asr/README.md`: memory-model and prior diagnosis overview; consult before changing sampling or safety policy.

Useful Apple documentation to re-check during the investigation: UIKit's `UIApplication.didReceiveMemoryWarningNotification`, Foundation Models' `SystemLanguageModel` and `LanguageModelSession`, and MetricKit's `MXMemoryMetric`. Documentation and instrumentation can guide a future approved diagnosis; none replaces the incident evidence or proves device-specific causality.

## Merge/acceptance note

The reviewed resumable-setup handoff explicitly lists any memory warning and duplicate/overlapping owner as a mandatory STOP. Do not describe this feature as accepted or physically qualified, and do not treat a successful build or simulator test as closure of this incident. Any local squash decision must keep this issue visible and explicitly preserve the unresolved STOP.
