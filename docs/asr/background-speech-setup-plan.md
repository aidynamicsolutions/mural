# Background First-Time Speech Setup Plan

**Status:** Owner-reviewed revised direction; implementation not started.

**Updated:** 2026-09-24

This plan covers the expensive first-time on-device speech setup. It is separate from the warm conversation-resume delay tracked in ../../todo.md.

## Product decision

The guarantee is **resumability**, not unconditional background execution.

A learner who starts first-time speech setup should not lose useful completed work merely because they lock the iPhone, switch apps, iOS ends a background task, the network drops, or the process is later relaunched.

Background continuation is an optimization layered on top of that guarantee:

- Continue a stage in the background only when the real operation, current device, signed entitlements, and iOS resource policy permit it.
- When a stage cannot legally or reliably continue in the background, stop at the nearest real safe boundary and resume it when Mural returns to the foreground.
- Never claim to resume inside an opaque Core ML, Core AI, or upstream SDK call. If that call was interrupted before its success boundary, rerun that component.
- Never repeat a completed download, verified package publication, valid Core AI specialization/cache, or valid Core ML preparation step unnecessarily.
- Never declare speech Ready from a persisted flag alone. The current process must still load and validate the resources required to record safely.

For the learner, the intended behavior is simple:

> Start setup once. Mural keeps completed work. If iOS lets setup continue while you are away, it does. If a step needs Mural open, Mural says so. Returning to the same live setup resumes automatically; after process termination or an explicit stop, Mural offers Resume setup.

## Current behavior and existing strengths

Today, when first-time setup is in progress and Mural backgrounds, ConversationCoordinator.background() cancels speech setup and ends the empty draft. Tapping **Prepare & start** starts orchestration again.

Several underlying components already have the right recovery properties:

- Core/LocalSpeechProvisioning.swift keeps partial managed ASR package files, resumes from actual surviving file lengths with strict HTTP ranges, rehashes completed files, and publishes verified packages atomically.
- Valid downloaded assets remain reusable after cancellation or process loss.
- Core/CoreMLPreparationReceipt.swift records only successful preparation for an exact model/path/device/OS/compute contract. A matching receipt can skip explicit Core ML prewarming, but normal model loading and contract validation remain authoritative.
- The current Vietnamese path uses a persistent Core AI specialization/cache for the staged encoder plus a Core ML decoder preparation receipt/cache. A successful first setup is therefore designed to make later starts much cheaper.
- Existing cancellation and admission rules keep one model owner active until native work drains; stale late results do not become Ready or start a second owner.

The missing layer is durable setup orchestration: today the coordinator treats backgrounding as the end of first-time setup rather than as an interruption to a resumable job.

Relevant existing documentation is in speech-setup-ux.md. Relevant code is primarily App/ConversationCoordinator.swift, App/LocalConversationEngine.swift, App/LocalNeuralTTS.swift, Core/LocalSpeechProvisioning.swift, Core/CoreMLPreparationReceipt.swift, Core/SpeechPreparationStep.swift, and Core/SpeechSetupProgress.swift.

## 1. First principle: model setup as a resumable pipeline

Treat first-time setup as a sequence of stages with different durability and resource requirements, not as one monolithic background operation.

The logical pipeline is:

1. Restore/check previous setup state.
2. Validate selected speech pair and tutor availability.
3. Inspect installed recognition, voice, and speech-detection assets.
4. Ask for download consent when required.
5. Download managed recognition assets.
6. Verify and atomically publish recognition assets.
7. Acquire any upstream-owned voice/style or speech-detection assets.
8. Prepare the selected voice.
9. Prepare speech detection.
10. Prepare/validate the selected ASR backend:
   - Vietnamese: staged Core AI encoder work plus Core ML decoder work under the current production path.
   - Taiwan: Breeze/WhisperKit Core ML work under the current production path.
11. Perform final in-process readiness checks.
12. If foregrounded, start the greeting/conversation. If backgrounded, wait for foreground.

Not every pair executes every stage. Build the planned stage list from the selected pair and actual missing work.

Each stage must declare:

- whether its result is durable across process death;
- how its success is revalidated;
- what resources it requires;
- whether it may continue under BGContinuedProcessingTask on this signed device;
- whether it has real measurable progress;
- what the learner should see.

## 2. Persist one minimal SpeechSetupJob

Add a small versioned, Codable setup record, persisted atomically outside the conversation draft.

Suggested fields:

- schema version;
- setup job UUID;
- LocalSpeechPair;
- selected ASR/model identity needed to detect an incompatible resume;
- createdAt / updatedAt;
- status: running, waitingForForeground, needsResume, cancelled, failed, complete;
- last fully completed orchestration boundary;
- current learner-facing stage for restoration/diagnostics;
- whether the user explicitly approved downloads;
- optional interruption reason suitable for non-sensitive diagnostics.

Do **not** persist claims such as modelResident = true or nativePrepared = true as cross-process readiness.

The persisted record is an orchestration hint. Durable underlying state remains authoritative:

- managed package files and active package pointer;
- upstream voice/VAD cache inventory;
- Core AI cache lookup/identity validation;
- Core ML preparation receipt;
- normal native load and ABI/shape validation.

On restore, recompute the remaining work from those real sources rather than blindly trusting the saved stage number.

Prefer a small atomic Application Support record rather than coupling setup lifetime to an empty SessionRecord. A greeting-only/empty conversation draft should not own whether expensive model setup survives.

## 3. Resume semantics

### Same process, ordinary lock/app switch

If the learner merely backgrounds or locks the iPhone and later returns to the same live process:

- if the existing setup owner is still running, reconnect the UI to that same owner;
- if setup paused because the next stage required the foreground, automatically continue the same user-initiated job when Mural becomes active;
- do not require another **Prepare & start** tap;
- never create a second model/download owner.

### Process termination / task loss

If Mural launches and finds a persisted setup job that was running or waiting when the previous process disappeared:

- treat it as interrupted, not still running;
- revalidate all durable state;
- show **Resume setup** with a concise summary of what was kept;
- do not silently restart expensive native work.

### Explicit cancellation or force quit

An explicit Cancel should persist cancelled state and never auto-resume.

A force quit may not provide a reliable callback. On the next launch, a previously running job should therefore be presented as **Resume setup**, not silently restarted.

### Native operation interrupted in flight

If iOS ends the task during an opaque native operation:

- retain all earlier completed stages;
- return to the previous safe boundary;
- rerun only the interrupted native component when setup resumes;
- do not claim instruction-level continuation inside Core ML/Core AI/FluidAudio/WhisperKit.

## 4. Background continuation policy

Use BGContinuedProcessingTask only as a continuation wrapper around the existing single setup owner. Do not create a second background copy of runLocalPreparation().

Create a small App/SpeechSetupContinuation.swift whose responsibilities are limited to:

- register the permitted task identifier;
- submit a user-initiated continued-processing request;
- request only resources that the upcoming stage actually requires;
- expose the active system task to the existing setup owner;
- update system title/subtitle/progress;
- forward expiration/cancellation to the same setup owner;
- complete the system task exactly once.

The continuation wrapper must not own download/model business logic.

### Submission strategy

For the MVP, prefer immediate/fail behavior rather than building another queued setup state.

If iOS cannot grant continued processing immediately:

- continue the existing setup while Mural is foregrounded;
- clearly tell the learner that Mural must remain open for the current setup;
- preserve resumability if they leave anyway.

Do not block setup waiting indefinitely for a background-task slot.

### Per-stage eligibility

Evaluate eligibility per stage, not with one global backgroundSupported Boolean.

Examples:

- Managed recognition download: network/CPU; continue under the task when available.
- Package verification: CPU/file I/O; continue when permitted.
- Voice/VAD acquisition or preparation: use actual SDK/resource requirements; do not promise background behavior before qualification.
- Core ML CPU/Neural Engine work: background only when the signed build has the required Background Inference capability and physical-device testing confirms the actual operation.
- Vietnamese staged Core AI GPU work: treat as foreground-only on iPhone unless BGTaskScheduler.supportedResources and the actually signed entitlement prove that this device/build may request the required GPU resource.
- Greeting, microphone capture, recording, and conversation audio: always foreground-only.

Do not infer requirements from the model name. Inspect the actual compute configuration used by each current Release path.

### Foreground-only boundary while already backgrounded

If a background-capable stage completes and the next required stage is foreground-only:

1. commit/verify the completed durable work;
2. persist waitingForForeground;
3. update system/user messaging to say that Mural needs to be opened to finish;
4. complete the continued-processing task;
5. do not start the foreground-only native call.

On foreground return, automatically continue the same job after revalidation.

### Backgrounding during a foreground-only native call

Request cancellation through the existing owner immediately.

UIApplication.beginBackgroundTask may be used only as a short grace period to drain/persist safely. It is not the multi-minute setup mechanism.

If the opaque native call does not return before iOS suspends/terminates the process, recovery starts from the previous safe boundary on Resume.

## 5. Keep the existing managed downloader for this MVP

Do not rewrite LocalSpeechProvisioning to a background URLSession merely to support this feature.

The current downloader already provides the important correctness properties:

- independent reviewed/pinned package metadata;
- allowed-host policy;
- strict Content-Range validation;
- bounded response buffering;
- resume from surviving file length;
- full SHA-256 verification;
- immutable/atomic publication.

Running that existing installer under continued processing preserves those properties and gives resumability even if the system ends the task.

A background URLSession migration can be evaluated separately if later needed. It should not be mixed into this patch because it changes networking/lifecycle behavior and deserves an independent security/recovery review.

## 6. Granular learner-facing progress

The learner should always be able to answer three questions:

1. What is Mural doing now?
2. What has already finished?
3. Can I safely leave the app during this step?

Extend SpeechSetupProgress so native preparation is no longer presented as one generic **Getting speech ready…** stage.

Prefer a checklist of real work rather than a fake overall percentage.

Example:

- ✓ Speech files downloaded
- ✓ Downloads verified
- ✓ Mural Voice ready
- ● Preparing speech recognition
  - Preparing encoder…
- ○ Final checks

Then, when the subphase changes:

- ✓ Speech files downloaded
- ✓ Downloads verified
- ✓ Mural Voice ready
- ● Preparing speech recognition
  - Preparing decoder…
- ○ Final checks

The UI may collapse steps that do not apply to the selected pair.

### Proposed major user stages

Keep the UI understandable while allowing internal subphases:

1. **Checking setup**
2. **Downloading speech**
3. **Checking downloads**
4. **Preparing voice**
5. **Preparing speech recognition**
6. **Final checks**
7. **Ready**

Useful recognition subphases include:

- Checking speech files
- Preparing speech detection
- Preparing encoder
- Preparing decoder
- Loading speech models
- Validating speech models

Do not expose internal framework names such as Core AI, Core ML, WhisperKit, PAL8, FP8, or model hashes in the normal learner UI. Keep those in diagnostics.

### Progress rules

- Managed recognition downloads: show verified received bytes and a real percentage.
- Upstream voice/style downloads: show an SDK fraction only when the SDK provides a real fraction.
- File verification: indeterminate unless there is a trustworthy file/byte total that the implementation can report.
- Native prewarm/load/specialization/validation: use named stage/substage plus indeterminate progress unless the underlying API provides real progress.
- Never invent a countdown.
- Never turn stage count into an estimated time percentage.
- The system continued-task progress may use completed work units/stages, but messaging must make clear it represents work completed, not a time estimate.

### Background-safety message

Show stage-specific guidance directly in the setup card.

When the current stage is background-capable on this device/build:

> You can lock your iPhone or switch apps. Mural will keep working when iOS allows. Completed work is saved.

When the current/next stage requires foreground:

> Keep Mural open for this step. Everything already completed is saved if you leave.

When setup reaches a foreground-only boundary while the app is away:

> Speech setup is partly complete. Open Mural to finish preparing speech.

When iOS interrupts the job:

> Setup paused by iOS. Your completed work is saved.

CTA: **Resume setup**

On cold relaunch with retained progress:

> Your speech files and completed setup work were kept. Mural will check them before continuing.

CTA: **Resume setup**

Do not say **Setup paused** merely because the app entered the background if work is still genuinely progressing.

## 7. System progress / Live Activity behavior

Use the system UI supplied by BGContinuedProcessingTask rather than introducing a second custom Live Activity for the MVP.

Keep title/subtitle aligned with the same learner-facing stage:

- Preparing speech for Mural
- Downloading speech — 412 MB of 1.2 GB
- Checking downloaded speech
- Preparing your voice
- Preparing speech recognition — encoder
- Preparing speech recognition — decoder
- Open Mural to finish setup

System cancellation must cancel the same setup owner.

If cancellation occurs:

- stop admitting new setup/model work;
- let existing native drain rules remain authoritative;
- preserve durable completed work;
- mark the job cancelled or needsResume according to the cancellation source;
- never append a late greeting or start the microphone.

## 8. Conversation boundary

Speech setup and conversation start are separate responsibilities.

Background setup must never:

- activate the microphone;
- start recording;
- play the greeting;
- append a greeting that implies a live conversation has started;
- start tutor generation.

If all required resource preparation completes while Mural is backgrounded:

- mark the setup job complete/prepared for this process as appropriate;
- finish the system background task;
- wait for Mural to become active;
- then enter the existing foreground greeting/conversation path.

If the process was terminated after setup completion, normal restore rules still require authoritative load/validation before Ready.

## 9. Exact implementation boundaries

### App/ConversationCoordinator.swift

Change background/lifecycle orchestration:

- remove unconditional first-setup cancellation merely because the app backgrounds;
- keep one localTask/setup owner;
- attach/reconnect SpeechSetupContinuation to that owner;
- persist SpeechSetupJob boundaries;
- automatically continue waitingForForeground work on ordinary foreground return in the same process;
- on cold restore, show Resume instead of auto-starting heavy work;
- prevent greeting/microphone start while inactive;
- retain generation/session identity and late-result protections.

Do not duplicate runLocalPreparation().

Refactor it only enough to expose real stage boundaries and to allow resume to recompute remaining work.

### Core/SpeechSetupProgress.swift

Expand learner-facing stages/substages.

Keep the current invariant that only real downloadable progress can advertise a fraction/bytes.

Add enough information for the UI to show:

- completed major stages;
- current major stage;
- current substage;
- whether the current stage is safe to continue away from Mural;
- whether foreground is required.

Keep diagnostic/native strings separate.

### New minimal SpeechSetupJob persistence

Place the small versioned record where it fits the current Core/App persistence architecture.

Requirements:

- atomic writes;
- no audio/transcript content;
- safe decode/migration for future schema changes;
- stale/incompatible job invalidation;
- explicit clear on successful transition into normal conversation or user cancellation as appropriate.

### New App/SpeechSetupContinuation.swift

Own only BackgroundTasks integration and system progress/cancellation.

### Core/LocalSpeechProvisioning.swift

For the first implementation, preserve installer architecture and security rules.

Only add narrowly scoped progress/restoration surfaces if the coordinator cannot derive them today.

### App/LocalConversationEngine.swift / LocalNeuralTTS.swift

Do not change model weights, precision, decoder policy, ASR quality, or compute placement merely for background support.

Expose/propagate more precise setup stage information where needed:

- voice acquisition versus initialization;
- speech-detection preparation;
- encoder preparation;
- decoder prewarm/load;
- validation.

Current native ownership/cancellation boundaries remain in force.

### App/Info.plist and entitlements

Add the permitted continued-processing task identifier.

Do not claim or add Background GPU / Background Inference capabilities as available until the actual signing path is approved and verified.

Runtime capability checks and signed-entitlement checks must drive the final per-stage background policy.

## 10. Implementation sequence

### Phase 1 — Resume-first state machine

Implement before relying on any background compute capability.

- Add SpeechSetupJob persistence.
- Separate setup lifetime from the empty draft.
- Recompute remaining work from durable state.
- Automatically resume on ordinary same-process foreground return.
- Show Resume setup after process loss/cold launch.
- Preserve explicit Cancel semantics.
- Add focused unit/coordinator tests.

Success means backgrounding can no longer reset useful setup work even if every native stage still has to run in the foreground.

### Phase 2 — Granular progress UX

- Extend SpeechSetupProgress.
- Add checklist/completed-stage presentation.
- Add encoder/decoder/voice/detection/final-check substages.
- Add clear safe-to-leave versus keep-Mural-open copy.
- Add interruption and Resume copy.
- Keep percentages truthful.
- Add accessibility/large-text simulator coverage.

### Phase 3 — Continued processing for background-capable work

- Add SpeechSetupContinuation.
- Register one permitted identifier.
- Start it only after the user explicitly starts/approves setup.
- Use the same existing setup owner.
- Continue managed downloads/verification where permitted.
- Stop at foreground-only boundaries.
- Reconnect on foreground return.
- Exercise system cancellation and expiration.

### Phase 4 — Qualify optional native background resources

On the actual physical target device and signed build:

- inspect BGTaskScheduler.supportedResources;
- verify the signed entitlements/provisioning profile;
- independently test CPU-only, Neural Engine, and GPU-requiring stages;
- enable background native execution only for stages that pass.

If the Vietnamese Core AI GPU stage is unsupported on the target iPhone, that is an accepted architecture outcome: preserve the completed prior work, wait for foreground, then finish the GPU stage.

Do not change the qualified speech backend merely to make that one stage background-capable.

## 11. Test matrix

### Resume and persistence

1. Background during preflight.
2. Background halfway through managed ASR download.
3. Background after download but before publication.
4. Background after package publication.
5. Background during voice acquisition.
6. Background during native encoder preparation.
7. Background during decoder preparation.
8. Relaunch after process termination at each durable boundary.
9. Relaunch with an old/incompatible persisted job.
10. Explicit Cancel followed by relaunch.

For every case, verify:

- no false Ready;
- no duplicate setup owner;
- no unnecessary redownload;
- no unnecessary rerun of successfully durable native preparation;
- interrupted opaque calls rerun safely;
- the correct Resume/auto-resume behavior occurs.

### Continued-processing behavior

1. Lock the screen during a supported stage.
2. Switch to another app during a supported stage.
3. Return while the task is still active.
4. Return after a supported stage finishes.
5. Reach a foreground-only stage while away.
6. Trigger/observe task expiration.
7. Cancel through the system task UI.
8. Exercise submission failure/unavailable background capability.

### UX/progress behavior

Verify the setup card changes through the actual phases, not only settled screenshots:

- checklist completion;
- byte progress;
- download -> verification transition;
- voice download -> voice preparation;
- encoder -> decoder transition;
- waiting for foreground;
- interrupted/Resume;
- cancelling/draining;
- Ready.

At every phase confirm that the safe-to-leave message matches the real execution policy.

### Safety

- No greeting while backgrounded.
- No microphone activation while backgrounded.
- No late greeting after cancellation/expiration.
- No mode/pair mutation starts a second owner while the old one drains.
- No receipt written after cancelled/failed native preparation.
- Full package/model validation still gates Ready.
- Thermal/memory safety behavior remains intact.

## 12. Physical-device proof and telemetry

Use content-free structured logging for setup boundaries:

- setup job id/generation, but no user content;
- stage enter/complete/interrupted;
- background policy selected;
- continued task submitted/started/completed/expired;
- durable resume source: package partial, package installed, Core AI cache hit/miss, Core ML receipt hit/miss;
- native component timing;
- Ready.

Do not log audio or transcript content.

Measure stages separately. Do not infer a fixed completion estimate from one phone or from download percentage.

The first physical qualification should use the current production Vietnamese path on the owner's iPhone, because it has the most complicated resource mix. Then qualify the Taiwan path separately.

## 13. Acceptance criteria

The feature is accepted when all of the following are true:

1. A learner starts first-time setup once.
2. Locking the iPhone or switching apps never resets already completed useful work.
3. Background-capable work continues when iOS permits it.
4. When the next stage requires Mural in the foreground, the app says so clearly and waits without discarding prior progress.
5. Returning to the same live process automatically continues the existing user-initiated setup job where appropriate.
6. After process termination/task loss, Mural shows **Resume setup**, revalidates durable state, and reruns only missing/interrupted work.
7. Managed ASR downloads resume from verified surviving bytes rather than starting over.
8. Valid Core AI/Core ML preparation caches/receipts are reused under their existing correctness rules.
9. No second setup/model owner can overlap the first.
10. No microphone, greeting, or conversation audio starts while backgrounded.
11. Native work without a real progress callback never displays a fake percentage/countdown.
12. The UI exposes enough stage granularity that the learner can tell what has finished, what is happening now, and whether it is safe to leave Mural.
13. Speech becomes Ready only after the current process completes the authoritative native load/validation required for recording.

A process eviction after successful setup can still require normal model reloading before recording is safe. The separate warm-return optimization in todo.md owns that latency; this plan does not promise permanent model residency.

## Non-goals

This work does not:

- change Vietnamese or Taiwan ASR weights/precision/decoding quality;
- replace the Core AI production path merely to obtain background GPU access;
- guarantee iOS will always finish setup while the screen is locked;
- checkpoint inside an opaque native SDK call;
- introduce a second custom Live Activity;
- migrate the managed installer to background URLSession;
- solve App Store model hosting/provisioning;
- solve warm conversation resume after process eviction.

## Apple references

- BGContinuedProcessingTask: https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask
- BGContinuedProcessingTaskRequest: https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest
- Performing long-running tasks on iOS and iPadOS: https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados
- BGTaskScheduler supportedResources: https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/supportedresources
- Background GPU Access entitlement: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.gpu
- Background Inference entitlement: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.inference
- UIApplication.beginBackgroundTask: https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(expirationhandler:)
