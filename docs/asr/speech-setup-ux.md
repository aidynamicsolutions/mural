# Speech setup UX: implementation and verification

Date: 2026-09-22. Branch: `mvp`. **Focused cancellation work complete and owner-accepted; not a clean-install release approval.**

## Accepted cancellation follow-up

The owner accepts the observed roughly **15-19 second cancellation wait after development reinstall** and requests moving on. No further latency tuning is required for this focused task. These are individual Cancel-to-drain observations, not a maximum wait, complete first-use setup time or an App Store clean-install result.

### Implemented behavior

- `Core/SpeechPreparationStep.swift` checks cancellation before and after each native component call, preserves caller isolation, and records content-free phase timings. `CancellableWhisperModel` wraps WhisperKit's existing loading interface for Breeze and PhoWhisper without changing decoding, tensor contracts, tokenizer, precision or compute choices.
- Cancel stops subsequent components after the in-flight native call returns. A late SDK error cannot start the voice fallback or another ASR preparation after cancellation. Completed assets remain reusable; cancelled preparation cannot falsely mark itself Ready or write a success receipt.
- Talk acknowledges **Setup cancelled** without a stopping spinner. It explains that speech is finishing its current step. Words, Settings and the next language-pair selection remain usable; choosing a pair does not start its model. Prepare, mode changes, diagnostics and other conflicting speech work stay gated until the existing owner actually drains. No automatic restart or late greeting.
- Receipt implementation/tests still match HEAD. No model pins, dependencies, signing settings or production catalog entries changed for this fix.

### Physical results from the completed session

Private evidence: `.build/verification/speech-cancellation/20260922-1742/`, especially the four JSON reports, `native-summary.json` and `key-events.log`. Device: iPhone 17 / `iPhone18,3`, iOS 27.2 (`24B5084k`). QA used the real ASR owner with staged assets and Apple voice selected, not actual speech synthesis.

| Case | Interrupted step | Cancel to drain | Retry to engine Ready |
| --- | --- | ---: | ---: |
| Breeze after QA development install | Decoder prewarm | **19.315 s** | 141.030 s |
| PhoWhisper after QA development install | Decoder prewarm | **15.403 s** | 4.282 s |
| Breeze cached fresh process | Decoder normal load | **1.538 s** | 3.559 s |
| PhoWhisper cached fresh process | Decoder normal load | **1.278 s** | 3.336 s |

All four reports passed. Recording/preparation admission stayed closed at cancellation and reopened only after drain. Breeze did not start the encoder on the cancelled attempt; its first retry still paid the skipped encoder preparation cost. The earlier 195.051-second Breeze result is a historical baseline, not a controlled speedup comparison. This fix avoids unwanted following work; it does not remove first-use setup cost or forcibly interrupt the current Apple call.

Sampled footprint maxima were 2,030,127,304 / 249,169,904 / 1,917,159,432 / 1,240,729,512 bytes in table order. Process-lifetime footprint peaks were 2,032,486,600 / 1,328,449,544 / 1,919,502,344 / 1,326,892,992 bytes. Thermal samples were nominal/fair; no app memory-warning or safety-stop event was recorded in those scoped samples. Sampling is not a hard memory bound or sustained thermal qualification.

### Verification and deployment closeout

- Prior session: **147 Swift checks** (92 XCTest + 55 Swift Testing), **6 package-tool checks**, **16 Core AI checks**, and **8 simulator UI checks** passed. The UI cases cover consent/automatic continuation, cached/failure recovery, cancellation with safe navigation/pair selection and closed admission, background/retry, large text, unavailable catalog and the existing thermal fixture.
- Saved simulator transitions were recorded and inspected, not inferred from settled screenshots: `after.mov`, `cancel-precise.jpg`, `cancel-detail-frames.jpg`, `pair-detail-frames.jpg`, and `large-text.mov` / `large-text-cancel-frames.jpg`. Closeout re-inspected those sheets, including pair-menu changes during drain and large-text cancel/background transitions. Largest text requires scrolling. This is simulator evidence, not native phone frame-responsiveness or VoiceOver qualification.
- Final daily and QA Release builds passed. Daily **`com.kevintruong.mural.dev`**, Release 0.1.0 (1), was installed in place and launched in the prior session, preserving data. Actual daily compiler flags include `MURAL_COREAI_TALK` and exclude `MURAL_LOCAL_QA`; the saved launch event confirms the staged Core AI backend. The earlier setup-only logging blocker was resolved for this batch. This launch is not a new spoken-turn test.
- Daily executable SHA-256: `9425d80989f7116d296c4ad50ae98276ba1ee3ecd8b62387b2a88a9b160fbc8e`. Final QA executable: `dd9de8896483fbc9b3053de0e7b279393de328eb28df3ea5ac5cb99433d6fb90`. QA helper builds changed during the batch; do not assign its final hash retroactively to every physical run.
- HEAD: `3bae86c34072c088454afe5b235802a76b6e2c3b` plus preserved working changes. `tracked-source-final.diff` SHA-256: `e59a2a322c98935ae617a590fc2a718450816583f0ec4d875ccc925daf28a119`. The 27-file `changed-source-final.sha256` inventory, including untracked source/tests, hashes to `9e61b5cf84587a8d4aaa71b7cfd51207b58170353c7ce949bd80b5f1894fa130`.
- Closeout confirmed all 27 source/test/tool files and the tracked diff still match that verified snapshot. Fresh `swift test --filter 'SpeechPreparationStepTests|SpeechSetupProgressTests|CoreMLPreparationReceiptTests'`: **27 passed**. Log: `.build/verification/speech-cancellation/accepted-closeout/focused-core.log`. No new app code, rebuild, reinstall or phone replay was needed for this documentation closeout.
- Prior scoped capture and all three recorders are stopped; the verification simulator was shut down. Closeout confirmed the saved capture/recorder PIDs are no longer running. Existing staged/unstaged/new work was preserved; no commit, push or publication.

### Remaining work, separate from accepted cancellation latency

1. Local installer fault/recovery tests are complete: HTTP range resume, cancellation/network loss, bad pins/files, simulated storage/write failure, immutable publication, pointer-boundary recovery and old-version retention. See [local speech QA](local-speech-qa.md#local-installer-transaction-fault-tests-2026-09-23). Hosted/customer clean-install qualification remains separate.
2. Safety-monitor and simulator coordinator/accessibility replay is complete. A delayed over-threshold sample could not stop a replacement monitor; current injected memory/thermal samples still stopped speech. Setup drain/admission, background/retry, thermal Resume and Accessibility XXXL consent/cancel checks passed. Physical native teardown, real memory/thermal qualification, scroll profiling and VoiceOver speech remain unverified; see [local speech QA](local-speech-qa.md#safety-monitor-delayed-sample-and-lifecycle-replay-2026-09-23).
3. The owner explicitly deferred mixed Mandarin/English recognition and Traditional Chinese quality work. Preserve the known limitation; do not investigate it or request audio under the current scope.
4. Keep [P0 provisioning](app-store-model-provisioning-release-blocker.md) open. TestFlight/App Store clean-install qualification is parked until the owner says they are ready to enroll in the paid Apple Developer Program; do not request enrollment or start distribution work before then. Hosting is separately deferred. When resumed, complete exact hosted packages, approved primary/backup sources and failover, independent pins, license/notices review, per-mode native disk reserves and intended clean-install verification. Independent local QA may continue but does not close the release gate.

No additional owner testing is required to close this focused cancellation task. Do not reopen it merely because historical paragraphs below describe the superseded spinner or 195-second result.

## Original setup-only checkpoint (historical)

The remaining sections record the earlier setup UX implementation and its original build/evidence. The accepted follow-up above supersedes their cancellation wording, current build identity and logging status.

This follow-up replaced the technical model-management detour with a learner-facing setup flow. It did not publish model packages, change model precision or qualify Taiwan recognition. See [the P0 blocker](app-store-model-provisioning-release-blocker.md) and [prior findings](local-speech-findings-handoff.md).

## What the learner sees

- Choose the on-device language combination, then **Prepare & start**. No separate Download / Manage Speech Models button on Talk.
- If recognition, Mural Voice or speech-detection files are missing, ask for download consent. Show reviewed recognition-package bytes and its storage allowance when available. Voice/detection sizes are explicitly unknown in this build, not included in a misleading total. Recommend Wi-Fi and disclose mobile-data use.
- **Download & continue** proceeds through download, verification and native preparation without requiring a second Start tap. **Not now**, sheet dismissal and Cancel discard the empty draft, not a conversation from history.
- A compact cream/yellow card shows the current stage. Managed recognition downloads use verified received-byte counts. Mural Voice uses the SDK's download fraction, without inventing byte counts. Native preparation and verification are indeterminate, not an estimated percentage or countdown.
- Cancel acknowledges immediately with **Stopping speech setup… / You can start again when this finishes.** Start, pair/mode changes and the diagnostic probe stay blocked until the existing owner actually drains. Safe navigation is not globally disabled.
- Friendly setup errors remain on Talk; retry uses Prepare & start. Detailed native errors, identities and timings remain inside **On-device details & diagnostics**.
- Optional **Settings > Downloaded speech** removes only managed recognition downloads for the selected pair, after confirmation and only when idle. It does not remove voice assets, developer-staged models, receipts, Apple caches, settings or learning history.
- Large text wraps the language selector and puts storage labels/values on separate lines. Setup has a smaller orb and omits the premature greeting caption so Cancel and diagnostics have room above the tab bar. Cancel and Not now have tested minimum 44-point accessibility frames. The existing Talk state animation respects Reduce Motion.

## What Prepare & start actually does

1. Validate the selected learning/support pair and system tutor availability. Apple manages its own tutor assets; Mural does not download an Apple language model here.
2. Check existing recognition manifests and the SDK's voice/detection cache inventory. This is an existence preflight, not validation or proof of readiness.
3. When recognition is missing, obtain the selected pair's independently pinned catalog metadata. An empty catalog fails closed with an actionable unavailable message. It does not switch languages/backends or pretend installation succeeded.
4. Ask for consent if files are missing. Metadata checks can happen before consent; the managed model transfer starts only after approval. Native loading remains authoritative.
5. Download and verify **only the selected recognition package**, if needed, through the existing installer. Wait for that worker and its actual completion/error.
6. Run the existing audio owner's preparation: acquire the chosen Mural Voice/style if missing and initialize it, then fully verify/load/prepare the selected ASR, including its existing speech-detection setup. Apple voice skips the Mural Voice acquisition. These phases are sequenced, not two simultaneous ASR/TTS downloads. Individual SDK transfer implementation remains upstream-owned.
7. Only after required preparation succeeds, append/speak the English greeting. Record remains unavailable until speech/support work has finished.

Receipts still skip only the matching explicit prewarm. Full file verification and normal native loading remain authoritative. A receipt does not prove that an Apple specialization cache exists. The existing explicit Mural Voice-to-Apple fallback policy is unchanged; no new fallback was introduced.

Backgrounding an empty first-setup draft cancels setup and leaves an explicit retry notice. Foregrounding does not silently restart its download. Existing conversations with learner text keep their previous pause/restore behavior. Restored-session preparation also receives the friendly native progress stages.

## Change boundaries and review points

- `App/ConversationCoordinator.swift`: one setup owner, consent continuation, user-facing errors, empty-draft background handling and observable stopping state. Session/pair admission and late-result checks remain in the existing coordinator.
- `Core/LocalSpeechProvisioning.swift`: adds an awaitable completion/error boundary over the existing worker. Parent cancellation cancels that same worker and waits for it; it does not release admission early. Package pins, HTTP rules, hashing and publication implementation are unchanged by this UX follow-up.
- `Core/SpeechSetupProgress.swift`: small value type separating learner-facing progress from diagnostic text. Only downloading stages accept percentages; native stages reject even supplied fractions/byte counts.
- `App/LocalNeuralTTS.swift` and `App/LocalConversationEngine.swift`: cache preflight and existing SDK progress callbacks, plus native stage updates. No backend, model, compute, decoding, VAD decision policy or receipt change.
- Monitor review Q1: a cancellation guard now rejects a detached memory sample **before** applying `stopForTTSSafety`. This closes the source-identified stale-result application window. A deliberately delayed native monitor replay is still unperformed; the one-second sampling cadence is unchanged and not a hard RAM ceiling.
- `App/RootView.swift` and `App/LibraryViews.swift`: progress/consent/storage presentation, large-text layout and a corrected Settings description that uses the session's actual support language instead of hardcoded Vietnamese.
- Receipt source and tests still equal HEAD. No project regeneration, new App file references, dependencies, signing configuration edits or production URL/pin overrides.

### Test-only seam

`--preview --preview-speech-setup=download|cached|failure|drain|unavailable` is compiled only with **DEBUG and simulator**. It uses temporary preview learning records and drives the real coordinator's consent, cancellation, session and admission logic. Simulated transfer/native work uses no model, network, microphone or personal data. The unavailable case exercises the real empty catalog without requiring an Apple tutor on Simulator.

**The fixture's 64 MB download, 128 MB storage allowance, 1 GB available space and 10-second non-cooperative delay are synthetic UI inputs, not package sizes, storage measurements or phone timings.** Its Ready screen is not native ASR readiness. No test URL or pin enters the shipping catalog. This seam is not compiled into the installed Release.

Existing FluidAudio voice/VAD loaders still own their cache validation/recovery and source policy. This patch does not qualify their live network failure paths, independently pin their full distribution inventory or prove that a cache-existence check can prevent every upstream repair download. Total first-use sizing, precise consent/recovery under corrupted SDK caches and distribution review remain release work.

## Automated results

Private evidence: `.build/verification/speech-setup-ux/20260922-1604/`.

| Check | Result / boundary |
| --- | --- |
| `swift test` | **141 passed**: 92 XCTest + 49 Swift Testing checks. Includes five new progress/awaited-installer tests, existing receipt tests and Taiwan persistence/meaning tests. |
| `swift test --filter SpeechSetupProgressTests` after cleanup | **5 passed**. Native progress cannot advertise a fake fraction; byte fractions and SDK-only fractions are bounded; empty catalog errors and waiter cancellation propagate. |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tools/ASR -p 'test_speech_package_tool.py'` | **6 passed**. |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest Tools.CoreAI.test_asr_final_review` | **16 passed**, including repeat after logic cleanup. |
| New/updated simulator UI checks | **6 passed together**: consent/decline/automatic continuation, missing catalog/retry without mode switch, cached startup, controlled failure recovery, cancellation with locked admission/no late session, background without automatic download restart, and largest text-size consent. Some cases share a test. |
| Existing thermal UI regression | **Passed**, safe injected fixture, not real heating. |
| Final focused UI replays | Drain + largest-text checks passed after selector correction; drain + consent passed again with 44-point hit-area assertions after final touch-target correction. |
| Simulator / physical Release builds | **Passed**. Existing interruption-deprecation, LiveTransport async-alternative and missing-AppIntents warnings remain; no new build warning identified. |
| `git diff --check` | Passed. |

The first UI batch had two assertions fail in the combined cached/failure test because the confirmation sheet did not advance after its tap. Evidence showed the sheet still present, not an installer error or late Ready. Tests now wait explicitly for confirmation presentation before tapping; the complete six-test rerun and later continuation replays passed. Retain the initial failed xcresult rather than calling every attempt green. This is evidence of the successful replays, not a universal flakiness guarantee.

Simulator: verification-owned iPhone 17, iOS 27.0 (`24A5423a`). Builds/tests used `Mural.xcodeproj`, scheme `Mural`, Debug, explicit simulator destination, `.build/taiwan-automated-derived-data`, `CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`, and `-parallel-testing-enabled NO`. Full commands/results are in the evidence logs. No physical native models are used by these UI tests.

### Visual evidence and limits

- Recorded and decoded `setup-transitions.mov` (238.34 s), `setup-final.mov` (359.207 s) and `setup-accessibility-final.mov` (159.32 s), with bounded verification-owned recorder processes. First recording exposed the initial card/tab-bar crowding and narrow accessibility storage columns; both were corrected.
- Inspected consent presentation/dismissal and actual percentage-to-verification-to-native-to-stopping changes, not just settled screenshots: `setup-final.mov` at 215.5-219.5 s (8 fps) and 219.5-222 s (12 fps), plus the 205-240 s context. Saved contact sheets are `consent-download-frames.jpg`, `native-to-stopping-frames.jpg` and `selected-drain.jpg`.
- Percentage disappears during verification/native setup, cancellation replaces the action with stopping feedback, and admission stays closed through the controlled drain. No transient text clipping seen in those inspected card/modal frames. The card naturally changes height between different stages; this is not a claim that every element is stationary.
- Largest-text controls are scrollable and reachable. A further selector wrapping correction was built and the corresponding UI tests passed. VoiceOver spoken announcements, explicit Reduce Motion runtime replay, all orientations and physical native-work responsiveness remain unverified.
- Serve-sim's accessibility bridge returned HTTP 503; XCTest drove the interactions instead. UI tests and simulator recordings do not establish phone audio, native cancellation latency or language quality.

## Installed build and evidence identity

- Source HEAD: `3bae86c34072c088454afe5b235802a76b6e2c3b` plus preserved staged candidate and these unstaged/new changes. No commit/push, reset, staging changes, model transfer, receipt change or user-data reset.
- Daily bundle: **`com.kevintruong.mural.dev`**, Release 0.1.0 (1), existing Apple Development signing. Installed in place on freshly rediscovered **iPhone 17 / `iPhone18,3`, iOS 27.2 (`24B5084k`)**. The final install did not steal foreground from the owner's other app.
- Executable SHA-256: `d2ad6f2f8d7f61c371ae2181a0077311df8ce2a5664f909b1ce30aab4847b2c3`.
- `tracked-source.diff` SHA-256: `9acbac2ca95a1ecc0fff0124448d0f39544e6cfea6cef8cb7ca543d861978dbe`.
- `changed-source-files.sha256` inventory SHA-256: `1d88a16a1f1dcbb79994698fccb7beb918e06767766b69e50b592c45e6b0375c`. This 25-file source/test/tool inventory includes new untracked files; the tracked diff alone does not. Both exclude documentation.
- Toolchain: Xcode 27.0 (`27A5252f`), Swift 6.4. Actual app compiler invocation retained `-D MURAL_COREAI_TALK`, without the QA/preview flag. Source still selects staged Core AI when available and Breeze only for Taiwan; no backend selector changed.

Exact physical build shape:

```sh
xcodebuild -project Mural.xcodeproj -scheme Mural -configuration Release \
  -destination "platform=iOS,id=$DEVICE_UDID" \
  -derivedDataPath "$PWD/.build/taiwan-talk-device-derived-data" \
  PRODUCT_BUNDLE_IDENTIFIER=com.kevintruong.mural.dev \
  OTHER_SWIFT_FLAGS='$(inherited) -D MURAL_COREAI_TALK' build
```

Final build/install evidence: `device-deployed-build.log`, `install-final.txt`, `daily-final.txt`, `executable-deployed.sha256`. Initial launch succeeded before the final layout refinements. No new native preparation or spoken turn is claimed for the final executable.

**Phone logging was blocked in this batch:** scoped USB `idevicesyslog` reported device not found; the network attempt failed to connect to lockdownd (`-8`). Both owned captures stopped. No broad device archive was collected. A screen capture showed another foreground app, not Mural, and was discarded rather than retained as unrelated personal content. There is no new runtime backend/preparation/timing proof for this executable. Restore a working scoped connection before requesting measured native timing checks. Device Hub was not running; the simulator mirror and owned simulator are stopped after validation.

## Release status and smallest phone check

Three independent outcomes remain:

1. **Receipts:** unchanged, host regression tests pass. Prior measured native cold/hit/reinstall findings remain applicable as historical evidence, not new timings.
2. **Taiwan Talk / Traditional Chinese:** setup UX improved and automated at the coordinator/UI boundary. The prior mixed-language fidelity failure and semantic/phone qualification gaps remain open.
3. **Clean-install provisioning:** app-side Start orchestration implemented, but **P0 remains open**. Catalog is empty. Exact converted packages, approved public primary/backup hosting, independent whole-package pins, measured native disk reserves, complete installer/native recovery tests and intended TestFlight/App Store clean-install evidence are still required. No paid account or hosting was requested merely to finish this UX task.

When convenient, open daily Mural and do one normal **Prepare & start**. Check that stages are readable and the greeting/Record appear as before. Optionally Cancel during preparation, wait for stopping to finish, and retry. Already-staged files should not show a download consent dialog; do not remove them to force one. No repeat of the entire speech/translation suite is needed for this UI review. Native cancellation may still take minutes after a cold preparation/reinstall; this change makes the wait visible, not shorter.
