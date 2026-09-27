---
name: verify-mural
description: Verify Mural by building and launching its iOS app, using serve-sim for simulator UI and Device Hub for iPhone 17 AI and audio flows. Use after changes affecting onboarding, conversation, themes, words, settings, persistence, audio, or OpenAI integration, when reproducing bugs including animation, shifting, flicker, or transient clipping, and before claiming work complete.
---

# Verify Mural

## Local MVP workflow override

For local MVP work, follow `mvp_plan.md`'s current paired-verification workflow: the implementation agent builds/installs/launches directly and the user performs phone speech/listening checks. Do not spawn tester subagents. Read `features/local-conversation.md`. Local probes need no OpenAI key; the key requirement and `--verify-audio`/`--verify-meaning` helpers below are premium-only. Preserve the confirmed existing phone bundle `com.kevintruong.mural.dev` using a build override, rather than installing the public default alongside it. Discover devices; use iOS 27 and Release for local timing.

**Preserve the local ASR backend when rebuilding.** The current paired iPhone 17 workflow uses the explicit staged Core AI opt-in, not ordinary Release. Before a phone build, read the current build recipe at the top of `features/local-conversation.md` and `docs/coreai/gpu-talk-checkpoint.md` in the repository. Pass `OTHER_SWIFT_FLAGS='$(inherited) -D MURAL_COREAI_TALK'` for that local Release, including builds from detached worktrees. Confirm the actual app compiler command and the `local_talk_asr_backend` launch event; a correct commit and a successful Release build alone do not identify the backend. Public/default Release remains unchanged. Do not enable the opt-in for unrelated devices, simulator checks, or an explicitly requested baseline comparison.

**Collect evidence before asking the user to reproduce.** Read existing `.build/verification/` reports, saved Mural logs, and the installing session when supplied. For a new paired check, start or reuse a scoped Mural-only device capture before the user acts, record its ownership and starting offset, and ask for one short batch plus “done” or an approximate failure time. Do not require screenshots of timings already in logs. Follow the logging procedure in `features/local-conversation.md`; never silently collect a device-wide archive or claim a missing/redacted event proves success.

## Purpose

Prove Mural through the closest practical user path. A successful build or an acknowledged tap is supporting evidence, not proof that the app works.

Mural has two useful verification surfaces:

| Surface | Use it for | API key needed |
|---|---|---:|
| iOS Simulator plus `serve-sim` | Onboarding, consent, navigation, themes, words, settings layout, preview data, reset, history, screenshots, and native UI tests | No |
| Physical iPhone 17 through Device Hub | Live OpenAI conversation, microphone, WebRTC audio routing, typed replies, meaning requests, network behavior, and device-only behavior | Yes for provider responses |

The current environment does not have an OpenAI API key. Prove the missing-key and consent guards, but report live provider response checks as blocked. Never add a key to a command, source file, screenshot, or evidence artifact.

Run commands from the repository root. The app bundle identifier is `no.william.mural`. Simulator verification must use the checked-in lifecycle below; physical recipes remain separate and opt-in.

## Mandatory simulator lifecycle

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

- Apple Silicon macOS, Xcode 27, iOS 27.0 simulator runtime, Python 3, xcbeautify, ffmpeg/ffprobe and reviewed SimSlim 0.11.0. Other runtimes are not app-qualified; persistent slimming refuses runtimes before iOS 18.5.
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

Do not use `xcrun simctl erase`, do not uninstall the app to force a state, and do not overwrite a simulator another session owns. For persistence changes, create a disposable iPhone 17 simulator from an installed device type and runtime listed by `xcrun simctl list devicetypes` and `xcrun simctl list runtimes`; record its returned UDID, use the normal non-preview launch, and shut down only that simulator when finished. Keep its evidence.

Restore settings through the UI after a check. Do not seed private conversations, keys, or learning exports by editing the container.

## Physical iPhone 17 and Device Hub

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

For microphone recording or live voice capture, fully quit Device Hub before testing and operate the iPhone directly. Device Hub can interfere with microphone capture even while a recording timer advances. Use Device Hub for typed input and visual control, not as proof of microphone behavior.

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

## Cleanup and forced-kill recovery

Cleanup is an acceptance gate, not an optional final instruction. Require `cleanup.json` with `cleanup: PASS` and `final_state: Shutdown`; also inspect the separate command status. Preserve all evidence/app data. A finalizer failure makes the run fail even if tests passed. An ordinary signal cannot interrupt the final cleanup a second time.

SIGKILL or host failure can bypass cleanup. Inspect `session.json`, `command-process.json`, helper ownership records and the exact UDID's lock metadata. Compare PID/PGID, start time and command to current `ps` output before signaling anything. Never automatically reclaim a stale-looking owner or shut down a borrowed booted device. Once ownership is established and surviving owned work is stopped, gracefully finalize recorded captures/helpers, run `xcrun simctl shutdown <that-owned-UDID>` and confirm its state via `simctl list devices -j`. Save the recovery result. Do not erase, delete, uninstall, clear caches/models, shut down all devices, or globally quit Simulator.

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
