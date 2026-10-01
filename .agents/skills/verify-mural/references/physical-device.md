# Physical-device verification

Read this reference for physical-phone or live-provider work, before preparing or executing those operations. It is not a prerequisite for simulator UI or documentation checks. The [parent skill](../SKILL.md) defines evidence selection and simulator safety; physical authorization and cleanup below remain mandatory. Run repository commands from the repository root.

## Local MVP workflow override

**Explicit native-device authorization override:** the qualified opt-in native local workflow below may replace manual operation when the user authorizes it and confirms an audible window. Without that authorization, keep the paired workflow. Native tests do not eliminate trust/unlock/microphone-permission or listening gates. Never collect room audio without separate permission.

For local MVP work, follow [local conversation's paired acceptance](../features/local-conversation.md#paired-acceptance), not the historical `mvp_plan.md` phase journal: the implementation agent builds/installs/launches directly and the user performs phone speech/listening checks. Do not spawn tester subagents. Read [local conversation](../features/local-conversation.md). Local probes need no OpenAI key; the key requirement and `--verify-audio`/`--verify-meaning` helpers below are premium-only. Preserve the confirmed existing phone bundle `com.kevintruong.mural.dev` using a build override, rather than installing the public default alongside it. Discover devices; use iOS 27 and Release for local timing.

**Preserve the local ASR backend when rebuilding.** The current paired iPhone 17 workflow uses the explicit staged Core AI opt-in, not ordinary Release. Before a phone build, read the current build recipe in [local conversation](../features/local-conversation.md) and the [Core AI checkpoint](../../../../docs/coreai/gpu-talk-checkpoint.md). Pass `OTHER_SWIFT_FLAGS='$(inherited) -D MURAL_COREAI_TALK'` for that local Release, including builds from detached worktrees. Confirm the actual app compiler command and the `local_talk_asr_backend` launch event; a correct commit and a successful Release build alone do not identify the backend. Public/default Release remains unchanged. Do not enable the opt-in for unrelated devices, simulator checks, or an explicitly requested baseline comparison.

**Collect evidence before asking the user to reproduce.** Read existing `.build/verification/` reports, saved Mural logs, and the installing session when supplied. For a new paired check, start or reuse a scoped Mural-only device capture before the user acts, record its ownership and starting offset, and ask for one short batch plus “done” or an approximate failure time. Do not require screenshots of timings already in logs. Use the bounded app-scoped console/capture ownership below and [local acceptance requirements](../features/local-conversation.md#physical-workflow); never silently collect a device-wide archive or claim a missing/redacted event proves success. If paired capture is unavailable, record that limitation rather than treating manual feedback as captured runtime evidence.

## Physical iPhone 17 and Device Hub

### Qualified opt-in native local workflow

See the [physical plan](../../../../docs/physical-iphone-e2e-plan.md) for acceptance evidence and limitations, and [lessons and optimization backlog](../../../../docs/physical-iphone-e2e-lessons.md) for failures, measured timings and qualified runtime optimizations. Qualified on the paired iPhone 17, iOS 27.2, with explicit Core AI Release and retained model/voice assets. This is separate from simulator verification and never a default dependency of `make build` or `make agent-verify`.

#### Select the affected behavior

The default `baseline` / `acoustic` / `multi` / `cancel` ladder below is the qualified **Vietnamese-English** path. For Chinese use [Breeze stages and their distinct status](../features/local-conversation.md#existing-native-automation), `DEVICE_PAIR=breeze-zh-CN-en` and a matching prepared artifact. Legacy `zh-CN-en` is FireRed research, not an alias or acoustic proof for Breeze. A build receipt's vi-en metadata does not select the user's runtime pair.

| Change / purpose | Smallest sufficient starting stage | Coverage boundary |
| --- | --- | --- |
| Real microphone / recognition path | `acoustic` | One actual acoustic turn, real reply and saved transcript; no relaunch |
| Conversation / durable transcript | `multi` | Two acoustic turns and exact text/count/order after normal relaunch |
| End during recording / recovery | `cancel` | Canceled recording drains, distinct new conversation completes; not inference cancellation or background execution |
| Native control / real-model baseline | `baseline` | Typed real-model turn; not acoustic input proof |
| Known synthetic-flow settings / selector recovery | `restore-settings` | Model-free; requires the recorded original meaning language, not a guessed value |
| Signing / runner / runtime / backend contract qualification | Applicable qualification ladder below | Do not treat an old pass as evidence for changed contracts |

For initial qualification, establish native control and real-model readiness (`baseline`), then one actual acoustic turn (`acoustic`), then `multi` and a fresh repeat after reviewing the first pass. Add `cancel` for its distinct lifecycle requirement. For changed contracts, rerun affected gates in that order. For routine feature checks on unchanged qualified contracts, choose the relevant stage, not the entire ladder; `multi` need not be preceded by a redundant `acoustic` or typed baseline.

#### Prepare first, then run one selected scenario

```sh
# Discover the exact physical UDID; never select by historical name alone.
xcrun devicectl list devices
export DEVICE_UDID='<freshly discovered physical UDID>'
make agent-verify-device DEVICE_STAGE=status
make agent-verify-device DEVICE_STAGE=prepare
# After preparation AND the readiness handoff, refresh process/lock state.
# status/stop-idle are administrative: vi-en here does not change the app's pair/backend.
make agent-verify-device DEVICE_STAGE=status DEVICE_PAIR=vi-en
# Only if this exact current PID exists and the user has confirmed idle ownership:
# make agent-verify-device DEVICE_STAGE=stop-idle DEVICE_PAIR=vi-en DEVICE_READY=YES DEVICE_IDLE_PID=<fresh-PID>
# If that PID exited, confirm absence. A new PID needs fresh bundle matching and current idle authorization.
# Example: conversation/persistence change, after confirming the audible window.
# Choose the stage from the table; do not run every stage by default.
make agent-verify-device DEVICE_STAGE=multi DEVICE_READY=YES \
  DEVICE_PLACEMENT='20-30 cm, microphone unobstructed, cool phone'
make agent-device-report  # Saved evidence only, no phone operations.
make agent-device-report DEVICE_RUN='.build/verification/physical-iphone-e2e/<run>'
```

`prepare` only builds/signs. It never installs, launches, plays or records, and does not require the screen unlocked. App and XCTest runner have separate identifiers: `com.kevintruong.mural.dev` and `com.kevintruong.mural.dev.physicaltests.xctrunner`. Keep the existing team, release flags, model/voice selection and main app data. If free provisioning has no available slot, stop; deleting any other app requires explicit authorization. The one-time QA deletion in the qualification log is not general permission to delete apps.

Runtime stages select a saved preparation only when source, app/test artifacts and device match; `DEVICE_PREPARED` can pin an explicit receipt. They launch a run-local copy of the fingerprinted `.xctestrun` directly, resolving its original product root and preserving signed identities/settings, explicit environment, selection, deadlines and locks. The original manifest is untouched; runtime does not resolve the project package graph. Incremental builds reuse original compiler-command evidence only for identical app executable bytes. Host-script edits alone no longer force recompilation. Never touch source timestamps or clear caches to manufacture a new compiler invocation.

Before runtime: close mirroring with ownership coordination; require idle/no personal conversation, an unlocked and cool phone, approved English/Vietnamese test pair, unobstructed microphone, and built-in Mac speakers at a user-agreed moderate unmuted volume. The test records/restores the original meaning preference through UI. It refuses active/paused personal Talk; no cloud fallback. Current user's comfortable volume is user-controlled; the runner only inspects it. It does not record the room.

The host launches the normal app with a scoped `devicectl --console` and `OS_ACTIVITY_DT_MODE=YES`, then native XCTest activates it. A fresh real backend event gates model work; `idevicesyslog` returned only `[connected]` in this runtime and is not acceptance evidence. Playback additionally needs the current native capture event and turn-specific Send-label UI marker. After successful bounded `afplay` completion, host transfers a fresh run/turn-specific random token into the XCTest runner's temporary container using `devicectl copy to` (minimum tool timeout five seconds, six-second host bound). Native XCTest requires its exact token within 12 seconds, keeps a 0.75-second trailing margin, and deletes the receipt before Send or recording cancellation. It never reads injected speech/text or writes Mural's data container; missing/wrong acknowledgments cannot release Send. Late/missing gates, changed route/fixture, early Send, wrong/duplicate turn, zero frames, model/resource faults, skips or incorrect results fail without automatic retry. Manual permission prompts are not auto-approved. Preparation temporarily holds the app's idle timer only while active, then restores it; manual locking and system Auto-Lock settings are unchanged.

Frozen fixtures live locally in `.build/verification/physical-iphone-e2e/fixtures-v1/`. If absent, generate them before playback and verify the runner's frozen hashes; do not silently accept new bytes:

```sh
mkdir -p .build/verification/physical-iphone-e2e/fixtures-v1
say -v Samantha -r 150 -o .build/verification/physical-iphone-e2e/fixtures-v1/turn-1.aiff 'I bought three apples on Tuesday.'
say -v Samantha -r 150 -o .build/verification/physical-iphone-e2e/fixtures-v1/turn-2.aiff 'My appointment is tomorrow morning.'
```

Case, punctuation, whitespace and the user-approved token `3=three` are the only equivalences. Preserve raw recognition. Initial setup reads/logs the original meaning preference and selects Vietnamese in one Settings visit. Later restoration and a separate readback visit remain intentional cleanup checks. `multi` checks both completed replies and exact text/count/order from one settled, transcript-scoped native snapshot after a normal relaunch; real passage visibility/scrolling remains required. `cancel` covers **End during recording**, drain and a distinct new conversation, not cancellation during inference or native background execution. Two full runs passed; physical speaker output was separately human-confirmed. TTS logs alone are never audible-output proof. No accent-wide, teaching-quality, cold-cache or sustained thermal benchmark is claimed.

Use saved operations instead of repeated inline scripts:

- `DEVICE_STAGE=status`: read-only lock/process status and the known content-free decoder receipt/container metadata, not acceptance. Missing receipt-copy evidence is explicitly recorded; no personal history or model files are copied.
- `DEVICE_STAGE=stop-idle DEVICE_READY=YES DEVICE_IDLE_PID=<fresh PID>`: only after the user confirms the app is idle. Verifies that exact PID against the installed main bundle under the device lock before termination. Never automatically terminate an unknown/personal session.
- `DEVICE_STAGE=restore-settings DEVICE_READY=YES DEVICE_RESTORE_MEANING='<recorded original>'`: bounded model-free recovery for this synthetic verification flow. Tests log the original preference. It also exercises the model-free playback-acknowledgment transport, diagnostics and nested synthetic-history dismissal. Do not guess the original value or use this to inspect personal history.

Routine runtime is bounded (420-second test-command ceiling, 300-second XCTest allowance, separately bounded cleanup); preparation has a 900-second ceiling. The retained FireRed research `resource` stage has a separately reviewed 1,020-second whole-runtime ceiling, 780-second test command and 720-second XCTest allowance, preserving six-minute loaded idle and native drain/+30-second observation. It requires a matching model-free `resource-check` and the [Simplified qualification plan](../../../../docs/asr/chinese/simplified-talk-qualification-plan.md), not the Vietnamese ladder or blanket authorization. Managed in-app acquisition and its token-redirect recovery passed. The subsequent native run `20260928-125336-34898` hit an iOS memory warning during recording before decode; resource qualification is BLOCKED, not permission for another attempt. See the [memory research handoff](../../../../docs/asr/chinese/firered-memory-research-handoff.md). See the plan for the explicit acquisition-only `provision` and recovery budgets, not the routine runtime allowance. These exceptions do not change routine budgets. Evidence includes automatic compact xcresult summaries even on failure, per-turn playback receipts, app-only logs, source/artifact identity, settings/cleanup and elapsed time. Failures do not become passes because cleanup succeeded. Review `cleanup.json`; settings-only recovery gets a separate run, preserving the original failure. SIGKILL/host-crash recovery is manual: inspect saved PID/PGID/command/start identities before stopping anything, then use exact device-scoped operations. No global kill, erase, uninstall, model/cache deletion or physical shutdown.

#### Efficient execution and diagnosis

1. Review saved reports and changed inputs first. Use `status` for current ownership/lock state and `agent-device-report` for saved evidence, not repeated ad hoc Python. Reporting successfully is not test acceptance.
2. Complete signing/build, fixture validation and applicable host-runner checks before asking the user to wait beside an unlocked phone. Preserve matching build receipts and warm assets. A discovery tunnel marked disconnected is not alone proof that wired control is unavailable; use bounded device status checks.
3. Consolidate the runtime readiness request: exclusive idle app, mirroring closed, cool/unlocked phone, agreed placement/output route/volume and listening availability. Carry approvals forward within that window; ask again only when readiness changed or a protected prompt requires action. Never change system Auto-Lock. The app's temporary preparation idle-timer hold does not remove unlock requirements.
4. Declare fixture and recognition equivalences before playback. Keep current-turn capture/UI gates, actual backend evidence and bounded state waits. Use the qualified completion acknowledgment, not fixture-duration sleeps; preserve its bounded wait and trailing margin. Requalify transport changes model-free first, then one actual acoustic turn before multi-turn/repeat and affected cancellation.
5. Diagnose the first failure from `failure.json`, compact xcresult when present, and scoped logs. A Make exit code alone is not the cause: distinguish a preflight ownership refusal, compilation failure, app fault and interrupted host. After a canceled tool call, do not launch again until saved cleanup or separate ownership-aware recovery plus fresh process checks establish that owned work stopped. For selector/cleanup bugs, reproduce and qualify the relevant model-free path before another expensive acoustic run. Scope queries to the active sheet/navigation container, use the actual accessibility element type, and scroll toward the target. Physical helpers now exit as soon as the target is hittable; preserve that behavior rather than repeating remote queries for the unused loop iterations.
6. Review automated outcome and cleanup separately, then request only needed human listening confirmation. Save unresolved gaps explicitly. No automatic retry after model/resource faults, and no reuse of old listening confirmation for new audio.

For a requested physical screenshot, use `xcrun devicectl device capture screenshot --device "$DEVICE_UDID" --destination "$EVIDENCE/screen.png" --timeout 15` only when the authorized app/surface is known to be foreground. Prefer an owned XCTest app screenshot when available. Do not use a default-display screenshot to discover whether a background Mural process is idle; it can capture unrelated personal content. This runtime's older `idevicescreenshot` path failed, so do not add DDI/signing/permission changes to rescue it. See the [session failure review](../../../../docs/physical-iphone-e2e-lessons.md#september-28-session-review-preventable-command-and-integration-mistakes).

For preparation-checklist regressions, native runtime samples real checklist accessibility states until Record is ready and rejects completed steps reverting. The copied test plan retains XCTest screen recordings on success and failure, without opening a mirror or recording the room. Export only the needed test's attachments using `xcrun xcresulttool export attachments --path <run>/baseline.xcresult --output-path <run>/attachments` (save verbose export output locally). Follow the source-decode and transition-inspection rules in [UI animation verification](../features/ui-animation.md). A passing sampled assertion alone does not prove every video frame.

Preparation receipt policy 2 uses canonical sandbox-relative model location, with absolute identity outside the sandbox. Install-related container UUID changes no longer cause false misses. Manifest/model/scope/OS/device/compute/policy invalidation and actual native loading/contract validation remain mandatory. A legacy receipt misses once. Diagnose content-free key differences using saved `status` evidence before changing policy; never force a hit or assume skipped prewarm removes all native loading cost.

`timings.json` now partitions host preflight/install/launch/test/result/cleanup (or build/validation for `prepare`). Native device-uptime intervals measure UI setup, preparation, recording, Send-to-Ready, assertions, persistence and teardown; they overlap the host test phase and must not be added to its total. Saved playback receipts include completion and acknowledgment-transfer times. `agent-device-report` displays the breakdown without phone access.

Matched retained-cache two-turn/persistence runtime measured **221.25 s before, 159.02 / 157.55 s after**, all including cleanup and unchanged scenario assertions, about 28% shorter in this small sample. Build was separate (19.59 s baseline preparation, 16.39 s optimized preparation). The four follow-up improvements and checklist fix measured **155.96 / 152.56 s**, an observed further 2.5% reduction with added checklist/video coverage, not an isolated identical-instrumentation comparison. Separate production rebuild: 40.64 s. Mandatory first native loading still took 19.40 / 16.54 s despite receipt hits. Both final runs passed real acoustic/model/persistence/cleanup checks, and the user separately confirmed both replies audible in each. Do not promise these gains on another runtime or call them faster inference. Evidence remains in the linked lessons/plan.

### Device Hub manual/premium fallback

Use this path only for behavior that cannot be proved on a simulator. Discover the current identifier every time; the currently paired phone is named `Kevq`, but names and UDIDs can change:

```sh
xcrun devicectl list devices
# Set DEVICE_UDID to the available paired iPhone 17 UDID printed above.
: "${DEVICE_UDID:?Set DEVICE_UDID to the available paired iPhone 17 UDID}"
```

Prepare a signed build through the qualified recipe above or the current [paired local recipe](../features/local-conversation.md), preserving the existing bundle, signing team, intended backend and assets. Do not substitute a generic public Debug build for the paired Core AI Release. Premium-only Debug helpers require an explicitly approved matching Debug build; they are not a reason to switch backends during unrelated verification.

Before install/launch, refresh status and establish authorized idle ownership as above. If needed, use the saved exact-PID `stop-idle` operation, not blanket `--terminate-existing`. Select the actual artifact from that approved preparation, never a guessed DerivedData path:

```sh
: "${DEVICE_APP:?Set the authorized signed Mural.app artifact from preparation}"
export APP_BUNDLE_ID=com.kevintruong.mural.dev  # Existing paired phone bundle, not the public default.
test -d "$DEVICE_APP"
xcrun devicectl device install app --device "$DEVICE_UDID" "$DEVICE_APP"
xcrun devicectl device info apps --device "$DEVICE_UDID" --bundle-id "$APP_BUNDLE_ID"
xcrun devicectl device process launch --device "$DEVICE_UDID" "$APP_BUNDLE_ID"
```

If signing, trust, Developer Mode, or device availability blocks the build or install, record that blocker. Do not edit signing configuration or remove the installed app. An installed app from an older revision is not evidence for the current checkout.

Device Hub is the input and display fallback for the physical phone. Open it with:

```sh
open /Applications/Xcode-beta.app/Contents/Applications/DeviceHub.app
```

Select the same phone, choose **View Screen**, and wait for a settled frame. For typed input, keep the selected device window visible and frontmost and enable **Capture Keyboard**. Turn it off again afterward. Device Hub paste can use the phone's clipboard instead of the Mac clipboard, so inspect the field before sending or leaving it. If the phone's own voice dictation inserts unrelated text, stop and resolve that competing input before continuing.

If Device Hub shows live frames but taps no longer alter the phone:

1. Coordinate ownership, then quit the Device Hub instance used by this check from its app menu. Do not close another session's windows. Closing only the device window is not enough and may recreate it.
2. Reopen `/Applications/Xcode-beta.app/Contents/Applications/DeviceHub.app`.
3. Select the same phone and choose **View Screen**.
4. Leave **Capture Keyboard** off unless typing is the next action.
5. Send one harmless navigation action and verify the resulting settled screenshot.
6. If it still has no visible effect, stop and report input as blocked instead of retrying indefinitely.

For microphone recording or live voice capture, fully quit Device Hub before testing. Use the explicitly authorized native local runner above, or operate the iPhone directly for manual checks. Device Hub can interfere with microphone capture even while a recording timer advances. Use Device Hub for typed input and visual control, not as proof of microphone behavior.

## Live AI checks

A valid OpenAI key is required for a completed provider response. Enter it only in **Settings > Advanced > Use your own API key** on the phone. Never read it from Keychain, pass it through `devicectl`, or include it in evidence.

With a key and an approved live run, select the affected checks below on the physical iPhone. Use the full journey for a broad provider-integration change, not automatically for an unrelated edit:

1. Open a new conversation and review/accept AI consent.
2. Confirm microphone permission, the greeting, and a settled nonempty response.
3. Send a short typed reply when using Device Hub input; confirm the learner passage and provider response.
4. Toggle Meaning and confirm a translation while active and after ending.
5. Mute, end, and relaunch; confirm the visible state and audio release.
6. Exercise one network or provider failure and confirm the user-facing error.

The app includes explicit Debug helpers that write content-free reports using temporary learning data. Use only an authorized matching Debug build and refresh status/idle ownership before each launch; resolve any existing process through the saved exact-PID operation:

```sh
xcrun devicectl device process launch --device "$DEVICE_UDID" "$APP_BUNDLE_ID" --verify-audio
xcrun devicectl device copy from \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$APP_BUNDLE_ID" \
  --source Documents/audio-verification.json \
  --destination "$EVIDENCE/audio-verification.json"

xcrun devicectl device process launch --device "$DEVICE_UDID" "$APP_BUNDLE_ID" --verify-meaning --verify-language=es
xcrun devicectl device copy from \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$APP_BUNDLE_ID" \
  --source Documents/meaning-verification.json \
  --destination "$EVIDENCE/meaning-verification.json"
```

These helpers incur API usage and are not substitutes for listening or checking the settled phone UI. With no API key, do not claim them as passed. When the key or authorization is unavailable, report live-provider acceptance as blocked separately from any proven missing-key, consent, or failure UI.

