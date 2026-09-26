# Resumable first-time speech setup

Updated: 2026-09-24

Review base: `c67e3d302428fe79b2ecbe6664bc2cafe9c45ae0` on `mvp`.

Status: independently reviewed implementation direction. A source patch and automated evidence are not physical-device qualification. Do not enable optional native background compute until the qualification below passes.

## Product contract

**Mural preserves verified, reusable work. Background execution is best effort.**

Starting setup creates a durable job independently of the empty conversation draft. Ordinary foreground return reconnects to the same live job without a second tap. Relaunch after process loss offers **Resume setup**; it never silently starts expensive native work. Explicit cancellation never auto-resumes. Ready always requires the current process's normal native loading and contract validation.

“Preserved work” means actual surviving partial downloads, atomically published verified packages, and valid native caches/receipts. It does not mean model residency, an instruction-level native checkpoint, immunity to storage failure/OS cache eviction, or successful subcalls below an existing component's durable success boundary. A corrupt/missing cache is revalidated and rebuilt under existing rules, not trusted because a checklist says complete.

This feature does not change the Vietnamese staged Core AI encoder, Core ML decoder, precision, tokenizer, decoding policy, Taiwan backend, TTS policy, microphone policy, package security, or automatic-cloud-fallback prohibition. Warm conversation resume remains separate in `../../todo.md`.

## Independent review and material changes

The original plan gets the central decision right: resumability before background privileges; one existing native owner; durable sources authoritative; no fake native percentages; conversation audio foreground-only. The managed installer and preparation receipts already implement recovery, so neither needs replacement.

Simplifications:

* Keep one small job record and the existing `localTask`. Do not add a second native/download executor, durable work queue, generic workflow framework, custom Live Activity, background URLSession, or per-model shadow receipt database.
* An ordinary interruption does not need to cancel the orchestration task itself. Signal cancellation to the current child owner, await its actual drain, then park the same orchestration task until foreground. Explicit Cancel/system interruption can cancel the outer owner, but admission remains closed until it returns.
* Re-run preflight on **every** attempt, including an already-approved resume. Approval is permission for the compatible job, not evidence that downloads remain installed. Reuse existing verified package/cache/receipt paths rather than using the last saved stage as a program counter.
* Keep all upstream acquisition and native stages foreground-only in the MVP. Qualifying managed transfers does not qualify voice, VAD, model loading, or specialization.

Corrected Apple assumptions:

* Background Inference is for background **Neural Engine** access, including access outside a continued-processing task. It is not a blanket requirement for CPU-only Core ML. It is currently documented as beta and requires signed-device verification.
* `BGTaskScheduler.supportedResources` is a class property. GPU access needs both runtime support and the signed Background GPU Access entitlement. Do not invent CPU/ANE resource flags or infer signed capabilities from an entitlements source file.
* Submission success is not receipt of an active execution grant. The UI says it can continue away only after the handler has delivered the matching task and the current stage is eligible.
* Expiration has no reliable user-cancel-versus-resource-expiration reason parameter. Use one conservative `systemInterrupted` reason and explicit Resume for either. Never auto-resume after the system UI's Cancel.
* A task can disappear without any callback. Persist before work, at real boundaries, and before acknowledging a pause/cancel. A continuation's completion is not application Ready.
* Completed task UI is transient. “Open Mural to finish” must also be represented in the app's durable job/UI; do not promise that a completed system activity remains visible.
* Apple's current initializer documentation describes a permitted wildcard family, while WWDC25 also demonstrates a static identifier. Use one bundle-prefixed permitted family with an exact, unique submitted/registered suffix per lease. This isolates delayed deliveries from newer attempts without a second job queue. Verify configuration in the selected SDK and signed app.

Missing lifecycle cases now included: foreground return before native drain, background before task delivery, delivery after cancellation, expiration during publication, consent sheet dismissal during lifecycle changes, incompatible pair/voice changes, storage/protected-data failure, double completion, cancellation after native success but before receipt commit, and inactive foreground transitions before greeting/audio activation.

## Actual production resources at the review base

| Component | Source/configuration | MVP away policy |
| --- | --- | --- |
| Managed recognition installer | Existing bounded HTTP ranges, SHA-256, atomic publication | Eligible only with a delivered continued-processing lease |
| Vietnamese encoder | `PhoWhisperStagedEncoder.prepareForConversation`: `SpecializationOptions(preferredComputeUnitKind: .gpu)`; `AIModelCache.default`; persistent specialization | Foreground only |
| Vietnamese decoder | `stagedDecoderCompute = .cpuAndNeuralEngine`; existing staged decoder receipt | Foreground only |
| Vietnamese Mel validation/frontend | Explicit `.cpuAndGPU`, including final decoder/frontend validation | Foreground only; the encoder is not the only GPU-dependent component |
| Speech detection | `VadConfig(... computeUnits: .cpuAndNeuralEngine)` in both production recognizers | Foreground only; existing unavailable-detector policy unchanged |
| Mural Voice | `Supertonic3Manager(computeUnits: .cpuAndNeuralEngine, vectorEstimator: .aneBucketed(.int4))` | Acquisition and initialization foreground only until independently qualified |
| Taiwan recognition | Breeze's explicit CPU/Neural Engine encoder and decoder; Mel uses the pinned SDK's default | Foreground only; inspect the locked SDK default during physical qualification |
| Greeting/tutor/microphone/playback | Existing conversation/audio owners | Foreground only, never a setup background stage |

The repository entitlements contain Sign in with Apple, not proof of either native background capability. No signed binary or provisioning profile was inspected by this review. Add neither native entitlement speculatively.

## Durable state

Persist a bounded, versioned Codable `SpeechSetupJob` atomically in Application Support, outside learning/session records. The record contains job UUID, pair, preparation/consent compatibility identity, timestamps, status, current stage, last safe orchestration boundary, download approval, and a closed-set interruption reason. It contains no audio, transcript, arbitrary exception description, native pointer, model-resident flag, or cross-process Ready claim.

The compatibility identity includes the selected pair, qualified backend contract, selected voice/style, and reviewed package/catalog identity. A relevant contract or consent-scope change invalidates approval. It does not delete packages or caches. Native cache/receipt validation still detects device/OS/path/runtime changes.

Restore decodes a small envelope first. Unknown future schemas, malformed/oversized records, impossible dates, and incompatible identities cannot start work. Preserve assets and offer a new explicit setup; never silently reinterpret future fields. No age-only expiry should force model downloads: inventory, not elapsed time, determines missing work.

A successfully written cancelled record is not resumable automatically. A previously running, waiting, or prepared record is an interrupted job on cold launch; offer Resume, then revalidate. A `complete` job never bypasses current-process loading. Clear the job only when safely transitioning into the ordinary foreground conversation, or replace it after a new explicit setup decision.

Creation/approval writes must succeed before expensive work starts. Later checkpoint failure stops admission to new work and surfaces a recoverable storage error. Completed asset publication remains reusable even if the job record write failed. Do not swallow persistence failures while telling the learner everything was saved. Lock-screen data protection must be tested; do not weaken existing asset protection to manufacture background support.

## Single-owner control flow

The existing `runLocalPreparation` remains the only orchestrator. Its live loop is:

1. Wait for foreground when required, honour explicit cancellation, and await the existing child owners' drain.
2. Recheck pair/tutor availability and actual managed, voice, and detection inventory.
3. Obtain consent if the compatible job has not approved the required acquisition. Consent never authorizes unrelated future packages.
4. Download/verify/publish managed recognition files through the unchanged installer. Persist publication only after it succeeds.
5. End the managed-work continuation lease before entering unqualified work. If away, save `waitingForForeground` and park the same owner.
6. Run existing voice/detection/recognizer preparation, with real stage reporting. Existing cache/receipt lookups decide whether costly preparation can be skipped.
7. Perform authoritative in-process readiness checks. If inactive, wait; do not append a greeting, activate audio, record, or invoke tutor generation.
8. Enter the ordinary foreground greeting/conversation path, then clear setup orchestration state.

For ordinary backgrounding during a foreground-only operation, set the pause intent and checkpoint **before** requesting child cancellation. Do not discard the draft/job. Do not begin another component until the child returns and all cleanup drains. A quick foreground return only wakes the owner; it never opens admission early. A late result from an interrupted generation cannot become Ready.

For system interruption, explicit Cancel, pair/mode mutation, network failure, or process loss, preserve underlying work and follow the appropriate explicit-resume/cancel policy. App Cancel and system interruption are different durable reasons. Existing post-conversation assessment and warm-resume behavior remain separate.

The foreground waiter must be cancellation-safe and single-shot. Cancellation-before-wait, cancellation-during-wait, repeated scene notifications, and wake-before-drain all need tests. Clearing a system-task handle is never authority to clear the native owner.

## Continued processing

`App/SpeechSetupContinuation.swift` owns only BackgroundTasks registration/submission, lease identity, system progress/title, interruption forwarding, and exactly-once completion. It has no package/model business logic.

Register and submit a concrete identifier under one bundle-prefixed permitted family after explicit start/approval, while foregrounded. Use `.fail`; do not build an additional queue or wait indefinitely for permission. Request no optional native resources for the managed segment. A failed/unavailable submission leaves foreground setup usable and the keep-open message visible.

Deliveries and expiration handlers capture immutable lease identity. A late delivery for an ended lease is completed unsuccessfully and cannot attach to a new job. Completion detaches the lease before invoking callbacks. A lease ends at verified package publication or interruption; native admission remains independently owned until drain.

System progress must represent observed work, not time. Download bytes are range-validated received bytes; only the completed hash/publication boundary establishes a verified package. Verification remains indeterminate in the app unless its implementation reports real totals. Do not emit fake progress heartbeats to avoid expiration. A stalled task may be expired; resume handles that outcome.

`UIApplication.beginBackgroundTask` is optional bounded cleanup grace only. Balance it on every path and expire it promptly; never hold it open as a multi-minute native-compute mechanism. The guarantee must work even when no grace is granted.

## Learner UI

Keep the real Talk setup card, with completed/current/pending major work. Build its plan from relevant work, rather than presenting irrelevant download rows for every pair. Current-process completions are observations, not persisted readiness. On cold restore, label retained work as subject to checking; do not show verified checkmarks from the record alone.

Major stages: Checking setup; Downloading speech; Checking downloads; Preparing voice; Preparing speech recognition; Final checks; Ready.

Useful actual substages: Checking speech detection; Preparing speech detection; Preparing encoder; Preparing decoder; Loading speech models; Validating speech. Reuse `SpeechPreparationStep` and existing voice progress surfaces; add only missing boundary events. Normal learner text never includes framework names, precision names, ABI details, hashes, or native exception strings.

Only managed byte progress and SDK-provided voice download fractions are determinate. Native specialization/prewarm/load/validation is indeterminate. No countdowns, elapsed-time-derived fractions, or stage-count-as-time estimates.

Delivered lease + eligible current stage:

> You can lock your iPhone or switch apps. Mural will keep working when iOS allows. Completed work is saved.

Foreground-required stage or no delivered lease:

> Keep Mural open for this step. Everything already completed is saved if you leave.

Waiting away:

> Speech setup is partly complete. Open Mural to finish preparing speech.

Known OS interruption may say “Setup paused by iOS. Your completed work is saved.” When system cancellation cause is ambiguous, use “Setup paused. Your completed work is saved.” Both offer **Resume setup** and never silently restart.

Cold restore:

> Mural will check your retained speech files and completed setup work before continuing.

CTA: **Resume setup**. Do not promise a specific retained artifact until inventory verifies it. Cancellation has an immediate acknowledgment plus a truthful draining state, with Start/Resume disabled until real admission reopens. Large text and VoiceOver must distinguish complete/current/pending without colour alone.

## Implementation and acceptance sequence

1. Durable record/store, same-owner foreground waiting and safe cold restore. Test serialization, future/corrupt/incompatible records, consent recomputation, storage failure, cancellation and drain races. This is the primary feature, independent of background privileges.
2. Granular progress on the real Talk surface. Test actual download→verify, voice→recognition, encoder→decoder, final checks, waiting, Resume, cancellation/drain, large text and accessibility transitions.
3. Managed-work continued processing, using the existing installer and owner. Test delayed delivery, failed submission, lock/app switch, expiration/system cancellation, package publication boundary and exactly-once completion.
4. Optional native qualification, separately for each stage and pair. Inspect the signed app/profile, supported resources, locked SDK and physical device. Enable only a stage that independently passes. Unsupported GPU on the owner's iPhone is an accepted architecture outcome, not permission to redesign ASR.

Acceptance requires no duplicate owner, no false Ready, no unnecessary download or valid preparation rebuild, safe rerun of interrupted opaque components, explicit cold Resume, same-process automatic continuation, truthful stage/background guidance, and no background/late microphone, greeting, tutor or audio. Native cache/receipt reuse never removes normal model loading and ABI/shape validation.

Existing HTTP/installer tests remain authoritative for hosts, pins, strict ranges, surviving file lengths, corrupt partial recovery, full hashes, immutable publication, interrupted pointer publication and low storage. Existing receipt tests remain authoritative for cancelled/failed preparation and hit-plus-normal-load behavior. Do not weaken these tests to make setup appear resumable.

## Physical proof and stop conditions

Use the existing installed app container; do not uninstall, clear models, remove receipts, delete caches, or reset learning data. First qualify the current Vietnamese path on the owner's signed iPhone; then Taiwan separately. Simulator tests cannot qualify native compute or background execution.

Cover lock and app switch during managed download; foreground return before/after drain; background at encoder boundary and during native preparation; termination at each real durable boundary then explicit Resume; lease failure/late delivery/expiration/system cancellation; publication while backgrounded; no late greeting/microphone; retained bytes; encoder cache hit/miss; decoder receipt hit/miss; stage timing, memory and thermal warnings.

Log only job/attempt/lease IDs and closed-set states: job created/restored/incompatible; stage enter/complete/interrupted; checkpoint saved/failed; selected away policy; continuation submitted/started/rejected/completed/system-interrupted/stale-delivery; native drain begin/end; current-process validation and Ready. Reuse existing `speech_preparation_step`, `coreml_preparation`, encoder specialization and asset-verification logs; add an explicit cache lookup hit/miss event where currently absent. Never log audio/transcripts or raw user-facing exception payloads.

Stop and report on overlapping owners, early admission release, unvalidated Ready, new automatic backend fallback, security-check weakening, a requested qualified-model/precision/backend change, memory warnings/crashes/Jetsam, late audio, corrupted resume state, or unavailable signing/capability proof. A failure to gain optional background execution is not itself a reason to change the backend.

## Apple references checked for this review

* [BGContinuedProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)
* [BGContinuedProcessingTaskRequest](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest)
* [Request initializer and identifier family](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest/init(identifier:title:subtitle:))
* [Performing long-running tasks](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)
* [WWDC25: Finish tasks in the background](https://developer.apple.com/videos/play/wwdc2025/227/)
* [Supported resources](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/supportedresources)
* [Required resources](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest/requiredresources)
* [Background GPU Access](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.gpu)
* [Background Inference](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.inference)
* [beginBackgroundTask](https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(withname:expirationhandler:))

Related source history: validated Core ML preparation `3a2734c45929caff9c62bc9222d1534eac8d022d`; managed speech/pair setup `ca2364f9e28bc2b7c61acb5ede5b8d038b522e04`; warm conversation visibility `ebf9bc04e3b77fd1c8c1e38bb0199d4ce6c8a2b8`. See `speech-setup-ux.md`, `local-speech-findings-handoff.md`, and `app-store-model-provisioning-release-blocker.md`; model hosting and distribution remain separate release gates.
