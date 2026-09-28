---
name: verify-mural
description: Verify Mural through bounded simulator checks or explicitly authorized native XCUITest on iPhone 17 for real local microphone, models, speech and persistence. Use serve-sim for simulator UI and Device Hub only for physical typed/visual fallback, never microphone acceptance. Use after user-visible or audio/model changes, when reproducing UI bugs, and before claiming work complete.
---

# Verify Mural

## Local MVP workflow override

**Explicit native-device authorization override:** the qualified opt-in native local workflow below may replace manual operation when the user authorizes it and confirms an audible window. Without that authorization, keep the paired workflow. Native tests do not eliminate trust/unlock/microphone-permission or listening gates. Never collect room audio without separate permission.

For local MVP work, follow `mvp_plan.md`'s current paired-verification workflow: the implementation agent builds/installs/launches directly and the user performs phone speech/listening checks. Do not spawn tester subagents. Read `features/local-conversation.md`. Local probes need no OpenAI key; the key requirement and `--verify-audio`/`--verify-meaning` helpers below are premium-only. Preserve the confirmed existing phone bundle `com.kevintruong.mural.dev` using a build override, rather than installing the public default alongside it. Discover devices; use iOS 27 and Release for local timing.

**Preserve the local ASR backend when rebuilding.** The current paired iPhone 17 workflow uses the explicit staged Core AI opt-in, not ordinary Release. Before a phone build, read the current build recipe at the top of `features/local-conversation.md` and `docs/coreai/gpu-talk-checkpoint.md` in the repository. Pass `OTHER_SWIFT_FLAGS='$(inherited) -D MURAL_COREAI_TALK'` for that local Release, including builds from detached worktrees. Confirm the actual app compiler command and the `local_talk_asr_backend` launch event; a correct commit and a successful Release build alone do not identify the backend. Public/default Release remains unchanged. Do not enable the opt-in for unrelated devices, simulator checks, or an explicitly requested baseline comparison.

**Collect evidence before asking the user to reproduce.** Read existing `.build/verification/` reports, saved Mural logs, and the installing session when supplied. For a new paired check, start or reuse a scoped Mural-only device capture before the user acts, record its ownership and starting offset, and ask for one short batch plus “done” or an approximate failure time. Do not require screenshots of timings already in logs. Follow the logging procedure in `features/local-conversation.md`; never silently collect a device-wide archive or claim a missing/redacted event proves success.

## Purpose

Prove Mural through the closest practical user path. A successful build or an acknowledged tap is supporting evidence, not proof that the app works.

Mural has two useful verification surfaces:

| Surface | Use it for | API key needed |
|---|---|---:|
| iOS Simulator plus `serve-sim` | Onboarding, consent, navigation, themes, words, settings layout, preview data, reset, history, screenshots, and native UI tests | No |
| Physical iPhone 17 | Opt-in native XCUITest for real local microphone/model/speech/persistence; Device Hub for premium typed/visual checks only | No for local; yes for live provider responses |

The physical iPhone is the primary acceptance surface for real microphone, ASR/tutor/TTS, audible output and native lifecycle behavior. Simulator checks remain the faster supporting surface for UI and synthetic guards. Select by the changed behavior; do not require both surfaces or the full physical qualification ladder for every change. A passing recording-cancellation test does not qualify background execution or inference cancellation.

The current environment does not have an OpenAI API key. Prove the missing-key and consent guards, but report live provider response checks as blocked. Never add a key to a command, source file, screenshot, or evidence artifact.

Run commands from the repository root. The app bundle identifier is `no.william.mural`. Simulator verification must use the checked-in lifecycle below; physical recipes remain separate and opt-in.

## Mandatory simulator lifecycle

Reuse `Mural Lifecycle Verification`, UDID `C094F154-7674-4A17-9F6B-319959B1F49A` (iPhone 17 / iOS 27.0), as the single persistent project device across tasks, retries and worktrees. Confirm availability and Shutdown before use. If busy, wait rather than create a substitute. Never create per-test devices or parallel test-worker clones. If missing, inspect the inventory before deliberately replacing it. Additional migration/runtime/screen-size devices require a concrete coverage gap, user approval and an agreed deletion plan before creation; export evidence and delete only those approved temporary devices afterward. Retain the primary device's app/model data.

```sh
make build  # Generic arm64 simulator compilation only; never boots a device.
make agent-verify SIM_UDID="$SIM_UDID"  # Three-check smoke fallback.
make agent-verify SIM_UDID="$SIM_UDID" TESTS='testThemeSearchFiltersLocally'
make agent-verify SIM_UDID="$SIM_UDID" VERIFY_SUITE=qualification
make agent-verify SIM_UDID="$SIM_UDID" SIMULATOR_MODE=stock
```

Pass the exact UUID of an available, **initially Shutdown, explicitly owned synthetic simulator**. Never select by name, `booted`, or another project's device. The runner takes the shared real-user lock at `~/Library/Caches/ios-verification/<UDID>.lock`; a prebooted device or busy lock is a refusal, not permission to stop its owner.

Make prepares artifacts before boot, locks canonical DerivedData across the whole job, serially tests the selected UDID, finalizes its recorder and confirms Shutdown on success, failure, timeout and ordinary cancellation. Routine focused/smoke jobs share a 600-second whole-command budget: 420 seconds for build/setup/tests and 180 seconds reserved for cleanup. Qualification has a 2400-second budget. Overruns fail; cleanup is never killed to manufacture a fast result. Give the outer tool at least 900 seconds for routine work (3000 for qualification) so the owner's separately bounded cleanup can finish even on an overrun. Do not nest `make agent-verify` inside another lifecycle runner.

Coordinate heavy simulator jobs across projects before measuring. A different UDID or DerivedData lock does not isolate CPU, memory or automation services. Observe other jobs read-only; defer/report active competition rather than stopping it. Do not add parallel simulator workers or clean caches to chase a number.

Default: `simslim-default.json`, reviewed SimSlim **0.11.0**, qualified on iPhone 17 / iOS 27.0. It disables system search, Health/Home/Fitness, Mail/Calendar/Contacts, Family/Screen Time, News/Weather/Maps/Games and only PosterBoard from widgets. All Siri/Intelligence/speech, chronod, liveactivitiesd, account/keychain, media, web, photos, messaging, connectivity, diagnostics and assets remain enabled. Use **stock** for integrations affected by disabled services. This does not qualify actual model/audio/background execution.

Both modes require SimSlim: missing/unreviewed CLI, invalid profile or setup failure stops before tests, with no silent fallback. `--stock` restores and verifies every SimSlim-managed override, not arbitrary manual changes. Install only if missing: `brew install mobai-app/tap/simslim`; review any version other than 0.11.0 before mutation. Profiles persist through shutdown; normal cleanup never erases data or restores/reboots again.

Optional Make variables: `EVIDENCE` (fresh directory), `DERIVED_DATA` (default `.build/mural-lifecycle-derived-data`, shared lock rejects contention), `VERIFY_SUITE=smoke|qualification` (default smoke), `TESTS` (space-separated method names replacing the suite selection), `SIMSLIM_PROFILE` (explicit reviewed trial; conflicts with stock). Omit `TESTS` for the suite; explicitly empty, malformed or duplicate selections fail before building. Omitted/empty profile selects the default, **not** stock. Evidence defaults to `.build/verification/<unique-run>/`.

## Concise Xcode output and test results

`xcbeautify` is installed on PATH. Initialize one fresh evidence directory before build and test actions:

```sh
export EVIDENCE="$PWD/.build/verification/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE"
set -o pipefail
```

Make already applies this convention. For explicitly authorized physical commands, or simulator commands **inside the enclosing lifecycle only**, preserve raw logs while showing formatted output:

```sh
xcodebuild <existing arguments> 2>&1 | tee "$EVIDENCE/<action>.log" | xcbeautify --is-ci
```

For each `test` action, add a unique `-resultBundlePath "$EVIDENCE/<action>.xcresult"` and print the compact structured summary:

```sh
xcrun xcresulttool get test-results summary --path "$EVIDENCE/<action>.xcresult" --compact
```

Check the summary first. Inspect only failed-test details or attachments needed as evidence. Never print entire `.log` files or dump whole result bundles into agent context.

## Preconditions

- Apple Silicon macOS, Xcode 27, iOS 27.0 simulator runtime, Python 3, xcbeautify, ffmpeg/ffprobe and reviewed SimSlim 0.11.0. Other simulator runtimes are not app-qualified; persistent slimming refuses runtimes before iOS 18.5. Physical iOS 27.2 qualification is separate.
- Node.js 20 or newer for the pinned `.tools/serve-sim` package.
- A selected, explicit iPhone 17-family simulator UDID for each run.
- For physical checks: a paired, unlocked iPhone 17 with Developer Mode enabled, a trusted Mac, a valid signing team in `Config/Local.xcconfig`, and the user's authorization to install the current build.
- For live OpenAI checks: an API key entered only through Mural's Settings UI. A ChatGPT subscription is not an OpenAI API credential.

Check tools and devices:

```sh
xcodebuild -version
node --version
swift --version
xcrun simctl list devices available
```

Install the pinned simulator helper only if it is absent:

```sh
export SERVE_SIM="$PWD/.tools/serve-sim/node_modules/.bin/serve-sim"
if [ ! -x "$SERVE_SIM" ]; then npm ci --prefix .tools/serve-sim; fi
```

The helper is `serve-sim` version 0.1.46. It targets simulators only. It does not control a physical iPhone.

## Build and run supported simulator checks

```sh
: "${SIM_UDID:?Set an exact owned Shutdown simulator UUID}"
export APP_BUNDLE_ID=no.william.mural
export DERIVED_DATA="$PWD/.build/mural-lifecycle-derived-data"
export SIM_APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Mural.app"
make agent-verify SIM_UDID="$SIM_UDID"
```

Prefer the smallest sufficient **affected-feature selection** below; there is no mandatory smoke run before it. The default smoke fallback reuses three existing checks: onboarding/language selection, meaning toggle/New conversation/preview History, and Apple/Mural voice preference reselection and relaunch retention. Preview History is temporary, while preference retention is asserted across app launches. Neither is native model/audio proof.

`VERIFY_SUITE=qualification` retains all 13 previously qualified UI checks: onboarding/consent/missing-key guards; meaning/backend and unsupported combinations; synthetic setup cancel/drain/retry; both voice checks; theme navigation/local search; secure settings; ended transcript/New conversation/preview History; largest Dynamic Type; and a recorded Settings transition. Use it for profile/runtime or broad integration changes, not every edit. Relevant exhaustive setup and reboot-retention scenarios remain separate; see the feature map.

Every selection checks exact test counts, zero skipped tests and the selected device. `make-action.json` records exact coverage, `timings.json` records preparation/build/lifecycle/total elapsed time, and `cleanup.json` separates setup/command/cleanup durations and outcomes. Stage markers and XCTest output show progress; raw logs remain saved. Native XCTest allows 180 seconds per test, destination lookup is bounded at 30 seconds, and automatic retries/verbose sysdiagnose collection are not enabled. A failed invocation stops later stages; diagnose its first failure/stall instead of blindly rerunning or waiting for the qualification ceiling. The native per-test limit is not a custom whole-suite abort-on-first-assertion mechanism. No test-worker clones or serve-sim mirror are needed. See the [speedup plan](../../../docs/simulator-test-speedup-plan.md) for measured evidence and scope differences.

Measured on the qualified runtime with incremental builds: smoke **4m23s / 4m35s**, median **4m29s**, through confirmed Shutdown; the final focused recorded transition took **4m27s**. The test-action window dropped 75.8% versus the broader 13-check qualification because coverage was selected more narrowly, not because identical tests ran faster. See the linked plan for raw evidence, failed artifact-check attempts, source-decode correction and limitations.

For a focused change (replaces smoke, never appends it):

```sh
make agent-verify SIM_UDID="$SIM_UDID" \
  TESTS='testOnboardingChoosesLearningAndSubtitleLanguagesWithoutAnAccount'
```

For custom simulator work, compile first with `make build`, then enclose **all** install/launch/input/capture steps in one bounded script:

```sh
python3 scripts/verify_simulator.py --udid "$SIM_UDID" \
  --evidence "$PWD/.build/verification/custom-$(date +%Y%m%d-%H%M%S)-$$" \
  --timeout 300 --cleanup-script /absolute/path/to/owned-finalizer.sh \
  -- bash /absolute/path/to/interaction.sh
```

Inside that script, the runner supplies identical `SIM` and `SIM_UDID`, and `EVIDENCE`. Install `$SIM_APP` on that exact device, then use `simctl launch --terminate-running-process` with the desired preview arguments. Do not boot another simulator or return to chat with the device still running. Any direct Xcode test must use `-parallel-testing-enabled NO` and the exact ID, hold an exclusive DerivedData lock (or use its own isolated directory), and save a unique xcresult/compact summary.

Useful arguments: `--preview --preview-onboarding`, `--preview --preview-existing-user`, `--preview --ended-conversation`, or `--preview --screenshot=greeting|conversation|themes|words`. Preview records are temporary; selected preferences can still use UserDefaults. None of these proves native microphone/model execution or durable conversations.

## Animation and transient layout bugs

For shifting, snapping, flicker, menu dismissal, or transient clipping, follow [UI animation verification](features/ui-animation.md). Reproduce through the real UI, record comparable before/after interactions, and inspect frames around the transition. Settled screenshots and passing UI tests alone cannot prove the animation is fixed. The workflow includes bounded recording, cleanup, sibling-control checks, long labels, and accessibility checks. Report blocked recording explicitly.

## Serve-sim readiness and observation

Prefer native tests. Start a mirror only inside an owned runner session when live input/accessibility is needed. Never take over an existing mirror. The tested repeatable startup/finalizer examples are linked in the [rollout evidence log](../../../docs/simulator-verification-lifecycle-plan.md).

Within `interaction.sh`:

1. Save `"$SERVE_SIM" --list "$SIM" -q`; require `running: false` before starting.
2. Record ownership intent **before** `--detach`, so a partially failed startup is finalized. Start only that exact device, without `--theme` or other global-setting changes.
3. Save the resulting stream JSON, PID, command/start identity and URL. Derive `HELPER_URL` from `streamUrl`; require `/health`, `/foreground` (Mural) and fresh `/ax` before input. Bound each request with `curl --fail --max-time`.
4. Drive mapped feature actions with `tap`, `type` or `button`, always passing `--device "$SIM"`. Coordinates come from current accessibility bounds/frame, not guessed browser pixels. Re-read state after each meaningful action.
5. The runner's `--cleanup-script` must verify the saved mirror identity, call only `"$SERVE_SIM" --kill "$SIM"`, and require a stopped stream and no owned helper process. Run it even after command failure, timeout or cancellation. Never use an unscoped kill.

The main runner stops its command group before invoking the separately bounded finalizer. Detached helpers are **not** covered by process-group cleanup; explicitly own and finalize them. Restore any changed appearance/text size/accessibility setting before shutdown and fail cleanup if restoration cannot be confirmed. The existing recorder should remain in the owned command group and finalize gracefully before movie decode validation.

On Xcode 27, keyboard input may require a visible simulator and macOS Accessibility permission. Do not grant permission silently. If blocked, prefer native UI tests; an accepted input event is not proof of the visible outcome. Do not keep a mirror alive while reviewing saved artifacts.

## Seed, reset, and persistence

Prefer the app's existing preview arguments. They create temporary records and avoid personal data:

- `--preview --preview-onboarding` for new-user language, subtitle, and consent UI.
- `--preview --preview-existing-user` for an existing-user AI-consent decision.
- `--preview --ended-conversation` for Settings-only meaning subtitles, transcript, manual reset, and retained history.
- `--preview --screenshot=greeting|conversation|themes|words` for visual fixtures.

Do not use `xcrun simctl erase`, do not uninstall the app to force a state, and do not overwrite a simulator another session owns. For persistence changes, reuse the persistent project simulator with synthetic content and a normal non-preview launch; preserve unrelated retained data. Only a demonstrated fresh-install/migration or runtime/screen-size requirement justifies an additional device, with user approval and cleanup agreed before creation. Record that temporary UDID, export evidence outside it, shut it down and delete only that approved temporary device when finished. A failed test or retry is not a reason to create a device.

Restore settings through the UI after a check. Do not seed private conversations, keys, or learning exports by editing the container.

## Physical iPhone 17 and Device Hub

### Qualified opt-in native local workflow

See the [physical plan](../../../docs/physical-iphone-e2e-plan.md) for acceptance evidence and limitations, and [lessons and optimization backlog](../../../docs/physical-iphone-e2e-lessons.md) for failures, measured timings and qualified runtime optimizations. Qualified on the paired iPhone 17, iOS 27.2, with explicit Core AI Release and retained model/voice assets. This is separate from simulator verification and never a default dependency of `make build` or `make agent-verify`.

#### Select the affected behavior

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

Routine runtime is bounded (420-second test-command ceiling, 300-second XCTest allowance, separately bounded cleanup); preparation has a 900-second ceiling. The explicit Simplified candidate `resource` stage has a separately reviewed 1,020-second whole-runtime ceiling, 780-second test command and 720-second XCTest allowance, preserving six-minute loaded idle and native drain/+30-second observation. It requires a matching model-free `resource-check` and the [Simplified qualification plan](../../../docs/asr/chinese/simplified-talk-qualification-plan.md), not the Vietnamese ladder or blanket authorization. Managed in-app acquisition and its token-redirect recovery passed. The subsequent native run `20260928-125336-34898` hit an iOS memory warning during recording before decode; resource qualification is BLOCKED, not permission for another attempt. See the [memory research handoff](../../../docs/asr/chinese/firered-memory-research-handoff.md). See the plan for the explicit acquisition-only `provision` and recovery budgets, not the routine runtime allowance. These exceptions do not change routine budgets. Evidence includes automatic compact xcresult summaries even on failure, per-turn playback receipts, app-only logs, source/artifact identity, settings/cleanup and elapsed time. Failures do not become passes because cleanup succeeded. Review `cleanup.json`; settings-only recovery gets a separate run, preserving the original failure. SIGKILL/host-crash recovery is manual: inspect saved PID/PGID/command/start identities before stopping anything, then use exact device-scoped operations. No global kill, erase, uninstall, model/cache deletion or physical shutdown.

#### Efficient execution and diagnosis

1. Review saved reports and changed inputs first. Use `status` for current ownership/lock state and `agent-device-report` for saved evidence, not repeated ad hoc Python. Reporting successfully is not test acceptance.
2. Complete signing/build, fixture validation and applicable host-runner checks before asking the user to wait beside an unlocked phone. Preserve matching build receipts and warm assets. A discovery tunnel marked disconnected is not alone proof that wired control is unavailable; use bounded device status checks.
3. Consolidate the runtime readiness request: exclusive idle app, mirroring closed, cool/unlocked phone, agreed placement/output route/volume and listening availability. Carry approvals forward within that window; ask again only when readiness changed or a protected prompt requires action. Never change system Auto-Lock. The app's temporary preparation idle-timer hold does not remove unlock requirements.
4. Declare fixture and recognition equivalences before playback. Keep current-turn capture/UI gates, actual backend evidence and bounded state waits. Use the qualified completion acknowledgment, not fixture-duration sleeps; preserve its bounded wait and trailing margin. Requalify transport changes model-free first, then one actual acoustic turn before multi-turn/repeat and affected cancellation.
5. Diagnose the first failure from `failure.json`, compact xcresult when present, and scoped logs. A Make exit code alone is not the cause: distinguish a preflight ownership refusal, compilation failure, app fault and interrupted host. After a canceled tool call, do not launch again until saved cleanup or separate ownership-aware recovery plus fresh process checks establish that owned work stopped. For selector/cleanup bugs, reproduce and qualify the relevant model-free path before another expensive acoustic run. Scope queries to the active sheet/navigation container, use the actual accessibility element type, and scroll toward the target. Physical helpers now exit as soon as the target is hittable; preserve that behavior rather than repeating remote queries for the unused loop iterations.
6. Review automated outcome and cleanup separately, then request only needed human listening confirmation. Save unresolved gaps explicitly. No automatic retry after model/resource faults, and no reuse of old listening confirmation for new audio.

For a requested physical screenshot, use `xcrun devicectl device capture screenshot --device "$DEVICE_UDID" --destination "$EVIDENCE/screen.png" --timeout 15` only when the authorized app/surface is known to be foreground. Prefer an owned XCTest app screenshot when available. Do not use a default-display screenshot to discover whether a background Mural process is idle; it can capture unrelated personal content. This runtime's older `idevicescreenshot` path failed, so do not add DDI/signing/permission changes to rescue it. See the [session failure review](../../../docs/physical-iphone-e2e-lessons.md#september-28-session-review-preventable-command-and-integration-mistakes).

For preparation-checklist regressions, native runtime samples real checklist accessibility states until Record is ready and rejects completed steps reverting. The copied test plan retains XCTest screen recordings on success and failure, without opening a mirror or recording the room. Export only the needed test's attachments using `xcrun xcresulttool export attachments --path <run>/baseline.xcresult --output-path <run>/attachments` (save verbose export output locally). Follow the source-decode and transition-inspection rules in [UI animation verification](features/ui-animation.md). A passing sampled assertion alone does not prove every video frame.

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

Prepare a signed build from this checkout. Do not change the signing team or bundle identifier just for verification:

```sh
export DEVICE_DERIVED_DATA="$PWD/.build/verify-mural-device-derived-data"
mkdir -p "$DEVICE_DERIVED_DATA"

xcodebuild \
  -project Mural.xcodeproj \
  -scheme Mural \
  -destination "platform=iOS,id=$DEVICE_UDID" \
  -derivedDataPath "$DEVICE_DERIVED_DATA" \
  build 2>&1 | tee "$EVIDENCE/device-build.log" | xcbeautify --is-ci

export DEVICE_APP="$DEVICE_DERIVED_DATA/Build/Products/Debug-iphoneos/Mural.app"
test -d "$DEVICE_APP"
xcrun devicectl device install app --device "$DEVICE_UDID" "$DEVICE_APP"
xcrun devicectl device info apps --device "$DEVICE_UDID" --bundle-id "$APP_BUNDLE_ID"
xcrun devicectl device process launch --device "$DEVICE_UDID" --terminate-existing "$APP_BUNDLE_ID"
```

If signing, trust, Developer Mode, or device availability blocks the build or install, record that blocker. Do not edit signing configuration or remove the installed app. An installed app from an older revision is not evidence for the current checkout.

Device Hub is the input and display fallback for the physical phone. Open it with:

```sh
open /Applications/Xcode-beta.app/Contents/Applications/DeviceHub.app
```

Select the same phone, choose **View Screen**, and wait for a settled frame. For typed input, keep the selected device window visible and frontmost and enable **Capture Keyboard**. Turn it off again afterward. Device Hub paste can use the phone's clipboard instead of the Mac clipboard, so inspect the field before sending or leaving it. If the phone's own voice dictation inserts unrelated text, stop and resolve that competing input before continuing.

If Device Hub shows live frames but taps no longer alter the phone:

1. Quit Device Hub completely from its app menu. Closing only the device window is not enough and may recreate it.
2. Reopen `/Applications/Xcode-beta.app/Contents/Applications/DeviceHub.app`.
3. Select the same phone and choose **View Screen**.
4. Leave **Capture Keyboard** off unless typing is the next action.
5. Send one harmless navigation action and verify the resulting settled screenshot.
6. If it still has no visible effect, stop and report input as blocked instead of retrying indefinitely.

For microphone recording or live voice capture, fully quit Device Hub before testing. Use the explicitly authorized native local runner above, or operate the iPhone directly for manual checks. Device Hub can interfere with microphone capture even while a recording timer advances. Use Device Hub for typed input and visual control, not as proof of microphone behavior.

## Live AI checks

A valid OpenAI key is required for a completed provider response. Enter it only in **Settings > Advanced > Use your own API key** on the phone. Never read it from Keychain, pass it through `devicectl`, or include it in evidence.

With a key and an approved live run, verify on the physical iPhone:

1. Open a new conversation and review/accept AI consent.
2. Confirm microphone permission, the greeting, and a settled nonempty response.
3. Send a short typed reply when using Device Hub input; confirm the learner passage and provider response.
4. Toggle Meaning and confirm a translation while active and after ending.
5. Mute, end, and relaunch; confirm the visible state and audio release.
6. Exercise one network or provider failure and confirm the user-facing error.

The app includes explicit Debug helpers that write content-free reports using temporary learning data:

```sh
xcrun devicectl device process launch --device "$DEVICE_UDID" --terminate-existing "$APP_BUNDLE_ID" --verify-audio
xcrun devicectl device copy from \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$APP_BUNDLE_ID" \
  --source Documents/audio-verification.json \
  --destination "$EVIDENCE/audio-verification.json"

xcrun devicectl device process launch --device "$DEVICE_UDID" --terminate-existing "$APP_BUNDLE_ID" --verify-meaning --verify-language=es
xcrun devicectl device copy from \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$APP_BUNDLE_ID" \
  --source Documents/meaning-verification.json \
  --destination "$EVIDENCE/meaning-verification.json"
```

These helpers incur API usage and are not substitutes for listening or checking the settled phone UI. With no API key, do not claim them as passed. The current valid result is a blocked live-provider check plus any proven missing-key, consent, or failure UI.

## Evidence

Keep fresh, local, uncommitted evidence under `.build/verification/`. Make creates a unique directory, or accepts a fresh `EVIDENCE`. The observation commands below belong **inside the bounded interaction script**, never after its runner has returned:

```sh
xcodebuild -version > "$EVIDENCE/toolchain.txt"
git status --short --branch > "$EVIDENCE/git-status.txt"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl --fail --max-time 15 "$HELPER_URL/ax" > "$EVIDENCE/before-ax.json" && grep -q 'onboarding-language-title' "$EVIDENCE/before-ax.json" && break
  sleep 1
done
test -s "$EVIDENCE/before-ax.json"
xcrun simctl io "$SIM" screenshot "$EVIDENCE/before.png"
# Drive one mapped feature, then capture the changed state after it settles.
xcrun simctl io "$SIM" screenshot "$EVIDENCE/after.png"
curl --fail --max-time 15 "$HELPER_URL/ax" > "$EVIDENCE/after-ax.json"
"$SERVE_SIM" event-log --device "$SIM" > "$EVIDENCE/events.txt"
```

For each run, write `$EVIDENCE/result.md` with:

- build and test commands plus exit status;
- app revision and dirty state;
- simulator or physical-device model, runtime, and identifier;
- starting state and exact user actions;
- expected versus observed outcome;
- screenshot, accessibility, event, test-result, or report paths;
- passed, failed, inconclusive, and blocked checks;
- cleanup performed.

Screenshots and accessibility output can contain personal content. Keep them local and review them before sharing. Do not commit evidence. The existing `.build/` ignore rule keeps this directory out of Git.

## Simulator cleanup and forced-kill recovery

This section applies only to simulators. Physical runs use the owned-process/settings cleanup described above; never shut down the physical phone.

Cleanup is an acceptance gate, not an optional final instruction. Require `cleanup.json` with `cleanup: PASS` and `final_state: Shutdown`; also inspect the separate command status. Preserve all evidence/app data. A finalizer failure makes the run fail even if tests passed. An ordinary signal cannot interrupt the final cleanup a second time.

SIGKILL or host failure can bypass cleanup. Inspect `session.json`, `command-process.json`, helper ownership records and the exact UDID's lock metadata. Compare PID/PGID, start time and command to current `ps` output before signaling anything. Never automatically reclaim a stale-looking owner or shut down a borrowed booted device. Once ownership is established and surviving owned work is stopped, gracefully finalize recorded captures/helpers, run `xcrun simctl shutdown <that-owned-UDID>` and confirm its state via `simctl list devices -j`. Save the recovery result. Do not erase, delete, uninstall, clear caches/models, shut down all devices, or globally quit Simulator as recovery. The only test-cleanup deletion exception is an explicitly approved temporary device under the lifecycle policy above; never delete the retained primary.

Required closeout: supported checks PASS/FAIL/BLOCKED; profile/runtime/CLI; evidence paths; owned helper/recorder stops; every owned simulator Shutdown; cleanup PASS/FAIL; other projects not targeted; physical microphone/model/native-background checks not run unless separately authorized and actually executed.

## Feature map

Read `features/README.md`, then the relevant feature file before choosing a check:

- `features/onboarding-consent.md`
- `features/themes-words-settings.md`
- `features/ui-animation.md`
- `features/conversation-lifecycle.md`
- `features/live-ai-device.md`

Match the check to the changed behavior. Prefer one sufficient real-path UI journey with outcome assertions; do not automatically run overlapping suites. Layout changes require relevant transition/large-text checks, search semantics require filtering/recovery cases, and persistence changes require the appropriate relaunch/reboot path. Repeated gestures can prove distinct behaviors: changing versus reselecting, retaining across relaunch, or the same query under a different filter. Do not delete them merely because the interaction repeats.

For changed data semantics, use assertions against production code for exhaustive matrices plus representative real UI integration; enumerate failures and write any necessary isolated checks before implementation. Do not reproduce the algorithm in the test or migrate unrelated coverage for this tooling rollout. Retain meaningful UI-state waits and target-driven scrolling.

Reuse saved evidence only after checking relevant production/test/fixture code, build configuration, runtime/Xcode, profile/CLI and exercised state. Record current input hashes and revision/dirty state beside measurements. An old app pass does not qualify new harness behavior or changed inputs; rerun affected checks, not automatically every overlapping suite.

## Failure behavior

- A build failure is a build failure, not a UI result.
- A live frame, process existence, or accepted input event is not readiness or success. Confirm the foreground bundle and changed visible state.
- A missing API key, unavailable phone, signing failure, microphone permission denial, or broken Device Hub input is a named blocker. Do not turn it into a pass by skipping the check.
- If Mural exits, inspect `~/Library/Logs/DiagnosticReports/Mural-*.ips` and the relevant test or simulator logs before retrying.
- Stop repeated retries when the settled UI does not change. Preserve the failure evidence.

## Quick run

```sh
cd "$(git rev-parse --show-toplevel)"
: "${SIM_UDID:?Choose an explicitly owned Shutdown iPhone 17 simulator}"
make agent-verify SIM_UDID="$SIM_UDID" \
  TESTS='testOnboardingChoosesLearningAndSubtitleLanguagesWithoutAnAccount'
```

This is a focused synthetic UI check, not the complete smoke selection or a microphone/model test. Inspect the xcresult screenshots and compact summary **after confirmed shutdown**. For broader qualification and the finalized Settings movie, omit `TESTS` and set `VERIFY_SUITE=qualification`. For an animation-only change, select `testSettingsDropdownTransitions` directly. Use `SIMULATOR_MODE=stock` to deliberately restore managed services, not to bypass ownership/cleanup.

Invoke this skill with `/skill:verify-mural` from Pi.
