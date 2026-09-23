# Background First-Time Speech Setup Plan

**Status:** Owner-reviewed direction; implementation not started.

**Updated:** 2026-09-23

This plan covers the multi-minute, first-time on-device speech setup. It is separate from the warm conversation-resume delay tracked in [`../../todo.md`](../../todo.md).

## Owner decisions

- Target continuing first-time setup while the app is backgrounded or the iPhone is locked, using iOS continued processing when the device, model path, and signing entitlements permit it.
- If iOS interrupts the task or the app is force-quit, retain completed work and show **Resume setup** at the last safe checkpoint. The native operation in progress may need to run again.
- Do not silently promise that iOS will always complete background work.

## Current behavior

When first-time setup is in progress and Mural backgrounds, `ConversationCoordinator.background()` cancels speech setup and ends the empty draft. Tapping **Prepare & start** starts the setup flow again. It does not resume an in-flight native model operation at its exact point.

The managed ASR package installer preserves partial file bytes and can resume range downloads. Valid completed assets and caches may also be reused. This means a retry does not necessarily repeat every download or preparation step. However, native ASR/Core ML initialization is not checkpointed inside an SDK call, and a component interrupted while in flight may need to run again. The preparation receipt is written only after successful preparation; a matching receipt can skip explicit prewarming but does not replace model loading and validation.

Relevant current implementation and behavior are described in [`speech-setup-ux.md`](speech-setup-ux.md), with orchestration in `App/ConversationCoordinator.swift`, managed ASR downloads in `Core/LocalSpeechProvisioning.swift`, and success receipts in `Core/CoreMLPreparationReceipt.swift`.

## Proposed approach

### 1. Feasibility gate on the physical iPhone

Before building the complete flow:

- Inspect the selected Release ASR path and identify whether its background preparation needs GPU access, Neural Engine inference, or neither. Do not infer the requirement from the model name alone.
- Check `BGTaskScheduler.supportedResources` on the test device and verify the entitlements in the actually signed app and provisioning profile.
- The project targets iOS 27, so the continued-processing API is available by OS version. The current app entitlements declare Sign in with Apple only; background compute access has not been configured or verified. Background GPU Access and Background Inference are separate Apple entitlements for the corresponding resources.
- Verify that the current signing team can use any required capability. Existing release notes defer paid Apple Developer enrollment; do not enroll, spend money, or claim an unavailable entitlement without the owner's approval. If the required resource cannot be used, retain the foreground fallback below.
- Run a bounded physical-device proof using the real selected ASR preparation, then lock the screen and switch apps. Record the actual stage timings and whether the process, model, and task remain viable.

### 2. Start one user-initiated continued-processing task

Use `BGContinuedProcessingTask` for the first-time setup. Start it in the foreground immediately after the person's final action: **Prepare & start**, or **Download & continue** when download consent is required. Register the task identifier and report meaningful progress. Prefer the system's continued-task Live Activity, which shows progress and lets the person cancel, rather than creating a separate custom activity or treating `UIApplication.beginBackgroundTask` as a multi-minute execution guarantee.

The request can queue until the system can start it. Do not tell the person that active preparation is underway until the task has actually begun; show a clear waiting state if queued. The system can still end a task under resource pressure, so continuation is best effort, not an unconditional guarantee.

Keep a single speech-preparation owner. Do not let foreground return, task restoration, or retry create a second simultaneous model load. Existing cancellation and native-drain safety boundaries remain in force.

### 3. Persist safe checkpoints, not fictional mid-call resume

Persist one active setup record with the selected language pair/model identity, current status, and last fully completed safe stage. Advance a checkpoint only after that stage succeeds. Preserve the existing manifest, hash, ABI, storage, and model-validation checks; never mark speech Ready based only on files being present.

- Keep the managed ASR downloader's verified range-resume behavior.
- Reuse valid completed assets and successful native preparation caches where the existing code permits it.
- If iOS ends a non-interruptible native operation, resume from the previous safe boundary and rerun only the component that did not complete. Do not claim to continue at an instruction-level offset inside a Core ML or SDK call.
- Verify the separate recovery behavior of any upstream-owned voice or speech-detection downloads before promising their partial progress is retained.
- Keep the existing success receipt restricted to complete, successful preparation.

### 4. UX and lifecycle

- Before first setup, set expectations that speech preparation can take a few minutes and, when background continuation is available, the person can leave Mural while it runs.
- Keep the current first-time setup content and status coherent in Mural. Do not replace it with **Setup paused** merely because the app entered the background.
- Show actual byte progress for downloads. Use accurate phase text or indeterminate progress for native work without a real progress callback. Do not invent a percentage or completion countdown.
- If the app returns while the task is still running, reconnect to the existing task. If it completed, proceed to Ready without another Prepare & start action.
- If the system ends the task or the app is relaunched after termination, restore the persisted status and show **Resume setup**. Preserve completed work. Do not silently restart heavy work after a force-quit or explicit cancellation.
- Do not capture microphone audio or play the conversation greeting while backgrounded. If preparation completes away from Mural, defer the greeting/audio start until the app is foregrounded.
- If the necessary background task/resource is unavailable, explain that Mural must remain open, keep the screen awake only while first-time setup is active in the foreground, and offer Resume after a later interruption. Do not imply that this fallback continues in another app.

### 5. Physical-device verification and acceptance

Verify on the owner's iPhone with the actual signed build and selected ASR model:

1. Start setup once, including the download-consent path when applicable.
2. Lock the screen and switch to another app during download and during native preparation. Inspect the transitions and Live Activity, not only the final state.
3. Return while setup is active, after it completes, and after a controlled task interruption. Confirm the existing task is reused, completion reaches Ready, and interruption offers Resume at the last safe checkpoint.
4. Cancel through the system task UI and confirm cancellation drains safely, retains completed downloads, and does not start a late greeting or microphone capture.
5. Exercise unavailable-resource/entitlement fallback, network interruption, and process termination during native preparation. Confirm no duplicate owner, no false Ready state, and no needless redownload of completed ASR chunks.
6. Measure setup phases separately. Do not infer a fixed completion time from download progress or one device/model run.

**Acceptance:** On a supported signed device, ordinary locking or app switching does not reset first-time setup. If setup completes while away, returning does not show **Setup paused** or require another full start. If iOS ends the task, Mural preserves completed work and offers **Resume setup**. Only a native component interrupted before its safe completion checkpoint may need to run again.

A process eviction after successful setup can still require model reloading before recording is safe. The separate warm-return optimization in `todo.md` owns that latency; this plan does not promise instant model residency after process termination.

## Apple references

- [BGContinuedProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)
- [BGContinuedProcessingTaskRequest](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest)
- [Performing long-running tasks on iOS and iPadOS](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)
- [Background GPU Access entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.gpu)
- [Background Inference entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.inference)
- [`UIApplication.beginBackgroundTask`](https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(expirationhandler:))
