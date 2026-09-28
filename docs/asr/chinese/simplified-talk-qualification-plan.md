# Simplified Chinese-English Talk: implementation and physical qualification plan

## Current checkpoint

**Status: offline preparation and model-free runner extension in progress; FireRed native continuation remains blocked.**

Source checkpoint: `b3013a0` on `mvp`, including the Simplified Chinese candidate from `45caaf3` and the new qualified physical E2E workflow. This plan does not inherit Vietnamese/Core AI qualification as FireRed qualification. The September 28 progress entry records offline trace inspection, selected MELI downloads and a signed model-free runner build. No new phone runtime, fixture playback, FireRed load or provisioning implementation has occurred.

User decisions:

- Prefer speech from speakers born and raised in mainland China, with natural Mandarin-English switching. Check Simplified Chinese writing separately from accent and spoken language.
- Use MELI as the primary corpus instead of ASCEND, subject to clip/reference review.
- Reuse the installed Mural and MuralUITests-Runner identities. No fourth app, new QA bundle, uninstall or deletion of personal data/model caches.
- Automate physical UI/acoustic checks using the existing native runner. Use interviews for readiness and focused listening/language feedback, not repeated manual navigation.
- Fresh-install-capable model downloading remains a required implementation goal. On this phone, qualify an empty managed FireRed installation without erasing the existing app. Do not call that a literal clean installation.
- Phone availability and the audible window must be reconfirmed before runtime; earlier readiness was deferred. No room-audio recording is authorized.

## Sources of truth

- [Physical E2E lessons](../../physical-iphone-e2e-lessons.md), read in full when preparing this plan.
- [Physical E2E plan](../../physical-iphone-e2e-plan.md) and [verification skill](../../../.agents/skills/verify-mural/SKILL.md#qualified-opt-in-native-local-workflow): existing commands, ownership and qualified mechanisms.
- [Candidate checkpoint](simplified-talk-candidate.md): source/build/UI evidence and exact FireRed model source.
- [Memory investigation](firered-memory-investigation-20260920.md) and [qualification](firered-aed-qualification.md): STOP disposition and continuation conditions.
- [Pinned native recipe](../../../Tools/ChineseASR/FireRedProbe/README.md), [local conversation guide](../../../.agents/skills/verify-mural/features/local-conversation.md) and [Core AI checkpoint](../../coreai/gpu-talk-checkpoint.md).
- Repository `AGENTS.md` overrides historical recipes. This document is a progress/acceptance plan, not a replacement runner specification.

## Progress tracker

Use **pending / in progress / blocked / complete**. Complete requires evidence and explicit scope; failed attempts remain linked separately. Update this table and the dated progress log after each meaningful stage, not every tool call.

| Stage | Status | Exit evidence / next action |
| --- | --- | --- |
| 0. Review and revised plan | complete | Reviewed `b3013a0`, physical runner/tests, lessons, corpus provenance and app-slot constraint. This document records the agreed direction. |
| 1. Offline trace and fixture preparation | in progress | Fresh TOC/export inspection leaves attribution unresolved. MELI v1.1 terms/source checks and six reviewer clips from three speakers prepared under `.build/verification/simplified-talk-meli-20260928/`; references not yet reviewed/frozen for inference. |
| 2. Minimal FireRed runner extension | in progress | Model-free `pair-check` for `zh-CN-en`, host refusal/race checks, signed build and physical Settings/nonce/restoration PASS (`20260928-083908-39499`). Native-linked build, duration-aware fixtures and FireRed event/resource stage still pending approval; not full Stage 2 completion. |
| 3. Continuation decision and resource experiment | blocked | Saved-trace analysis first; explicit review of one adequately budgeted real-Talk experiment, then measured idle/drain evidence. |
| 4. Speech, support and persistence | blocked | Stage 3 permits continuation; actual acoustic mixed speech, tutor, English output and Simplified support evidence. |
| 5. Native lifecycle and existing-pair regression | blocked | Distinct cancellation/background/resume/drain/offline scenarios and focused Breeze/PhoWhisper checks. |
| 6. Ordinary linkage and managed downloads | pending | Extend existing bridge/package/installer path after native qualification; exact pinned public assets, no fallback. |
| 7. Empty managed-install provisioning on current phone | blocked | Stage 6 implemented; prove real downloads/verification/activation and offline preparation without using developer-staged assets. |
| 8. Final review and handoff | pending | Gate-by-gate report, cleanup, reviewed source and appropriate commit; no full-completion claim with blocked required gates. |

**Next safe action:** review the shorter continuation proposal and local MELI review packet. Model-free phone gate passed with restored settings. No FireRed preparation until Stage 3's continuation decision and capture/fixture prerequisites are recorded.

## 1. Offline evidence and corpus preparation

### Resource evidence first

Inspect the retained `.build/verification/firered-memory-device-20260920/idle.trace` and its report. Seek pre-Prepare, loaded-idle and post-Stop allocation call trees and timestamped VM attribution. Existing stable sampled residency near 1.57 GB does not establish the original warning cause, leak freedom or successful delayed release. Record unavailable attribution explicitly rather than inventing a fix or repeating the stopped configuration blindly.

### Primary corpus: MELI

- Dataset: <https://doi.org/10.5683/SP3/5WMRUO>
- Speaker criteria: <https://meli-corpus.readthedocs.io/en/latest/1-design/>
- Download documentation: <https://meli-corpus.readthedocs.io/en/latest/4-download/>
- Inspected published metadata: version **1.1**, **CC-BY 4.0**, 275 unrestricted files. Save the exact metadata/license and selected file identities when downloading; recheck rather than assuming a moving release is unchanged.
- The design page states Mainland-born/raised recruitment for 51 bilinguals, recorded in Vancouver with overseas university experience. **Individual metadata must control selection:** September 28 inspection found M03A lists birth/early residence in Kaohsiung and later Taiwan schooling, despite the cohort-level claim. Do not count all 51 as independently established Mainland-origin speakers. Selected review speakers F00A (Hangzhou to 18), M00A (Sichuan to 19) and F89A (Hefei to 18) have relevant individual histories. Approximately 30 hours across both languages, transcriptions and aligned TextGrids; not a mainland-resident population benchmark.
- Research summaries/paper wording have conflicting license descriptions. Use the actual release metadata and current official download terms, preserving evidence; stop for clarification if the selected release introduces contradictory restrictions.

Inspect small annotations/metadata before downloading necessary audio files; avoid fetching the entire corpus. Select a small fixed set across several speakers with Mandarin-only, English-only, Mandarin-to-English and English-to-Mandarin switches. Include natural short replies and names/numbers when suitable examples exist. Supplement missing categories with consented reviewer speech or clearly labeled local synthetic fixtures, not falsely attributed MELI examples.

Freeze selection before observing FireRed output. Record file IDs/checksums, speaker region metadata, channel selection, exact clip boundaries, duration, source and reviewed reference. Preserve natural pauses and switch boundaries; no speech speed changes, stitched fake code-switching or model-dependent cherry-picking. Check the correct speaker channel and exclude overlapping/unintelligible speech from exact-reference smoke checks using predeclared criteria. Keep omitted cases documented rather than silently improving the score.

Have the Mandarin reviewer resolve uncertain references and expected Simplified writing before inference. References are scoring-only, never recognition prompts. Predeclare case/punctuation/spacing rules and any exact numeric equivalences; the old `3=three` rule is not blanket permission to rewrite Chinese numbers or names. Preserve raw output and report script errors separately. No Traditional-to-Simplified conversion of recognized text to turn a failure into a pass.

CS-Dialogue is a closer geographic alternative with 200 speakers from 30 mainland provincial-level regions, but its official terms explicitly prohibit commercial product development: <https://huggingface.co/datasets/BAAI/CS-Dialogue>. Do not use it for Mural without appropriate permission. TALCS download/license remains unverified. ASCEND is optional supplementary coverage, not the primary Mainland-origin acceptance source.

## 2. Extend the existing physical workflow minimally

Reuse `scripts/verify_device.py`, `UITests/MuralUITests.swift`, `make agent-verify-device` and `make agent-device-report`. No second runner, downloader, generic backend registry, tester subagents or new test suite by default.

The current physical harness is explicitly Vietnamese/Core AI-specific: hardcoded pair/backend, two English fixtures, five-second playback ceiling, 12-second acknowledgment window and 300-second XCTest allowance. Do not run it unchanged and label the result FireRed acceptance.

Required changes:

1. Add a small explicit Simplified Chinese scenario selection while preserving the existing default. Snapshot the real original preference and select the test pair in one Settings visit; restore and independently read it back during cleanup.
2. Require actual selected-pair `zh-CN-en`/FireRed preparation and native inference evidence in the current process. A generic Core AI launch event is insufficient. Adapt expected event contracts and fault matching to the real FireRed path, without weakening Vietnamese checks.
3. Accept frozen reviewed audio fixtures with duration-aware bounded playback and acknowledgment budgets below the app's recording cap. Retain fresh capture event plus native UI gate, one playback per turn, successful completion, exact nonce acknowledgment and trailing margin. No guessed Send sleeps.
4. Preserve distinct main app `com.kevintruong.mural.dev` and existing runner `com.kevintruong.mural.dev.physicaltests.xctrunner`. Do not create another signed slot. Stop on provisioning errors rather than deleting apps or changing teams.
5. Build the explicit native-linked Release with the existing Core AI opt-in preserved. Check actual app compiler/linker commands, bundled pin and signed artifacts. Fingerprint the additional native inputs/configuration for preparation reuse. Restore the ordinary generated project after variant preparation, including failure; preserve the matching artifact/receipt so ordinary regeneration cannot accidentally cause a default build to be tested as FireRed.
6. Requalify changed Settings/selector/cleanup/acknowledgment paths model-free first. Define failure cases before any necessary isolated host checks: wrong backend/pair, stale or truncated playback, wrong nonce, changed fixture/artifact, late Send, missing native evidence, false drain, faults and failed restoration. Use existing host checks only where unsafe/uneconomical to provoke through the app.

## 3. Resource continuation and first real Talk qualification

Record the saved-trace conclusion before proposing another native load. If unresolved, present the missing attribution and a concrete bounded continuation for explicit review, not an unchanged retry to finish a matrix. No resource-limit increase, warning suppression, thread/provider/model change, VAD disabling or automatic retry.

Proposed experiment, **not yet approved for execution**:

- Discover and exclusively own the connected physical iPhone 17 under the existing lock. Prepare signed artifacts and fixtures before requesting an audible window.
- Use normal Settings/Talk, not file-probe/flask/diagnostic launch routes. Keep retained assets and selected voice. Observe combined FireRed + VAD + Apple tutor + English speech, not isolated ASR only.
- Confirm useful app-scoped console and any approved allocation/VM capture are ready before Prepare. Missing attribution/capture is a blocker, not permission for an unobserved soak.
- Establish real readiness/tutor baseline and qualify one acoustic turn, reviewing each gate before expanding. Reuse compatible observations as part of the resource experiment rather than duplicating model loads merely for stage names.
- Observe at least **360 seconds loaded idle after the final completed turn**, then End, native return/owner drain and **30 seconds post-drain**. Seek timestamped release samples including +2/+10/+30 seconds where supported. No additional inference during idle or release observation.
- Set a separately reviewed finite resource-stage budget covering profiler readiness, human navigation, preparation, turns, full idle, native drain and cleanup. The current 300-second test allowance cannot fit this. Do not simply shorten idle or extend every routine stage. Record actual phase anchors so the deadline does not expire before Stop as it did previously.
- Resolve how the idle observation stays foreground without changing system Auto-Lock or silently holding the preparation-only idle timer. If manual unlock/touch is needed, agree it before the run and record the interaction.
- Stop on the first memory warning, crash, serious/critical thermal state, asset/model fault, missing required evidence or existing native-duration blocker. Cancel through the owner, never free handles during a synchronous C call. Preserve failed evidence and no automatic second attempt.

### Revised continuation budget for review (September 28; not approved)

The user rejected the initial 25-minute ceiling as too slow. **Timeout ceilings are not planned waits.** Reduce the first experiment to **one** reviewed acoustic turn, combining native readiness, first acoustic qualification and resource observation in one fresh-process Talk run, with the retained selected voice, FireRed/VAD, actual Apple tutor and English output. Expected working estimate **8-10 minutes**, not measured or guaranteed for this unqualified combined workload. The only fixed observation waits total **390 seconds** (6-minute idle + 30-second post-drain); the original warning arrived about 338 seconds after load and 137 seconds after the last decode. Shortening those observations requires an explicit coverage change, not an optimization claim. No file-probe substitute or duplicate model loads for stage labels. Keep the existing 60-second native-operation stop; routine stage budgets remain unchanged.

- Whole runtime ceiling **1,020 seconds (17 minutes)**, excluding separately completed signed build/fixture preparation: 60 seconds preflight/install, 60 seconds profiler attachment/readiness, 780 seconds native test command (including startup), and 120 seconds reserved host capture finalization/cleanup. Phases proceed immediately on readiness; there is no wait to consume a ceiling.
- Resource-only XCTest allowance **720 seconds**, not the existing 300: 30 seconds Settings/UI, the unchanged routine 90-second preparation/greeting gate, 90 seconds for one turn, **360 seconds loaded idle anchored to the final completed reply/speech/support**, 60 seconds End/native-owner drain, **30 seconds after confirmed drain**, 60 seconds native restoration/teardown. A phase overrun fails; do not spend the idle/drain reserve on extra preparation or retries. Preserve full cleanup separately even after failure.
- App-scoped console starts at normal launch. Allocation/VM capture must be attached and show useful baseline allocation stacks and a timestamped VM snapshot **before Prepare**. Missing useful capture blocks loading. Trace ceiling 900 seconds from attach request (60 attachment + 780 test + 60 save); host finalization remains separately reserved. Capture/log limits must not expire before the release interval.
- Need phase-correlated memory samples at baseline, verification/VAD/native preparation, each native return, final completed turn, loaded idle and owner drain +2/+10/+30 seconds. The old 420-second diagnostic-from-Prepare mode is unsuitable and must not be reused unchanged. Do not infer drain solely from the New conversation button.
- Foreground idle requires an agreed human touch on a non-action area at least every 30 seconds, without changing Auto-Lock or extending the preparation-only idle-timer hold. Unexpected background/lock ends this experiment as incomplete; no automatic resume/reprepare.
- First warning, crash, serious/critical thermal state, model/asset fault, lost required evidence or native-duration blocker stops through the existing owner. Preserve the failure, drain safely and finalize owned captures. No second attempt without review.

Approval of this design is not an audible window. Execution also requires frozen reviewer-approved references, native-linked artifact/event/stop instrumentation, model-free qualification and one current phone-placement/listening readiness interview. A warning-free bounded run can support continuation for the tested workload; it does not prove the original pressure cause, universal memory safety or broad device qualification.

## 4. Speech, Simplified support and persistence

After permitted continuation and acoustic qualification, use small medium-difficulty batches, not the entire corpus through slow UI automation:

- Several frozen natural Mandarin/English switching turns across speakers, plus monolingual controls, short Yes/No and name/number coverage.
- Real iPhone capture/frame evidence and current native turn identities; no injected audio/text in place of microphone acceptance.
- Compare raw text against predeclared references. Report Chinese character errors, English word/span errors and script mismatches separately. Any aggregate mixed error metric must name tokenization/sample size; a small smoke is not corpus-wide accuracy.
- Require actual Apple runtime locale support for `en-US` and `zh-Hans-CN`, real completed replies, English reply policy and English speech. Preserve bounded prompts and no cloud fallback.
- Verify Simplified meanings, word lookup and screen-only Help. No Chinese Help playback; no Chinese assessment/learning credit. Use reviewer judgment for meaning/script/usefulness, not merely nonempty generated text.
- End, normal relaunch, then inspect only the newly created test conversation. Assert exact observed learner/assistant text, counts and order. Retain screen evidence without Device Hub mirroring.
- A planned fresh repeat qualifies changed contracts only after the first pass is reviewed. Do not repeat failed model/resource runs automatically. Routine later changes select only affected scenarios.

Human listening confirms actual iPhone output separately from Mac fixture playback. TTS events are not audible-output proof. No room recording unless separately authorized.

## 5. Native lifecycle and existing pairs

Record each result separately; existing `cancel` proves only recording cancellation/recovery.

- End during recording, drain, then a distinct new conversation without stale text/audio.
- Cancellation during preparation/inference: correlate actual native entry/return; an action after work has completed is not in-flight acceptance. Observe admission closed until the old synchronous owner finishes.
- Change the next Settings pair while canceled setup drains; diagnostics remain on the old owner and no new model is admitted early.
- Background/foreground and paused-session resume use the selected FireRed mapping, preserve finalized text and discard unfinished recording. No late old-session completion or automatic fallback.
- Restart and offline operation with all required assets installed. Preserve and restore connectivity changes through agreed human actions if automation cannot safely control them.
- Focused Traditional Chinese/Breeze and Vietnamese/PhoWhisper regressions, preserving voice/backend preferences. Do not replay entire already-qualified suites unless shared changes justify it.

## 6. Ordinary linkage and managed downloads

After native qualification, complete the implementation rather than leaving only a developer-staged candidate:

- Isolate/reuse the existing runtime bridge; reproducible pinned linkage and notices, preserving reviewed sherpa/ORT versions and inference policy. Ordinary project must not accidentally retain probe-only flags/paths.
- Extend the existing ONNX package schema/catalog/installer minimally for FireRed and explicit upstream file paths. No second downloader, invented manifest URL, runtime plugin system or bundled model weights.
- Exact reviewed public model repository: `csukuangfj2/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26`, revision `374cff185e952c40fcf2f6da972a3b6cf340608d`. Required files: `encoder.int8.onnx`, `decoder.int8.onnx`, `tokens.txt`; sizes/hashes must match the existing pin. Never moving `main`, v1, CTC or LLM substitution.
- Use bundled reviewed metadata where the upstream lacks a canonical manifest. Review signed CDN redirect/host handling narrowly. Preserve storage checks, resumable/cancelable transfer, full pinned verification, atomic activation and fail-closed corruption handling.
- Measure disk requirements rather than guessing a larger reserve. Verify all required supporting assets/voice/tutor availability; FireRed weights alone do not establish complete first-use readiness.
- Resolve managed assets through the same full recognizer verification before native load. Existence-only preflight is not integrity verification or readiness.
- Production S3/R2 hosting remains a separate future publication task in `todo.md`; no upload/spending or destination assumption here.

## 7. Provisioning within the existing app slots

Use the existing app and runner only. Preserve `Documents/FireRedProbe/model`, existing other models, voices, history and settings.

Exercise a genuinely empty **managed FireRed package location** through the actual production install path. Do not silently copy/import developer-staged weights or fall back to them. Prove network fetches, exact pinned URLs/bytes, completed verification and atomic activation before preparation. If the managed package already exists, stop and agree a safe test arrangement instead of deleting it to force a test.

Cover initial download, bounded interruption/cancellation and explicit resumption, safe rejection of incomplete/corrupt packages, then real preparation and cached offline restart. Use isolated host checks for destructive corruption/storage failure cases that cannot safely be produced on the personal phone; those do not replace the real app download and activation check.

Report this as **first-download provisioning in an existing installation**, not a literal clean installation. A whole-app clean-install gate remains deferred/blocked by the preservation/app-slot constraint, while fresh-install-capable code remains required. Reusing the XCTest runner does not give Mural a new empty sandbox.

## Efficiency and safety rules carried forward from the lessons

| Known mistake | Required prevention here |
| --- | --- |
| Repeated build/phone handoffs | Prepare artifacts and freeze fixtures first; consolidate one readiness interview. Carry approval forward within the unchanged window. |
| Unnecessary recompilation/package resolution | Reuse matching source/device/artifact receipts and compiler proof for identical executable bytes; runtime uses copied fingerprinted `.xctestrun`. No source timestamp touches/cache clears. |
| Receipt mistaken for cached native readiness | Keep policy-2 stable sandbox identity plus all manifest/device/OS/compute invalidation and full load/validation. Measure actual native loading. |
| Discovery tunnel falsely treated as unreachable | Use bounded direct device checks through saved status operations, not cached connection text alone. |
| Empty syslog accepted as evidence | Use qualified Mural-only `devicectl --console`; require fresh process/backend/turn events. No device-wide archive fallback. |
| Duplicate initialization mistaken for duplicate process | Correlate PID and owner/turn identity, not event-line counts. |
| Playback starts too early or Send truncates it | Fresh capture + UI gates, actual bounded `afplay` completion and current nonce. Retain devicectl's five-second minimum tool timeout inside a bounded host call. |
| Repeated remote accessibility queries | Early-return target-driven scrolling; one initial Settings visit; one settled transcript-scoped snapshot for counts/order. Restore/readback visits remain meaningful. |
| Selector/cleanup faults waste model runs | Use actual control types, scope nested Done buttons and transcript queries; qualify repairs model-free before another acoustic run. |
| Late permission approval or lock | Human protected prompts remain gates; keep bounded waits. Never auto-approve or change system Auto-Lock. |
| False pass from reference normalization | Freeze rules before inference; preserve failed text and script/English-span findings. No retry-until-green. |
| Unknown/personal process terminated | Reuse status and exact-PID stop-idle only with confirmed idle ownership and installed-bundle identity under lock. |
| Resource capture ends before release | Attach/verify first; anchor idle to actual final completion and budget drain/observation/cleanup separately. |
| Speed claim hides reduced scope | Report build separately and total through cleanup; compare identical coverage, fixtures/runtime and retained-cache state. Never add overlapping native and host timing domains. |
| Successful tests hide failed cleanup | Inspect saved cleanup independently, preserve original failures and separate recovery reports. Stop all owned playback/capture/tests, restore preferences; never shut down the phone. |

Do not start redundant simulator acceptance when physical tests sufficiently prove the affected path. When synthetic UI-only checks are necessary, use the single persistent Mural simulator and mandated bounded lifecycle. No other project's simulator, Device Hub or build workload may be interrupted.

## Evidence and completion

Keep private artifacts under `.build/verification/physical-iphone-e2e/<unique-run>/` using existing entrypoints. Retain source/working diff, exact hardware/OS, app/runner/runtime/pin identity, fixture provenance, scope/budgets, actual backend, current-turn receipts, raw recognition, native results/video, scoped logs, timings, human feedback and cleanup. Do not commit personal speech, logs, audio, binaries, signing data or `.build`.

For each stage update the tracker with the evidence path, automated versus human-confirmed results, failures and next blocker. Final report separates:

- Source and ordinary/native builds.
- FireRed pair/readiness, acoustic ASR and English preservation/script.
- Tutor, meanings/lookup/Help and audible English output.
- Exact native lifecycle scenarios and resource idle/drain interval.
- Download/activation/offline provisioning versus literal clean-install coverage.
- Existing-pair regressions, restored preferences and owned-process cleanup.

Commit only reviewed intended source when ready, naming remaining candidate gates honestly. No automatic push or full E2E/completion claim while required acceptance is blocked.

## Progress log

### Plan saved at source checkpoint b3013a0

- Read the physical E2E lessons in full and incorporated the qualified receipt, launch, playback, UI-query, logging, cleanup and timing practices above.
- Replaced ASCEND-primary planning with MELI Mainland-origin speaker selection and explicit provenance/coverage limits.
- Recorded existing app/runner reuse and the distinction between first managed download and literal clean installation.
- No implementation, phone operation, model load or playback performed in this documentation step.

### September 28: offline evidence and model-free preparation

- Confirmed `mvp` at `b3013a0`, ahead four commits; only this untracked plan existed initially. Preserved it and the applied candidate. Read the requested project/handover/resource/physical records; no patch reapplication or generated-project edit.
- Fresh saved-trace TOC export passed. A bounded 20-row Allocations List selector still hit the file-size guard (exit 153, empty export); no broader retry. Saved Statistics/VM tables lack usable timestamped stack attribution. Instruments GUI range/call-tree inspection was not achieved, so this is an explicit tooling gap, not proof the trace lacks stacks. Original cause remains inconclusive. Evidence: `.build/verification/simplified-talk-offline-20260928/result.md`.
- Retrieved exact MELI release 1.1 API metadata: CC-BY 4.0, 275 unrestricted files, no additional terms/restrictions fields. Preserved official release README, procedures, transcription conventions and download documentation. Current official download page also states CC-BY 4.0. README contains stale SpiCE links/citation text; use the actual MELI DOI/version and official current citation, not those copied references.
- Individual metadata exposed an exception to the blanket Mainland-origin claim. Selected F00A, M00A and F89A have documented Mainland upbringing; overseas experience remains a limitation. Downloaded only their three necessary WAVs after inspecting six small annotation files. Full source sizes/MD5s match release metadata; SHA-256 hashes and six deterministic left-participant-channel clips saved in `review-manifest.json` under `.build/verification/simplified-talk-meli-20260928/`. No audio playback or model output observed. Clips/references remain **review-required, not admitted to inference**; natural multiword switching, names and separate Yes/No coverage remain gaps.
- Added `DEVICE_STAGE=pair-check DEVICE_PAIR=zh-CN-en` to the existing physical runner/XCTest. It selects English/Simplified Chinese, checks FireRed diagnostics, exercises scrolling and fresh nonce transport without Prepare, restores the original preference and independently reads it back. It never opens personal history. Default Vietnamese stages remain unchanged; host and XCTest explicitly reject native Chinese scenarios until continuation is implemented/reviewed.
- Failure cases written first: unknown pair, missing readiness and accidental native Chinese admission. Observed expected preimplementation failure, then existing host checks PASS. Python compile and whitespace checks PASS. Signed ordinary Core AI Release/app and updated runner build PASS, 28.69 seconds through cleanup, under `.build/verification/physical-iphone-e2e/20260928-082658-11057/`. Actual compiler evidence reused only for identical app executable bytes. This is not a FireRed-linked artifact or physical UI pass.
- Read-only discovery found the connected paired iPhone 17. No installation, launch, Prepare, microphone action, Mac playback, room recording or simulator boot occurred. Build cleanup PASS. Physical model-free acceptance awaits exclusive idle/unlocked phone confirmation; resource experiment design and reference review remain separate gates. No managed downloader/linkage promotion started.

### September 28: model-free physical gate passed; continuation not approved

- User confirmed exclusive idle/unlocked/cool phone and closed mirroring for **model-free only**. User requested a local reviewer packet for later Mandarin review. They requested revising the resource proposal for speed, not executing it. Revised above to one combined acoustic/resource turn, estimated 8-10 minutes with a 17-minute failure/cleanup ceiling; six-minute idle and 30-second release observations remain, pending review. No audible window or FireRed continuation approval obtained.
- First preflight `20260928-083555-32270` refused a residual Mural process. Using the current idle confirmation, `stop-idle` verified exact PID 83814 against the installed bundle under lock and stopped only that process (`20260928-083609-32707`). No data change.
- Model-free attempt `20260928-083618-32989` reached Simplified Chinese/FireRed diagnostics and consumed the nonce, but failed: XCTest immediately deleted the receipt before devicectl's post-copy file-node lookup, yielding error 7000. Host abort interrupted preference teardown; original cleanup remains FAIL. Recorded original preference was Traditional Chinese. No model work/playback occurred; phone-after process inventory was empty.
- Added tests-first refusal cases, then a narrow shared transport correction: tolerate only that exact destination-specific file-node error when the fresh native log proves consumption of the exact run/index/nonce once. Wrong/missing/duplicate nonce, other copy errors, timeout, early Send and playback failures remain failures. No guessed Send delay or retry. Exact-token ACK is now logged; all current-token and completion gates stay intact. This handles a post-delivery stat race, not a failed delivery. Recovery can explicitly restore the recorded original language during pair-check.
- Updated signed app/runner preparation `20260928-083848-38647`: PASS, 14.01 seconds including cleanup, identical production executable and retained compiler proof. Focused host checks PASS. Separate model-free recovery/qualification `20260928-083908-39499`: **1 passed, 0 failures/skips; 28.78 seconds including cleanup**. Selected Simplified Chinese, checked FireRed diagnostics, exercised exact nonce transport and scrolling, restored Traditional Chinese and independently read it back. No personal history access, Prepare, microphone, models or Mac playback. Owned phone/host processes stopped; cleanup PASS. This run's copy returned normally; the reproduced post-copy-error branch has host rejection-matrix evidence, not deliberate physical fault injection.
- Exported native XCTest screen recording and screenshot. Video fully decodes with ffmpeg; inspected the Simplified Talk screenshot with readable pair, Prepare button and diagnostics disclosure. No animation-fix claim. Failed attempt and separate recovery evidence remain intact; no model retry or duplicate simulator acceptance.
- Reviewer packet: `.build/verification/simplified-talk-meli-20260928/review.html`, adjacent `reviewer-notes.md`, `review-manifest.json` and `prepare-clips.py`. Local audio controls require deliberate Play; no autoplay/upload/recording. Human reference/script/meaning checks remain unperformed. All corpus bytes/logs/binaries stay ignored.
- Fresh selection qualification `20260928-084236-47188` additionally passed from restored **Traditional Chinese**, actually changed to Simplified Chinese, then restored/read back Traditional Chinese without a recovery override: 1 test, 0 failures/skips, cleanup PASS, **36.48 seconds**. This proves selection, distinct from the preceding recovery's already-selected state. No models/audio; the final screen recording remains in its xcresult. No further repeat needed.
