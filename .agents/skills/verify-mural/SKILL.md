---
name: verify-mural
description: Verify Mural by building and launching its iOS app, using serve-sim for simulator UI and Device Hub for iPhone 17 AI and audio flows. Use after changes affecting onboarding, conversation, themes, words, settings, persistence, audio, or OpenAI integration, when reproducing bugs, and before claiming work complete.
---

# Verify Mural

## Local MVP workflow override

For local MVP work, follow `mvp_plan.md`'s current paired-verification workflow: the implementation agent builds/installs/launches directly and the user performs phone speech/listening checks. Do not spawn tester subagents. Read `features/local-conversation.md`. Local probes need no OpenAI key; the key requirement and `--verify-audio`/`--verify-meaning` helpers below are premium-only. Preserve the confirmed existing phone bundle `com.kevintruong.mural.dev` using a build override, rather than installing the public default alongside it. Discover devices; use iOS 27 and Release for local timing.

## Purpose

Prove Mural through the closest practical user path. A successful build or an acknowledged tap is supporting evidence, not proof that the app works.

Mural has two useful verification surfaces:

| Surface | Use it for | API key needed |
|---|---|---:|
| iOS Simulator plus `serve-sim` | Onboarding, consent, navigation, themes, words, settings layout, preview data, reset, history, screenshots, and native UI tests | No |
| Physical iPhone 17 through Device Hub | Live OpenAI conversation, microphone, WebRTC audio routing, typed replies, meaning requests, network behavior, and device-only behavior | Yes for provider responses |

The current environment does not have an OpenAI API key. Prove the missing-key and consent guards, but report live provider response checks as blocked. Never add a key to a command, source file, screenshot, or evidence artifact.

Run commands from the repository root. The app bundle identifier is `no.william.mural`. The project has no checked-in simulator launcher; use the commands below.

## Preconditions

- Apple Silicon macOS with Xcode 26 or newer, an installed iOS 26.1 or newer simulator runtime, and Swift 6 tooling.
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
xcrun devicectl list devices
```

Install the pinned simulator helper only if it is absent:

```sh
export SERVE_SIM="$PWD/.tools/serve-sim/node_modules/.bin/serve-sim"
if [ ! -x "$SERVE_SIM" ]; then npm ci --prefix .tools/serve-sim; fi
```

The helper is `serve-sim` version 0.1.46. It targets simulators only. It does not control a physical iPhone.

## Build and prepare the simulator

Choose an available iPhone 17 or iPhone 17 Pro simulator from `xcrun simctl list devices available`, then set `SIM` to its UDID. Use that same value for building, launching, input, screenshots, and cleanup.

```sh
export APP_BUNDLE_ID=no.william.mural
export SERVE_SIM="$PWD/.tools/serve-sim/node_modules/.bin/serve-sim"
: "${SIM:?Set SIM to an available iPhone 17-family simulator UDID}"
export DERIVED_DATA="$PWD/.build/verify-mural-derived-data"
mkdir -p "$DERIVED_DATA"

xcodebuild \
  -project Mural.xcodeproj \
  -scheme Mural \
  -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  build

export SIM_APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Mural.app"
test -d "$SIM_APP"
```

Run supporting checks when the change warrants them:

```sh
swift test

xcodebuild \
  -project Mural.xcodeproj \
  -scheme Mural \
  -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  -parallel-testing-enabled NO \
  test
```

For a focused native UI check, append one of the test names in the feature map:

```sh
xcodebuild \
  -project Mural.xcodeproj \
  -scheme Mural \
  -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  -parallel-testing-enabled NO \
  -only-testing:MuralUITests/MuralUITests/testOnboardingChoosesLearningAndSubtitleLanguagesWithoutAnAccount \
  test
```

## Launch the simulator app

Boot the selected simulator without erasing it, install the app built above, and launch it with a deterministic Debug preview argument:

```sh
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b
xcrun simctl install "$SIM" "$SIM_APP"
xcrun simctl terminate "$SIM" "$APP_BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch --terminate-running-process "$SIM" "$APP_BUNDLE_ID" --preview --screenshot=greeting
```

Useful simulator-only launch states are:

```sh
xcrun simctl launch --terminate-running-process "$SIM" "$APP_BUNDLE_ID" --preview --preview-onboarding
xcrun simctl launch --terminate-running-process "$SIM" "$APP_BUNDLE_ID" --preview --preview-existing-user
xcrun simctl launch --terminate-running-process "$SIM" "$APP_BUNDLE_ID" --preview --ended-conversation
xcrun simctl launch --terminate-running-process "$SIM" "$APP_BUNDLE_ID" --preview --screenshot=conversation
xcrun simctl launch --terminate-running-process "$SIM" "$APP_BUNDLE_ID" --preview --screenshot=themes
xcrun simctl launch --terminate-running-process "$SIM" "$APP_BUNDLE_ID" --preview --screenshot=words
```

`--preview` uses temporary SwiftData and skips normal onboarding. `--preview-onboarding` reopens the two-screen onboarding fixture. `--preview-existing-user` starts with an onboarded user. `--ended-conversation` seeds a finished coffee conversation. `--screenshot` seeds synthetic simulator-only content and never calls OpenAI.

## Serve-sim readiness and observation

Start one mirror for the selected simulator. Do not start a second mirror for the same device.

```sh
"$SERVE_SIM" --detach --panes devices,tools --fit "$SIM"
SERVE_INFO=$("$SERVE_SIM" --list "$SIM" -q)
printf '%s\n' "$SERVE_INFO"
export PREVIEW_URL=$(printf '%s' "$SERVE_INFO" | python3 -c 'import json,sys; print(json.load(sys.stdin)["url"])')
export HELPER_URL=$(printf '%s' "$SERVE_INFO" | python3 -c 'import json,sys; print(json.load(sys.stdin)["streamUrl"].rsplit("/stream.mjpeg", 1)[0])')

curl --fail --max-time 10 "$HELPER_URL/health"
curl --fail --max-time 10 "$HELPER_URL/foreground"
curl --fail --max-time 15 "$HELPER_URL/ax"
```

Open `PREVIEW_URL` in the host browser when visual interaction or a browser screenshot is useful. The displayed frame must show Mural, not the Home Screen or a stale frame. Use the accessibility response and a fresh frame to choose targets.

`serve-sim` commands use normalized coordinates inside the simulator display, not browser pixels:

```sh
"$SERVE_SIM" tap 0.50 0.50 --device "$SIM"
"$SERVE_SIM" type "Mural verification text" --device "$SIM"
"$SERVE_SIM" button home --device "$SIM"
"$SERVE_SIM" event-log --device "$SIM"
```

The tap above is syntax only. Derive the actual coordinate from the current screenshot or accessibility bounds before sending it. After every meaningful action, fetch `/ax` or a screenshot again. An event-log entry saying that a tap was accepted does not prove that a native control changed state.

On Xcode 27, keyboard input is bridged through Device Hub. The selected simulator window must be visible and frontmost, and the app that launched `serve-sim` may need macOS Accessibility permission. Do not silently grant that permission. If keyboard input is not important, use the native UI tests instead.

## Seed, reset, and persistence

Prefer the app's existing preview arguments. They create temporary records and avoid personal data:

- `--preview --preview-onboarding` for new-user language, subtitle, and consent UI.
- `--preview --preview-existing-user` for an existing-user AI-consent decision.
- `--preview --ended-conversation` for meaning, transcript, manual reset, automatic reset, and retained history.
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
  build

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

Keep fresh, local, uncommitted evidence under `.build/verification/`:

```sh
export EVIDENCE="$PWD/.build/verification/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE"

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

## Cleanup

Stop only resources owned by this verification run:

```sh
"$SERVE_SIM" --kill "$SIM"
xcrun simctl terminate "$SIM" "$APP_BUNDLE_ID" 2>/dev/null || true
```

If a foreground `serve-sim` process was used, stop it with Ctrl-C and wait for it to exit. Shut down a simulator only if this run booted it and no one else is using it. Never use an unscoped `serve-sim --kill`, never erase a simulator, and never uninstall Mural just to clean up. Leave evidence in place and confirm the named files still exist after cleanup.

## Feature map

Read `features/README.md`, then the relevant feature file before choosing a check:

- `features/onboarding-consent.md`
- `features/themes-words-settings.md`
- `features/conversation-lifecycle.md`
- `features/live-ai-device.md`

Match the check to the changed behavior. Prefer one real-path UI check plus the normal core/native test that covers the same behavior.

## Failure behavior

- A build failure is a build failure, not a UI result.
- A live frame, process existence, or accepted input event is not readiness or success. Confirm the foreground bundle and changed visible state.
- A missing API key, unavailable phone, signing failure, microphone permission denial, or broken Device Hub input is a named blocker. Do not turn it into a pass by skipping the check.
- If Mural exits, inspect `~/Library/Logs/DiagnosticReports/Mural-*.ips` and the relevant test or simulator logs before retrying.
- Stop repeated retries when the settled UI does not change. Preserve the failure evidence.

## Quick run

This is the minimal harness smoke check for a cold agent. It proves a real simulator UI feature without an API key:

```sh
cd "$(git rev-parse --show-toplevel)"
set -euo pipefail
export APP_BUNDLE_ID=no.william.mural
export SERVE_SIM="$PWD/.tools/serve-sim/node_modules/.bin/serve-sim"
: "${SIM:?Set SIM to an available iPhone 17-family simulator UDID}"
export DERIVED_DATA="$PWD/.build/verify-mural-derived-data"
export SIM_APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Mural.app"
export EVIDENCE="$PWD/.build/verification/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE"
cleanup() {
  "$SERVE_SIM" --kill "$SIM" > "$EVIDENCE/serve-stop.txt" 2>&1 || true
  xcrun simctl terminate "$SIM" "$APP_BUNDLE_ID" > /dev/null 2>&1 || true
}
trap cleanup EXIT

test -d "$SIM_APP"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b
xcrun simctl install "$SIM" "$SIM_APP"
xcrun simctl launch --terminate-running-process "$SIM" "$APP_BUNDLE_ID" --preview --preview-onboarding
"$SERVE_SIM" --detach --panes devices,tools --fit "$SIM"
SERVE_INFO=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  SERVE_INFO=$("$SERVE_SIM" --list "$SIM" -q 2>/dev/null || true)
  if printf '%s' "$SERVE_INFO" | grep -q '"running":true'; then break; fi
  sleep 1
done
export HELPER_URL=$(printf '%s' "$SERVE_INFO" | python3 -c 'import json,sys; print(json.load(sys.stdin)["streamUrl"].rsplit("/stream.mjpeg", 1)[0])')
curl --fail --max-time 10 "$HELPER_URL/health"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl --fail --max-time 15 "$HELPER_URL/ax" > "$EVIDENCE/onboarding-ax.json" && grep -q 'onboarding-language-title' "$EVIDENCE/onboarding-ax.json" && break
  sleep 1
done
test -s "$EVIDENCE/onboarding-ax.json"
xcrun simctl io "$SIM" screenshot "$EVIDENCE/onboarding.png"

TEST_STATUS=0
xcodebuild \
  -project Mural.xcodeproj \
  -scheme Mural \
  -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  -parallel-testing-enabled NO \
  -only-testing:MuralUITests/MuralUITests/testOnboardingChoosesLearningAndSubtitleLanguagesWithoutAnAccount \
  test > "$EVIDENCE/onboarding-test.log" 2>&1 || TEST_STATUS=$?
printf 'test status: %s\\n' "$TEST_STATUS" > "$EVIDENCE/onboarding-test-status.txt"
if [ "$TEST_STATUS" -ne 0 ]; then exit "$TEST_STATUS"; fi

xcrun simctl launch --terminate-running-process "$SIM" "$APP_BUNDLE_ID" --preview --screenshot=greeting
AFTER_AX_AVAILABLE=no
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl --fail --max-time 15 "$HELPER_URL/ax" > "$EVIDENCE/after-ax.json" && grep -q 'target-caption' "$EVIDENCE/after-ax.json"; then
    AFTER_AX_AVAILABLE=yes
    break
  fi
  sleep 1
done
xcrun simctl io "$SIM" screenshot "$EVIDENCE/greeting-after-test.png"
"$SERVE_SIM" event-log --device "$SIM" > "$EVIDENCE/events.txt"
cat > "$EVIDENCE/result.md" <<EOF
# Mural verification harness self-check

- Surface: iOS Simulator with serve-sim 0.1.46
- Simulator: iPhone 17, UDID $SIM
- Starting state: --preview --preview-onboarding
- Driven feature: onboarding language, subtitle, consent, and Talk transition
- UI test status: passed
- API key: not used; this flow makes no provider calls
- Post-test accessibility availability: $AFTER_AX_AVAILABLE; the screenshot remains the visual proof if the bridge is unavailable
- Evidence: onboarding.png, onboarding-ax.json, greeting-after-test.png, after-ax.json, events.txt, onboarding-test.log
- Cleanup: serve-sim stopped and app terminated by the exit trap
EOF

test -s "$EVIDENCE/greeting-after-test.png"
test -s "$EVIDENCE/after-ax.json"
```

The targeted test must pass, `onboarding.png` must show Mural's onboarding screen, and `greeting-after-test.png` must show Mural's Talk screen. If any step is unavailable, label the run partial or blocked and preserve the exact output.

Invoke this skill with `/skill:verify-mural` from Pi.
