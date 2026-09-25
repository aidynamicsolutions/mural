# On-device speech memory-pressure UX

Date: 2026-09-25. Branch: `mvp`.

**Status: recovery UX implemented locally and simulator-verified. A real iOS memory warning, native model drain under warning, and physical-device acceptance are not yet verified by this change. This does not establish or fix the underlying memory-pressure cause.**

## Reported issue and scope

During manual testing, the owner loaded Vietnamese ASR, switched to Traditional Chinese, and prepared the second model. They later saw an iOS memory-warning pop-up. This sequence makes model coexistence/residency a useful investigation hypothesis, but does not prove that two models remained resident or that Mural caused the warning. Earlier physical testing did not reliably reproduce the warning.

The accepted goal is to keep the rest of Mural usable and avoid a blocking "close Mural and reopen" message. iOS may still terminate Mural if memory pressure escalates. This change is a best-effort response, not a guarantee against termination, a reduction in model memory, or a fix for one-model-at-a-time residency.

## Agreed behavior

- On a memory warning, request cancellation of active local speech/ASR work and release the engine's model references. Cancel an in-progress managed setup transfer as well; its existing checkpointed installer remains responsible for safe recovery.
- For an established local conversation, pause the same session, retain finalized turns, and keep navigation and other app areas usable. Do not end the conversation, show a generic modal/banner, switch backend, clear caches, or permanently disable ASR for the process.
- Talk quietly shows a paused status and a subdued **Resume** action. Keep it disabled until the existing work owners actually drain. Foregrounding alone must not restart speech. An explicit Resume runs the ordinary preparation/validation path; a failed retry remains a normal preparation error.
- If first-time setup is interrupted before the learner has a completed turn, discard the empty draft. Keep Prepare & start disabled while the setup owner drains, then let the user explicitly start again and recheck inventory.
- The existing 3 GB sampled-footprint guard uses the same temporary pause/recovery behavior. It is not a permanent memory-warning latch.
- Thermal protection is unchanged: cooling and an explicit Resume are still required.

Apple advises apps to release memory in response to warnings; warnings are best-effort and termination can occur if memory demand continues. Therefore Mural responds narrowly but does not attempt to prevent iOS from managing process lifetime.

## Implementation checklist

- [x] Observe memory warnings for every local speech backend, not only the staged Core AI backend.
- [x] Stop current audio/native work and remove the process-long ASR lockout.
- [x] Cancel an active managed setup transfer; preserve the installer’s existing resumable-file and verification behavior.
- [x] Preserve an established conversation and gate explicit Resume on the existing worker/drain state.
- [x] Do not automatically resume after foregrounding; require an explicit user action.
- [x] Replace the blocking/generic warning UI with quiet Talk status and a nonmodal, drain-gated Resume control.
- [x] Keep thermal-stop UX separate and unchanged.
- [x] Add a simulator UI regression covering a posted memory-warning notification, a noncooperative drain, background/foreground and tab navigation, explicit retry, and retained transcript turns.
- [ ] Verify a naturally occurring memory warning and native-owner drain on Kevq without artificially stressing or clearing the phone.
- [ ] Separately investigate whether switching language leaves two heavyweight ASR owners resident, and whether explicit offload after the prior owner's drain is safe. Do not change models, precision, compute placement, tokenizer, or backend as part of this UX fix.

## Verification evidence

- Focused UI test: `testMemoryPressurePausesSpeechUntilExplicitResumeAndPreservesTurns` passed on the iPhone 17 / iOS 27.0 simulator, 1 test, 0 failures.
- Result bundle: `.build/verification/memory-pressure-recovery/20260925-200239/memory-pressure-ui.xcresult`.
- Formatted/raw build-test log: `.build/verification/memory-pressure-recovery/20260925-200239/memory-pressure-ui.log`.
- Screenshots: `.build/verification/memory-pressure-recovery/20260925-200239/attachments/` (paused state and post-Resume state).
- Release configuration built successfully for Kevq using the existing local signing setup and the current `MURAL_COREAI_TALK` path. The built app was installed over the existing `com.kevintruong.mural.dev` app and launched successfully. No app uninstall, app-data wipe, cache deletion, or signing/capability change was performed. Evidence: `.build/verification/memory-pressure-recovery/20260925-202128/` (`device-build.log`, `device-install.log`, `device-installed-app.txt`, and `device-launch.log`).
- The UI fixture posts the same notification name and models a four-second noncooperative owner. It is not an actual OS-delivered warning and is not proof of native model release. The phone was not artificially memory-stressed. Physical warning reproduction, real native-owner drain under warning, and interactive device acceptance remain pending.

## References to retain

- Apple, [Responding to memory warnings](https://developer.apple.com/documentation/uikit/responding-to-memory-warnings).
- Apple, [Responding to low-memory warnings](https://developer.apple.com/documentation/xcode/responding-to-low-memory-warnings).
- Apple, [Identifying high memory use with Jetsam event reports](https://developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports).
- Related Mural evidence: [`firered-memory-investigation-20260920.md`](chinese/firered-memory-investigation-20260920.md), [`vad-qualification-result-20260919.md`](vad-qualification-result-20260919.md), [`gpu-talk-checkpoint.md`](../../coreai/gpu-talk-checkpoint.md), [`speech-setup-ux.md`](speech-setup-ux.md), and the current paired workflow in [`mvp_plan.md`](../../mvp_plan.md).
