# Speech setup checklist progress regression

**Status: checklist fix passes Core and focused simulator checks. Physical Taiwan/Breeze smoke reached Ready, then received a real iOS memory warning. STOP pending memory and engine-owner review; phone UI-order acceptance is inconclusive.**

- Source branch: `local/resumable-speech-setup-qualification`
- Recording: `ScreenRecording_09-24-2026 18-58-55_1.MP4`
- Frame/source review: `.build/verification/speech-setup-video/20260924T120421Z/result.md`

## Observed failure

The recording shows `Checking setup` still pending after preflight, `Voice ready` checked and then pending again, and the headline returning from component preparation to the broader recognition stage. The checklist disappears when the validated setup hands off to Mural's greeting. Source confirms the validation boundary is before that handoff, so the greeting transition is not evidence of Ready bypassing native checks.

## Cause

`SpeechSetupControl.enter` currently removes the completion mark for every incoming progress stage's major category. It accepts duplicate and out-of-order observations. A second `.checking` update can therefore erase preflight completion, and a delayed earlier progress event can reopen a completed stage. The same unfiltered stream can make the headline move backwards.

## Fix plan

- [x] Review the user recording at sparse and dense frame intervals.
- [x] Trace the checklist from `LocalConversationEngine` progress callbacks through `ConversationCoordinator` to `SpeechSetupControl`.
- [x] Add focused Core regressions for repeated completed stages, backward stage updates, same-major detail regressions, and real revalidation after a drained resume. The new tests failed before the fix and pass after it.
- [x] Make `SpeechSetupControl.enter` reject stale/backward updates, preserve completion on duplicate updates, and clear a completion only when a later setup attempt genuinely re-enters that stage.
- [x] Label the engine's post-preflight reset as voice preparation, not a second setup check.
- [x] Keep component labels as observed. Decoder and encoder share a progress rank, so no native order is imposed. Model, compute, precision, tokenizer, and validation policy are unchanged.
- [x] Run the full Core suite on Darwin, then focused iOS 27 simulator checklist and conversation-handoff tests. Inspect recorded transition frames.
- [x] Stabilize the UI regression test: it no longer waits for the short `Checking downloads` state after slow XCTest screenshot/accessibility calls. It asserts the stable `Preparing voice` state, download completion, verification completion, and removal of download-only progress.
- [x] Update this document with outcomes and limitations.
- [x] Build the normal Release configuration with the existing local signing settings, install in place into the exact existing app bundle, and launch on Kevq. No app was removed, no cache was cleared, and no data was reset.
- [x] Owner-led physical smoke attempted. Taiwan/Breeze reached validated Ready, then STOP on an iOS memory warning. The log does not prove the visual checklist ordering; this is not signed-device lifecycle or background-continuation qualification.

## Validation results

- Xcode 27.0, iOS 27.0 iPhone 17 simulator (`D9CD5843-2A4C-4402-9031-B063C0F19383`). `build-for-testing` succeeded.
- Darwin `swift test` passed. XCTest reported 92 passed, 0 failed. Swift Testing reported 95 tests across 12 suites passed, including the regression cases, installer, and preparation-receipt suites.
- Focused UI run passed 2/2: `testSpeechSetupChecklistTransitionsUseOnlyDownloadPercentages` and `testSuccessfulSpeechPreparationResumesCompactlyWithoutHidingConversation`. The final result bundle is under `.build/verification/speech-setup-checklist/` as `checklist-ui-final.xcresult`.
- Inspected the iOS 27 simulator capture and XCTest recording around download completion through voice, encoder, decoder, final checks, and Ready. The major checkmarks remain complete while later stages run. The checklist is removed only after validated setup hands off to the conversation, which is expected.
- One intermediate rerun failed only because XCTest began waiting for the transient `Checking downloads` title after its three-second display had passed during slow accessibility/screenshot work. The same failed run's recording showed the expected `Checking downloads` to voice/encoder/decoder progression and retained marks. The brittle intermediate-title assertion was replaced with stable downstream assertions; the final focused run passed.
- Evidence: `.build/verification/speech-setup-checklist/20260924T164806Z/` contains build and test logs, compact xcresult summaries, the simulator recording `after-checklist.mov`, exported XCTest recording and focused frames (`xcresult-transition-*.jpg`), plus the retained download-progress screenshot. These are local, ignored verification artifacts.
- Physical Release was installed in place on Kevq with the existing bundle and signing configuration. The Mural-only capture shows Taiwan/Breeze setup job `46BBF7AA-8EA9-49EA-A6A9-7801B2A0485E` reached `process_validated` and `ready`, then one Breeze decode completed before UIKit delivered a real memory warning at 14:10:04. The app's memory-warning handler ended local work and raised its safety alert. Breeze process-footprint peak was 2,178,320,728 bytes; thermal state was fair, not serious. Two engine warning handlers fired (Breeze and PhoWhisper); why both engine instances were alive is unresolved. See `.build/verification/phone-smoke/20260925T065239Z/memory-warning-report.md`. Do not retry native ASR until this is reviewed. The checklist fix changes only progress acceptance and its initial phase label; the original screen recording remains the pre-fix visual evidence. Track the separate memory-warning and engine-lifetime investigation in [speech-setup-memory-warning-investigation.md](speech-setup-memory-warning-investigation.md).

## Acceptance

1. `Setup checked` remains checked after preflight; an ordinary progress reset cannot undo it.
2. Once `Voice ready` is observed, duplicate or backward progress cannot turn it back into pending.
3. The headline does not regress from a later major/detail phase to an earlier one. Decoder and encoder remain peer observations; their native order is not fabricated.
4. A real later revalidation after drain can reopen the stage being performed again.
5. Existing foreground gating, durable boundaries, native preparation, and the validated handoff to the greeting remain unchanged.
6. No unrelated source, assets, signing, or package changes.

## Progress log

- 2026-09-24: Frame review and source trace completed. Added Core tests first; the pre-fix focused run failed on the pending Checking setup mark, disappearing completion, and backward headline. Implemented the progress gate and engine phase label. `swift test --filter SpeechSetupControlTests` now passes 8/8.
- 2026-09-25: Xcode 27 simulator build passed. Darwin `swift test` passed (92 XCTest and 95 Swift Testing cases). Focused iOS 27 UI tests passed 2/2. Recorded and inspected the checklist transition through encoder, decoder, final checks, and Ready. A first UI rerun missed the transient three-second `Checking downloads` title after XCTest accessibility work; the app recording showed the expected state sequence, the brittle assertion was replaced with stable downstream checks, and the final run passed.
- 2026-09-25: Built Release with the current default ASR selection and existing local signing config; installed and launched in place as `com.kevintruong.mural.dev` on Kevq. Build, bundle, signature/profile, permitted task identifier, and no-native-entitlement checks passed. No app was removed and no data/cache was cleared.
- 2026-09-25: Physical Taiwan/Breeze smoke reached validated Ready and decoded one turn, then UIKit logged a real memory warning. Mural's safety handler ended the conversation. Peak footprint was about 2.18 GB and thermal state was fair. Two ASR-engine warning handlers fired, one for Breeze and one for PhoWhisper; ownership is unresolved. The bounded Mural-only capture stopped after its 15-minute limit. Further ASR retries are STOPPED pending review. Details: [memory-warning investigation](speech-setup-memory-warning-investigation.md) and local `.build/verification/phone-smoke/20260925T065239Z/memory-warning-report.md`.
