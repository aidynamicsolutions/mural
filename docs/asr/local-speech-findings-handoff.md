# Local speech findings and review handoff

Date: 2026-09-22. Repository: `aidynamicsolutions/mural`, branch `mvp`.

**Focused cancellation work is complete and owner-accepted; this is not a release approval.** The [accepted cancellation follow-up](speech-setup-ux.md#accepted-cancellation-follow-up) records the final implementation, four passing physical cancellation/retry runs, eight passing UI checks and installed daily build. The owner accepts the observed 15-19 second post-reinstall cancellation drain; further latency tuning is not the next task. Read that closeout for current source/executable identities and limits. Older native timings and UX descriptions below are historical. Remaining work is installer recovery, safety/lifecycle coverage, Taiwan language quality and release provisioning.

Next-agent instructions: [copy-ready review prompt](local-speech-review-prompt.md).

## 1. Three independent outcomes

| Deliverable | Established | Still open |
| --- | --- | --- |
| Receipt regression | Cached preparations reuse receipts while still verifying assets and normally loading/validating models. Physical QA recovery passed; focused cancellation improvements and the observed remaining drain are accepted. Receipt implementation/tests currently equal HEAD. | Full coordinator lifecycle and native cache-miss coverage. First-use/reinstall preparation may still be long; acceptance is not a total-startup-time bound. A receipt is not proof that an Apple cache still exists. |
| Taiwan Talk / Traditional Chinese | Explicit Breeze selection and pair persistence implemented. Prior human checks accepted basic English/Mandarin conversation, on-screen Chinese support and English speech. Host persistence tests passed. | A mixed-language recognition failure remains. Comprehensive Traditional Chinese meaning/script qualification, current physical accessibility and lifecycle checks are incomplete. |
| Clean-install provisioning / distribution | Installer candidate, package tools, trust/component tests, normal-path Core AI specialization and local HTTP/temp-filesystem transaction fault tests exist. A separately signed QA app installs and native preparation works with reviewed, Mac-staged assets. | **P0 remains open:** empty production catalog, no published exact converted packages, no implemented/qualified backup failover, no release storage reserve, no actual OS-process-kill/ENOSPC test, and no TestFlight/App Store clean-install evidence. |

Evidence labels used below:

- **Measured:** saved automated report or correlated native log from the named run.
- **Human-confirmed/reported:** prior owner feedback, not a new controlled audio benchmark.
- **Source-derived:** behavior follows the current code; a physical UI replay is still needed.
- **Review question:** a hypothesis or coverage gap, not a reproduced defect.

## 2. Preserve this checkout and the owner's phone

- HEAD is `3bae86c34072c088454afe5b235802a76b6e2c3b`. The Taiwan/provisioning candidate and local follow-ups are **uncommitted**. Source changes were staged externally during this documentation pass; the index was left untouched, and these latest documentation edits remain unstaged/untracked. Inspect `git diff HEAD` plus new files, not only the unstaged diff. No commit or push was made by this agent. An online agent checking out HEAD alone will not have this candidate; provide the reviewed working changes, including new files, separately from private evidence.
- Original delivery: `/Users/tiger/Downloads/mural-taiwan-talk-provisioning-handover.zip`; original extraction: `.build/handover/mural-taiwan-delivery/`. Do not reapply it to the already modified checkout.
- The initial guarded apply rejected edit 63 in `App/LibraryViews.swift`: an excerpt ended with an incomplete `ForEach(session?.topics ?? [])` context line. With owner authorization, only that malformed context suffix was repaired in a separate bundle copy. Original-blob guards were retained; 70 contexts across 20 existing files then applied. Original bundle and `.build/handover/mural-taiwan-delivery-context-repaired/` remain available. Evidence: `.build/verification/taiwan-talk-patch/20260922T043313501826Z/`.
- Daily app: **`com.kevintruong.mural.dev`**. Do not uninstall it, reset its data, delete its models/receipts or clear Apple caches. The native QA batch below did not alter daily Mural. The later UX follow-up installed new daily builds in place, preserving app data; its latest executable/install evidence is in `speech-setup-ux.md`.
- Disposable test app: **`com.kevintruong.mural.qa`**, displayed as **Mural QA**, using existing free development signing. The owner authorized removal of Full Moon (`com.kevintruong.fullmoon`) to free a three-app free-profile slot; that removal is complete. It is not permission to remove another app.
- The owner approved safe local fixes/tests, including justified receipt changes with a review record. The original receipt-freeze constraint is therefore not an absolute prohibition. Nevertheless, the relative-path experiment below was reverted; preserve receipt safety invariants if proposing another change.
- Automate what does not require speech/listening. Do not spawn tester subagents. Ask for only one short human batch if new audio/semantic evidence is actually needed, with logging ready first.
- Hosting and paid Apple Developer enrollment are explicitly deferred. Do not invent endpoints, publish packages, spend money, change the signing team or grant Mac automation permissions silently.

### Code snapshot for an independent reviewer

The original, now superseded, documentation-independent snapshot was taken under `.build/verification/taiwan-handoff/20260922-152637/`:

- `tracked-source.diff`: `git diff --binary HEAD -- App Core Tests UITests Tools`, SHA-256 **`ebdd7a0998b850276c2abce8c76a0f9b5bc951f398f2ad93657a5e949b6d1f72`**. This diff alone excludes untracked files.
- `changed-source-files.sha256`: sorted current-file hashes for 22 changed/new files in those directories, including untracked source/tests/tools; inventory-file SHA-256 **`e2b1c59bb3d20bdfe333097fdd285cf5978f83455205152d5011041f746e83e1`**.
- These identify the handoff code state, not a commit, package trust pin or independently reproduced build. They exclude documentation. Read the actual new files as well as the tracked diff.

## 3. Physical configuration and trust identities

Last tested hardware: **iPhone 17 / `iPhone18,3`**, **iOS 27.2 (`24B5084k`)**. Toolchain recorded during this work: Xcode 27.0 (`27A5252f`), Swift 6.4. Rediscover the actual paired device and tools before the next run; do not signal historical PIDs.

- Vietnamese: PhoWhisper CS, staged **Core AI GPU-preferred FP8 encoder + Core ML PAL8 decoder**, decoder-only receipt scope.
- Taiwan: Breeze PAL8 through WhisperKit/Core ML, eager receipt scope, one recognizer for the complete turn.
- Preserve the local build flag `MURAL_COREAI_TALK`, but verify actual compiler and runtime selection. The current `PhoWhisperStagedEncoder.enabled` is true when Core AI is available, including ordinary Release. Older verification notes saying ordinary Release is necessarily baseline are historical and conflict with current source. Do not infer backend from the model name or flag alone.
- Native QA explicitly selects the existing Apple voice setting to isolate ASR preparation. It does **not** run speech synthesis. These results do not qualify Supertonic acquisition, tutor coexistence or audible output.

| Identity | Fixed value |
| --- | --- |
| Breeze source revision | `cffe7ccb404d025296a00758d0a33468bec3a9d0` |
| Breeze inner manifest SHA-256 | `64021fb776ee2ef4cf02c05b2a9dafde0e0700e9bf7d967b4bc5302558b5fdb4` |
| PhoWhisper PAL8 support inner manifest SHA-256 | `430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336` |
| PhoWhisper packed FP8 encoder inner manifest SHA-256 | `73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13` |

These are **inner** identities, not missing whole-package distribution pins. Keep precision, compute settings, support inventory and tokenizer unchanged unless conducting a separately approved and qualified model experiment. In particular, the pinned support package still needs its duplicate Core ML encoder files under the existing load contract.

Final QA executable SHA-256: **`d7b90d684420499e260ed160a2a5347fd9e9b80c84fe5f004e4e335b9a221594`**. Evidence: `.build/verification/local-speech-qa/executable-final.sha256` and final build logs. Earlier Breeze cancellation/warm checks used earlier diagnostic-helper builds, not this final executable; the native preparation/model/receipt paths were unchanged between those helper revisions. Do not assign the final executable hash retroactively to every run.

## 4. Finding C1: historical native cancellation baseline

**Current status: focused fix complete, observed residual wait accepted.** Per-component cancellation now prevents following work, safe navigation and next-pair selection remain usable, and conflicting speech admission stays closed until drain. Latest post-install drain was 19.315 s for Breeze and 15.403 s for PhoWhisper; cached runs were 1.538 s and 1.278 s. See the [accepted closeout](speech-setup-ux.md#accepted-cancellation-follow-up) for recovery costs and evidence. No more latency work is required absent a new regression or owner request.

**Historical measurements before that fix.** The automated runner cancelled the preparation task, called the real engine's `stop()`, checked that recording/preparation admission remained closed, awaited the native work, and then prepared again. The correlated logs place cancellation inside native prewarm, not merely before it.

All reports in this table are under `.build/verification/local-speech-qa/`. Times are individual observations, not averages or promised bounds.

| Case | Native prewarm duration | Cancel request to drain | Recovery Prepare to engine Ready | Evidence |
| --- | ---: | ---: | ---: | --- |
| Breeze native prewarm | 195.739 s, ended as cancelled | **195.051 s** | **6.143 s** | `breeze-cancel.json`, run `B91C239C-9CD7-4148-880F-A8AADAE252CB`, `key-events.log` |
| PhoWhisper native decoder prewarm | 19.580 s, ended as cancelled | **19.495 s** | **4.749 s** | `pho-native-cancel.json`, run `4DF0EC4F-F239-4E87-BE93-0738DB2E8929`, `key-events.log` |
| PhoWhisper early preparation cancellation | Not inside decoder prewarm | 0.034 s | 27.741 s, including fresh specialization/preparation | `pho-cancel.json`; **not** evidence of fast native cancellation |

Raw monotonic event times, seconds:

| Model | `cancel-requested` | `cancel-drained` | Recovery begin | Recovery Ready |
| --- | ---: | ---: | ---: | ---: |
| Breeze | 335966.8146644167 | 336161.86614783335 | 336161.91798929166 | 336168.060504375 |
| PhoWhisper decoder | 336385.9471195417 | 336405.44214450003 | 336405.47192929167 | 336410.2204604167 |

At the cancellation event, reports show `busy=true`, `canPrepare=false`, `canRecord=false`. At drain, `busy=false`, `canPrepare=true`, `canRecord=false`. Native logs show `prewarm_failed status=cancelled`; the cancelled attempts did not write a successful preparation receipt. Recovery performed preparation/normal validation and wrote a receipt after success.

**What this proves:** the tested engine owner did not reopen these admission gates before native completion, and subsequent preparation recovered. **What it does not prove:** full Talk UI responsiveness, prompt OS resource reclamation, no late audio in all phases, general race freedom, or that no supported native cancellation improvement is possible. The helper does not instantiate the conversation coordinator, tutor, learning store or microphone.

### C2: cancellation feedback and safe controls corrected

**Original source-derived finding.** Before the [setup UX follow-up](speech-setup-ux.md), the path was:

1. `TalkView.localTurnButtons` in `App/RootView.swift` keeps **End** available during preparation.
2. `ConversationCoordinator.endLocal` cancels tasks and calls `localAudio.stop()` without awaiting native completion. It keeps the pending worker represented in busy state while it drains.
3. With **no learner message**, the draft is discarded and the coordinator moves to `.idle`. Its status becomes **“Prepare to talk on this iPhone”** even while `localResourcesBusy` remains true.
4. **Prepare & start**, speech-pair/mode selection, speech-model management and the diagnostic probe remain disabled until the owner drains. The preparing progress indicator disappears because it is shown only for `.preparing`.
5. With an existing learner message, the session stays ended and status already says **“Finishing local work…”** while busy, or the separate assessment status. Transcript remains available; **New conversation** is gated. Do not describe every End path as having no feedback.
6. Tabs and the Settings entry are not globally disabled by this code. Actual navigation/frame responsiveness during the long native operation still needs verification.

**UX impact in plain language:** End can stop the requested conversation without being able to instantly stop the iPhone's model-setup operation. The app must wait before starting another speech job. In the observed native cases that wait was about **3 minutes 15 seconds** for Breeze and **20 seconds** for PhoWhisper. An idle-looking screen with a disabled start button can make a learner think the app ignored them or broke. This is not evidence that the entire phone or screen freezes for that duration.

**Current correction:** **Setup cancelled** replaces the spinner, explains the current native step is finishing, and allows Words, Settings and next-pair selection. Start, mode changes and the probe remain gated until drain; pair selection does not start a model. Eight simulator UI checks passed with recorded transitions. Four separate native ASR-owner cancellation/retry runs passed. These complementary surfaces do not prove full phone UI responsiveness, VoiceOver, every coordinator/audio phase or a maximum native wait. The focused task is owner-accepted with those boundaries.

Preserve the safety rule: do not unlock on a timer, nil the owner early, detach untracked native work, skip validation, add a second recognizer, or force-exit the app as a shipping cancellation strategy. The wrapper waits for an in-flight call to return; no claim is made that all supported native cancellation options have been exhausted.

## 5. Finding R1: receipts help, but do not guarantee once-per-install setup

**Measured cached reuse:**

| Mode | Fresh process, retained assets/receipts, no intervening reinstall | Next preparation in same process |
| --- | ---: | ---: |
| Breeze | 4.411 s | 3.470 s |
| PhoWhisper | 4.576 s | 3.029 s |

These are engine Ready times, not full Talk button-to-greeting/audio times. Logs show receipt hits, zero explicit prewarm on hits, and normal loading still occurring. Full asset verification remains authoritative.

**Rejected experiment:** development installation changed the sandbox/model path while retaining assets and a receipt. With the owner's approval, a temporary storage-root-relative path identity and policy version 2 were tested. After an in-place reinstall of the same executable, lookup hit and explicit prewarm was skipped, but normal Core ML loading still took **177.693 s before cancellation**. Immediate retry reached Ready in **4.628 s**. The experiment did not eliminate the native cost and was reverted.

The result is consistent with native preparation being needed despite a durable receipt, but does not identify Apple's internal cache key or prove reinstall was the sole cause. It is not proof that every relative-path design is unsafe. Any new proposal must measure total verification/prewarm/normal-load/Ready cost and preserve correctness, not celebrate receipt hits alone.

**Current state:** `Core/CoreMLPreparationReceipt.swift` and `Tests/CoreMLPreparationReceiptTests.swift` match HEAD; policy version 1 and absolute standardized model-path hash remain. Actual runtime compute values, manifest, OS build, device, scope and policy are still in the key. Staged scope covers only the decoder. Trials must retain their own always/once and no-auto-rebuild behavior.

The later QA development reinstall produced an incompatible Breeze receipt and **149.448 s** explicit prewarm, **153.353 s** total preparation. A fresh app process is therefore not interchangeable with a fresh installation.

**Do not promise “only once in the app's lifetime.”** Reinstallation, artifact/path/compute-policy changes, OS changes or missing native caches can require preparation again. A normal relaunch with compatible retained state is the fast case measured above. An injected cache miss is not evidence of an actual OS upgrade.

Evidence: `.build/verification/taiwan-talk/20260922-113707/receipt-relocation-*-key-events.log`, plus native QA warm/memory reports and logs.

## 6. Finding Q1: smoother UI, safety-monitor replay complete with native limits

The owner reported Taiwan scrolling/orb stutter. The local follow-up moved synchronous memory sampling/logging off MainActor and changed the conversation-wide polling interval from 100 ms to 1 s in `LocalConversationEngine.startTTSConversationMonitor`. The owner reported smoother behavior afterward. This is human-confirmed improvement, not a before/after animation capture or profiling proof of the only cause.

**Review result:** the post-sample cancellation guard is present before any sampled footprint update or safety action. The check and `stopForTTSSafety` run synchronously on MainActor, so Stop cannot interleave between them. A controlled simulator replay suspended an over-threshold sample across Stop/restart, started the replacement monitor, and released the stale sample. The stale result did not close admission or stop the replacement. A fresh injected 3 GB footprint still stopped memory admission; a current serious-thermal state still stopped speech and notified its owner.

**Coordinator/accessibility review:** `localResourcesBusy` covers the setup/resume task, audio ASR/TTS, tutor/support work, final assessment, managed downloads and staged decoder drain. Pause/Resume awaits the previous coordinator task before preparing again. Simulator UI checks passed for cancelled setup drain/admission, pair selection/navigation, background/retry, thermal pause/explicit resume and Accessibility XXXL consent/cancel reachability. Evidence and exact result bundles are recorded in [local speech QA](local-speech-qa.md#safety-monitor-delayed-sample-and-lifecycle-replay-2026-09-23).

**Remaining limitations:** the detached sample is read-only but not cancellable and can finish after Stop while the next monitor has started. No physical native inference teardown/reprepare replay, real memory-pressure or thermal event, scrolling profile, sustained thermal/battery qualification or VoiceOver spoken-announcement test was performed. The 1-second sample interval is not a hard ceiling; transient footprint peaks can exceed the threshold between samples. The TTS experiment UI test passed with an internal QoS priority-inversion runtime warning whose cause is not established. Do not present injected `3_000_000_000` fields as measured memory use.

## 7. Finding L1: mixed Mandarin/English fidelity still fails

**Human-reported failure:** in the supplied mixed test, a Mandarin linking phrase was rendered as its English translation rather than preserving the spoken language span. Repeated owner attempts showed the same issue. Pure Mandarin and basic English checks were accepted separately. No matching recorded waveform was retained for a controlled replay, so exact causal attribution to audio, decoder or conversion is unproven.

Keep raw recognition independent from display trimming and generated teaching. Do not normalize script, translate recognizer output, inject expected words or switch individual words to PhoWhisper to make the test appear to pass. The same Breeze actor currently owns each complete Taiwan turn. Typed input must have no fabricated ASR provenance.

Traditional Chinese teaching quality is a separate gate: broad owner acceptance is not a comprehensive contextual-meaning audit. A prior support example also raised a contextual word-sense concern; investigate with a small synthetic phrase set rather than copying personal transcripts into Git. Keep English practice speech English and Chinese Help on screen. Taiwan automatic learning credit remains disabled; do not enable it to close a checklist.

Next useful test is a small, consented reusable synthetic corpus with independently reviewed expected language spans and Taiwan usage, scored on raw ASR and teaching separately. Automate replay where practical. A competent Traditional Chinese reader is still needed for nuanced meaning; do not request the whole original phone checklist again.

## 8. Finding P1: original online models are not our converted iPhone packages

See [model sources and release plan](model-distribution-release-plan.md) for repository revisions, license obligations, HTTP results and primary/backup TODOs.

- Upstream Hugging Face inventories and representative ranged files were reachable. The full VAD weight was downloaded and verified. Sample reachability is not full-package or failover qualification.
- The exact locally converted Breeze PAL8 and merged PhoWhisper PAL8/Core AI FP8 exports were not found in the bounded community search. Original training weights cannot be substituted for these conversions. This is not proof that no public identical export exists anywhere.
- Reuse publisher hosting when exact accepted bytes are available; use an owned byte-identical backup. Locally converted files need an approved primary host too if no identical public copy exists. Hosting protects availability, not ASR accuracy.
- The current installer has one manifest/files source. Ordered primary/backup failover is **planned, not implemented**. Dependency registry overrides are not automatic failover.
- `Core/SpeechPackageCatalog.swift` is deliberately empty. Missing catalog entries must remain unavailable, not simulate a completed install. Do not download a trust pin from the metadata it should authenticate.
- VAD, selected neural TTS assets/voices and Apple system tutor/voice prerequisites belong in first-use accounting. Apple OS-managed assets must not be mirrored.
- The owner will supply R2/S3 details later. Paid developer enrollment is needed later for intended distribution, not for current free-signed local QA. Neither missing dependency excuses skipping available local failure tests.

Reviewed export locations for later local work, reverify before use:

```text
/Users/tiger/tmp/mural-breeze/phone-assets/breeze-asr25-pal8-v1
.build/verification/coreml-preparation-lifecycle/20260922-073130/restore-layout/PhoWhisperCS/phowhisper-cs-pal8-g16-v1
.build/verification/coreml-preparation-lifecycle/20260922-073130/restore-layout/packed/encoder-fp8
```

Do not redistribute until provenance and all required notices/licenses have been reviewed. No model package was uploaded during this work.

### P2: installer and storage evidence is still incomplete

Real CryptoKit hashing and disposable-filesystem checks now supplement URLProtocol HTTP tests. They reject wrong hashes/truncation/extra files/symlinks and cover the active-pointer helper's missing-directory rejection. A Foundation URL alias comparison bug found by those tests was fixed using standardized absolute paths. These checks do not prove the full install pipeline, immutable-directory publication or process-death recovery.

Remaining automatable checks include end-to-end disposable installation, old/new version replacement, loss of network/cancel/resume at several offsets, HTTP 200 versus 206 safety, unapproved redirects, simulated ENOSPC/write errors, failed directory/pointer publication and kill between directory and pointer publication. Use a test-only HTTP/filesystem seam; do not add a shipping trust-pin override or put fixture URLs in the production catalog. Never corrupt a valid user installation for testing.

Native QA recorded normal-path Core AI specialization begin/end from the exact staged FP8 artifacts, followed by successful preparation. This narrows the original missing-specialization blocker, but is **not** proof of a device-wide cold cache, cancellation inside specialization, after-Ready cache eviction, customer downloads or TestFlight behavior.

Storage observations:

- Staged inputs including manifests: Breeze **1,657,748,594 B**, PhoWhisper support **1,655,767,545 B**, packed FP8 export **1,280,729,149 B**.
- Initial PhoWhisper sampled container logical growth above baseline: **1,767,655,061 B**. Subsequent Breeze growth: **1,124,691,351 B**, with Pho caches already present.
- Later combined QA container sampled maximum: **6,631,450,960 logical B / 6,631,837,696 allocated B**.

Both modes were staged, samples were every two seconds, and external Apple caches/transient peaks are not fully counted. These are **not** qualified single-mode `specializationReserveBytes` values. See [native QA storage limits](local-speech-qa.md#storage-measurements-and-limits). Do not derive disk reserve from the 3 GB RAM guard.

An earlier built Release payload measured **39,336,213 logical B** with no recognized model-file suffix found. This is not an archive audit, compressed IPA size, App Store thinned/download size or definitive binary scan. No complete distribution archive/export gate has passed.

## 9. Changes that the next agent must review

Review the entire working candidate, not only the new helper. Main boundaries:

| Area | Current change / review focus |
| --- | --- |
| `Core/LocalSpeechPair.swift`, `Models.swift`, `Languages/LanguageModule.swift`, `MeaningController.swift` | Explicit pair, legacy Vietnamese default, per-session support language, raw recognition provenance and pair-aware meaning/cache behavior. |
| `App/ConversationCoordinator.swift`, `LocalTutorModel.swift`, `RootView.swift`, `LibraryViews.swift` | Selection/admission, single audio/tutor ownership, Taiwan on-screen support, history/edit/archive behavior and learning-credit guard. C2 is fixed and the focused cancellation work is accepted; preserve safe pair selection without starting another owner. |
| `App/BreezeEnglishRecognizer.swift`, `LocalConversationEngine.swift` | Fixed Breeze pin; full-turn routing; pre-Ready validation and normal-path Core AI recovery; cancellation/actor isolation; monitor follow-up Q1. |
| `Core/SpeechPackage.swift`, `SpeechPackageCatalog.swift`, `LocalSpeechProvisioning.swift` | Canonical metadata, independent pins, compatibility/path/file validation, resumable transfers, publication/recovery and safe deletion boundaries. Catalog intentionally empty. |
| `App/MuralApp.swift` | New ASR-only runner behind `MURAL_LOCAL_QA` plus exact QA bundle and launch argument. Ten-minute watchdog requests cancellation but cannot preempt native work. No normal learning-store creation in runner mode. Inspect exclusion from ordinary builds. |
| `Tests/LocalSpeechPairPersistenceTests.swift`, `SpeechHTTPTests.swift`, `SpeechPackageTests.swift` | New persistence/meaning, HTTP and real hash/filesystem component coverage; do not overstate integration coverage. |
| `Tools/ASR/`, `Tools/CoreAI/test_asr_final_review.py` | Package/archive tools; existing 16-check harness adapted to extract the new native-source boundary and stub managed resolution. Receipt code/tests are unchanged. QA helper was moved out of the engine file rather than weakening decoder-policy tests. |
| `UITests/MuralUITests.swift` | Taiwan unpublished-package regression and explicit preference cleanup to prevent contamination of later preview tests. |

No new third-party dependency, App project reference, project regeneration or tracked signing change was needed.

## 10. Completed checks and evidence limits

Host commands recovered from the actual run:

```sh
swift test
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tools/ASR -p 'test_speech_package_tool.py'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest Tools.CoreAI.test_asr_final_review
git diff --check
```

- Full host batch before the QA-only runner: **92 XCTest + 44 Swift Testing = 136 Swift checks**, **6 ASR package checks**, **16 Core AI final-review checks**, passed. Includes the five newly supplied persistence/meaning tests. Rerun relevant tests after any new correction; this is not a claim the full suite was repeated after every helper edit.
- Simulator native UI: seven distinct checks eventually passed, including onboarding/consent, ended-session handling, meanings/history, explicit thermal resume, a settings large-text check and Taiwan unpublished-package handling. An initial subtitle check failed after an idle timeout, then passed unchanged in isolation; root cause remains unresolved. An initial batch command timed out after test logs completed. Keep that evidence instead of calling the suite flake-free.
- A real test-state leak was fixed: the Taiwan test left On-device in preferences and affected a later premium preview. Restoring GPT-Live in cleanup made the paired rerun pass.
- Native QA: **11 completed reports** for missing assets, warm preparation/reuse, early/native cancellation, synthetic safety and post-kill recovery. Killed/incomplete reports are not passes. Force-kills occurred during **asset verification**, not during inference or specialization.
- Latest helper follow-up: physical Release QA build and ordinary simulator build without the QA macro passed; Core AI final review **16/16** passed again.
- Mac physical-input automation was blocked by `Not authorised to send Apple events to System Events (-1743)`. The ASR-only runner avoided spending the owner's time on repeated taps. One owner unlock was needed. It is not a substitute for full coordinator/UI/audio transitions.

### Evidence map (private, do not commit)

| Directory | Contents / limitation |
| --- | --- |
| `.build/verification/coreml-preparation-lifecycle/20260922-073130/` | Prior receipt baseline and reviewed Pho exports; predates this candidate. |
| `.build/verification/breeze-preparation-lifecycle/20260922-085236/` | Prior Breeze receipt baseline; not Taiwan Talk acceptance. |
| `.build/verification/taiwan-talk/20260922-113707/` | Feature builds, user-check logs, receipt relocation experiment and private UI/audio-related evidence. |
| `.build/verification/taiwan-automated/` | Host tests, simulator results, initial failures and reruns. Its earlier QA-signing blocker was subsequently resolved; read later install/native reports too. |
| `.build/verification/model-sources/` | Source inventories, bounded HTTP checks and temporary QA Info.plist. |
| `.build/verification/qa-install-20260922-143213/` | Owner-approved QA installation and preserved daily-app metadata. |
| `.build/verification/local-speech-qa/` | Per-run JSON, native key events, storage samples, build/install logs, executable hashes and scoped capture ownership/cleanup. |
| `.build/verification/taiwan-handoff/20260922-152637/` | Historical handoff changed-source inventory and tracked-source diff identity. |
| `.build/verification/speech-cancellation/20260922-1742/` | Final cancellation source inventory, build/install/launch identities, four native reports, UI recordings and test logs. |
| `.build/verification/speech-cancellation/accepted-closeout/` | Fresh 27-test cancellation/progress/receipt regression check and acceptance closeout. |

The last native batch stopped its owned Mural-only capture and returned QA to a normal launch without diagnostic arguments. Staged test assets remain in QA. No continuing test/capture is promised. Rediscover processes before any cleanup. Keep raw transcripts, recordings, device identifiers, private captures and model binaries under private ignored storage, not in Git or a remote-agent prompt.

## 11. Recommended next work, without wasting owner time

1. Treat C1/C2's focused cancellation fix and observed 15-19 second residual drain as accepted. Do not repeat reinstalls, reimplement the old spinner proposal or tune latency without a new regression or owner request.
2. **Local installer transaction tests completed:** disposable HTTP/filesystem tests cover range resume, cancellation/network failure, integrity failures, simulated storage/write errors, immutable-directory publication, pointer-boundary interruption and old-version retention. Details and limits are recorded in [local speech QA](local-speech-qa.md#local-installer-transaction-fault-tests-2026-09-23). They do not prove real OS process-kill, actual ENOSPC, hosted delivery or customer clean install.
3. Q1 delayed-sample replay and simulator coordinator/accessibility checks are complete. No stale sample stopped a replacement monitor; current synthetic memory/thermal stops remained active. Physical native teardown, real memory/thermal qualification, scrolling profiling and spoken VoiceOver remain unverified.
4. The owner explicitly deferred mixed-language recognition investigation. Preserve the known finding and do not investigate or request audio under the current scope.
5. No further local installer or safety-monitor code action is currently authorized or required. The owner has parked TestFlight/App Store clean-install qualification until they are ready to enroll in the paid Apple Developer Program. Do not request enrollment or start distribution qualification before they say so. Keep the P0 release gate open; when resumed, complete enrollment/configuration and owner-approved hosting/artifact prerequisites, then qualify hosted delivery, licenses/notices, per-mode reserves and a production-signed TestFlight clean install. Independent local QA remains separate. Report receipt and provisioning outcomes separately; language quality remains a documented, owner-deferred limitation.

Required output from the next agent: findings by evidence level, a scoped fix or justified limitation per issue, commands/build identities, before/after timing tables, remaining tests/blockers and the smallest concrete owner action still needed. A credible partial result is better than a false P0 completion.
