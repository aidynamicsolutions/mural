# Automated local speech preparation checks

Date: 2026-09-22. Result: **bounded physical ASR checks passed; focused cancellation follow-up is complete and owner-accepted**. This is not complete Talk, hosted provisioning, language-quality or App Store acceptance.

Latest results: [accepted cancellation closeout](speech-setup-ux.md#accepted-cancellation-follow-up). Four subsequent physical cancellation/retry runs passed: post-install drain **19.315 s Breeze / 15.403 s PhoWhisper**, cached drain **1.538 s / 1.278 s**. The owner accepts the observed 15-19 second wait; do not reopen latency tuning as unfinished work. This is Cancel-to-drain, not total setup time: the first Breeze retry still took 141.030 s to finish skipped preparation. Eight simulator UI checks separately passed safe navigation, pair selection, closed admission and recovery.

## Local installer transaction fault tests (2026-09-23)

`Tests/SpeechInstallerTests.swift` now drives the shared installer transaction core against `URLProtocol` and disposable temporary directories. Package canonicalization and independent pins remain covered by `SpeechPackageTests`; the production entry point still validates the full catalog manifest before calling this core. No real network, published catalog entry, model weights, or user/device container is used.

Covered and passing:
- Exact byte ranges resume after a network loss, cancellation, and a fresh installer invocation; the final file is hashed before publication.
- A full-object `200` is accepted only for the complete initial range; ignored partial ranges remain rejected by the HTTP/package tests. Unreviewed redirects, truncation, encoded/oversized responses and cancellation are rejected or drained safely.
- Bad outer manifest pins and mismatched file hashes fail without replacing the old active package; the corrupt staged file is discarded.
- Insufficient space before transfer and simulated space loss between ranges preserve the current active pointer; retry resumes at the saved offset.
- A read-only staging file exercises a filesystem write-open failure without touching the active version.
- An injected interruption immediately before active-pointer publication leaves the old pointer and both immutable directories intact; a new installer invocation repairs the marker and switches the pointer without downloading again.

Verification: full `swift test` **62 passed**; ASR package tools **6 passed**; Core AI checks **16 passed**; targeted iPhone 17 Pro / iOS 27.0 simulator UI test `testTaiwanSpeechPackageUnavailableDoesNotStartOrSwitchModes` **1 passed**. Logs and xcresult: `.build/verification/speech-installer/20260923T025140Z/`.

Limits: restart and pointer interruption are deterministic in-process fault injections, not an actual process kill or kill during the atomic filesystem rename/write. Free-space loss is simulated, not real ENOSPC. The tests exercise the shared transaction core with synthetic small file plans, not a fully pinned production artifact, hosted CDN, backup failover or a genuinely clean install. P0 remains open.

## Safety monitor delayed-sample and lifecycle replay (2026-09-23)

`LocalConversationEngine.startTTSConversationMonitor` checks cancellation immediately after each asynchronous sample and before it updates the maximum or calls `stopForTTSSafety`. There is no suspension between that check and the safety action on MainActor, so Stop cannot interleave in that window. The detached `task_info`/logging sample itself is not cancellable and may finish after Stop; it is read-only, and a replacement monitor starts for the next preparation.

A controlled iPhone 17 Pro / iOS 27.0 simulator replay suspended an over-threshold sample, stopped the monitor, started a replacement monitor, then released the stale sample. It did not stop the replacement generation. A fresh injected 3 GB footprint and a current serious thermal state still invoked the safety stop. These are injected values through the actual monitor loop, not physical memory or thermal measurements.

Coordinator/UI regression checks passed: setup cancellation kept admission closed until the simulated drain, safe navigation and pair selection stayed available, background/retry did not start another owner, and the thermal warning required explicit Resume. At Accessibility XXXL text size, the cancel and consent flows remained reachable. Simulator evidence: `.build/verification/safety-monitor/20260923T102519/`; `safety-monitor-replay-final3.xcresult` **1/1 passed**, `coordinator-lifecycle.xcresult` **4/4 passed**.

Limits: no physical-phone or native inference lifecycle replay, real memory pressure/thermal excursion, scrolling profile, or VoiceOver spoken-announcement test was done. One-second sampling is sampled protection, not a hard memory ceiling; a transient peak can exceed the threshold between samples. The TTS experiment UI test emitted an internal QoS priority-inversion runtime warning despite passing; no cause was established. Xcode also reported existing LiveTransport async-alternative and iOS 27 AVAudioSession deprecation warnings.

The initial batch below is historical. Start an independent review with [consolidated findings](local-speech-findings-handoff.md) and the [updated next-agent prompt](local-speech-review-prompt.md).

## Why this check exists

Mac UI automation failed with `Not authorised to send Apple events to System Events (-1743)`. Rather than ask the owner to operate another checklist, `App/MuralApp.swift` now has a small `MURAL_LOCAL_QA` compile-time runner. It also requires the exact `com.kevintruong.mural.qa` bundle and `--local-speech-qa`. Ordinary builds omit it.

The runner calls the same `LocalConversationEngine.prepareConversation`, `stop`, admission gates, verified assets, Core AI specialization and Core ML receipt/load paths as Talk. It does not create the coordinator or learning store, record audio, synthesize speech, invoke a tutor, delete caches, override receipts, or substitute an ASR model. It selects the existing Apple-voice option in QA preferences to isolate ASR from neural TTS acquisition. Microphone/listening and full coordinator/background transitions are not proved by this runner.

The QA screen keeps itself awake while visible and restores the normal idle behavior when it disappears. iOS still requires one user unlock to launch the app; this is not a lock bypass. During this batch the owner supplied that single unlock.

## Initial physical results (before the cancellation follow-up)

Paired iPhone 17 / `iPhone18,3`, iOS 27.2 (`24B5084k`), free development signing. Exact reviewed model files were rehashed on the Mac and staged only into QA. This is **Mac-assisted native qualification**, not an in-app model-download test.

| Check | Result |
| --- | --- |
| Missing assets, both modes | Failed closed, no Ready/recording admission; retry admission restored after Stop. |
| PhoWhisper fresh QA cache | Normal path logged actual Core AI specialization begin/end and validated encoder/decoder; recovery preparation reached Ready in 27.741 s. |
| PhoWhisper native decoder-prewarm cancellation | Stop kept admission closed while native work drained for **19.495 s**. Log records `prewarm_failed status=cancelled`. No successful receipt write on the cancelled attempt. Immediate recovery reached Ready in **4.749 s**. |
| Breeze native prewarm cancellation | Stop kept admission closed for **195.051 s** until native work returned. Log records cancelled prewarm, not successful preparation. Recovery reached Ready in **6.143 s**. |
| Breeze fresh-process cached preparation, no intervening reinstall | **4.411 s**; subsequent same-process preparation **3.470 s**. Receipt hit skipped explicit prewarm; normal model loading still ran. |
| PhoWhisper fresh-process cached preparation, no intervening reinstall | **4.576 s**; subsequent same-process preparation **3.029 s**. Receipt hit skipped explicit prewarm; normal decoder loading still ran. |
| Force-kill and relaunch, both modes | Killed only the launched QA PID during asset verification, before its verification-end/Ready event. Fresh-process reruns passed both preparation/Stop iterations. Incomplete killed reports are not counted as passes. |
| Simulated sampled-memory guard, both modes | Calling the real 3 GB guard stopped models and rejected another preparation in that process. No 3 GB allocation, actual memory pressure, thermal stress or iOS memory-warning delivery was induced. Later fresh-process recovery passed. |
| Development reinstall | Receipt became incompatible and preparation reoccurred. Breeze's subsequent full prewarm took **149.448 s** (153.353 s total preparation). This does not contradict cached relaunch timings. |

**Historical finding:** the tested engine admission gates remained closed until cancelled native preparation drained, and recovery passed. This is bounded ownership evidence, not a blanket cancellation-safety or full-UI responsiveness pass. The idle-looking cancellation UI and missing per-component cancellation boundaries were subsequently corrected and verified as described in the accepted closeout above. The remaining observed drain is accepted; do not skip native load/validation to hide it. No production model/receipt behavior was changed in this initial batch.

## Storage measurements and limits

Measured app-container metadata every two seconds off MainActor, including Application Support, Caches, Documents and temporary files. Reported both logical sizes and `totalFileAllocatedSize`; neither is a transactional device-wide physical peak. Shared/APFS storage, external Apple caches and transient files missed between samples remain limitations.

- Reviewed staged inputs, including their manifests: Breeze **1,657,748,594 bytes**; PhoWhisper PAL8 support **1,655,767,545 bytes**; FP8 source/AOT encoder package **1,280,729,149 bytes**. Both modes were intentionally staged for this batch; this is not a selected-mode-only download.
- Initial PhoWhisper preparation/recovery: container logical bytes grew from **4,595,088,993** to a sampled maximum of **6,362,744,054**, settling at **5,372,303,939**. The sampled increase over baseline was **1,767,655,061 bytes**.
- Subsequent Breeze cancellation/recovery: baseline **5,372,298,126**, sampled maximum **6,496,989,477**, final **5,506,146,345** logical bytes. Incremental sampled increase **1,124,691,351 bytes**, with PhoWhisper caches already present.
- Later targeted PhoWhisper cancellation after reinstall sampled **6,631,450,960** logical / **6,631,837,696** allocated bytes for the combined QA container.

These are useful observed storage costs, **not an approved per-mode `specializationReserveBytes` value**. Independent single-mode hosted-install peaks plus headroom still need qualification. No storage was filled to exhaustion and no reserve was fabricated for the catalog.

## Run the check again

Discover the device first. Do not use the daily bundle. Create a temporary QA Info.plist from `App/Info.plist` with only its display name changed to `Mural QA`; leave the tracked plist untouched. With an available free-profile app slot and existing signing:

```sh
xcodebuild -project Mural.xcodeproj -scheme Mural -configuration Release \
  -destination "platform=iOS,id=$DEVICE_UDID" \
  -derivedDataPath .build/local-mvp-phase-1-device-derived-data \
  PRODUCT_BUNDLE_IDENTIFIER=com.kevintruong.mural.qa \
  INFOPLIST_FILE="$PWD/.build/verification/model-sources/QA-Info.plist" \
  OTHER_SWIFT_FLAGS='$(inherited) -D MURAL_COREAI_TALK -D MURAL_LOCAL_QA' build
```

Confirm built bundle ID/display name and actual compiler flags before installing with `devicectl`. The derived Release product now represents QA, not daily Mural. Never reinstall an unidentified product into the daily workflow.

```sh
xcrun devicectl device process launch --device "$DEVICE_UDID" --terminate-existing \
  com.kevintruong.mural.qa --local-speech-qa --qa-model=pho --qa-action=prepare

xcrun devicectl device copy from --device "$DEVICE_UDID" \
  --domain-type appDataContainer --domain-identifier com.kevintruong.mural.qa \
  --source Documents/local-speech-qa.json --destination "$EVIDENCE/report.json"
```

Supported model choices: `pho`, `breeze`. Actions:

- `missing`: use only before staging assets; expects the normal preparation failure.
- `prepare`: Ready -> Stop -> Ready -> Stop through the real owner.
- `cancel`: cancel during preparation, await native drain, then reprepare. PhoWhisper targets the decoder-validation progress phase; Breeze uses warming state. Always correlate logs to establish the actual native phase interrupted.
- `memory`: prepare, then inject the sampled-memory safety threshold and check restart rejection. Explicitly simulated, not a real memory benchmark.

Each launch replaces the report with a new run ID. Check model/action/run ID and `status`; an old report, `running` report, acknowledged launch, or timeout is not success. The runner requests cancellation after ten minutes but cannot forcibly interrupt non-cooperative native work. If it remains blocked, terminate only the freshly verified QA PID and report the limitation. Stop scoped log captures after the batch.

No automatic model staging/downloading wrapper was added. Use `devicectl device copy to` for the three reviewed export directories when native-only qualification is intended; retain their existing relative locations (`Library/Application Support/BreezeASR25/...`, `Library/Application Support/PhoWhisperCS/...`, `Documents/CoreAI/W8FullV3/packed/encoder-fp8`). Never copy daily learning data or native caches.

## Evidence and remaining gates

Private evidence: `.build/verification/local-speech-qa/`, especially individual `*.json` reports, `key-events.log`, `storage-summary.json`, source verification, build/install logs, executable identities, killed-process events and `qa-finished.png`.

Ordinary simulator build without the QA flag passed. The focused source/decoder policy checks passed **16/16**. Initially the test harness captured the appended QA helper as part of the decoder-policy source; moving the QA code to the existing app probe file fixed that test boundary without changing the policy/tests.

Still not proved here: customer download/resume/failover, actual low-storage failure, standalone per-mode reserve, a true cold device-wide Apple cache, cancellation inside the encoder specialization itself, actual background/foreground coordinator behavior, new microphone/TTS/tutor or mixed-language quality, and TestFlight/App Store execution. Retain prior human evidence rather than asking for it again without a new failure. Hosting and paid enrollment remain deferred as documented in [the release plan](model-distribution-release-plan.md).
