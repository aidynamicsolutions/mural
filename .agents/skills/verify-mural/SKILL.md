---
name: verify-mural
description: Verify Mural through bounded simulator checks or explicitly authorized native XCUITest on iPhone 17 for real local microphone, models, speech and persistence. Use serve-sim for simulator UI and Device Hub only for physical typed/visual fallback, never microphone acceptance. Use after user-visible or audio/model changes, when reproducing UI bugs, and before claiming work complete.
---

# Verify Mural

## Purpose

Prove Mural through the closest practical user path. A successful build or an acknowledged tap is supporting evidence, not proof that the app works.

Mural has two useful verification surfaces:

| Surface | Use it for | API key needed |
|---|---|---:|
| iOS Simulator plus `serve-sim` | Onboarding, consent, navigation, themes, words, settings layout, preview data, reset, history, screenshots, and native UI tests | No |
| Physical iPhone 17 | Opt-in native XCUITest for real local microphone/model/speech/persistence; Device Hub for premium typed/visual checks only | No for local; yes for live provider responses |

The physical iPhone is the primary acceptance surface for real microphone, ASR/tutor/TTS, audible output and native lifecycle behavior. Simulator checks remain the faster supporting surface for UI and synthetic guards. Select by the changed behavior; do not require both surfaces or the full physical qualification ladder for every change. A passing recording-cancellation test does not qualify background execution or inference cancellation.

Local verification needs no OpenAI key. If live-provider behavior is affected and no user-provided key/authorization is available, report those checks as blocked; missing-key and consent guards can still be checked. Never add a key to a command, source file, screenshot, or evidence artifact.

Run commands from the repository root. The public/simulator bundle is `no.william.mural`; the paired phone uses the separate recipe below. Simulator verification must use the checked-in lifecycle. Documentation/tooling-only changes need their relevant checks, not an app journey unless app behavior is affected.

## Evidence selection

- Identify the requested outcome, affected contracts and material failure cases, then choose checks capable of detecting an incorrect result. Prefer representative, challenging inputs over artificially long journeys. Broaden for shared behavior or unresolved risks, not because another suite exists. These evidence types are alternatives or complements, not mandatory stages:
  - Static appearance: inspect current screenshots and applicable display variants. Accessibility frames may include interaction/row padding, and combined labels may insert punctuation; they are not literal painted geometry or text.
  - Accessibility: inspect names, roles, values, states and actions. Screenshots and AX dumps do not establish actual VoiceOver speech/focus.
  - Interaction: assert the acknowledged result through the affected path, not a successful tap command. Use focused production-logic checks for distinct transitions, errors or cancellation risks.
  - Persistence: assert exact content/state after acknowledged save and normal reopen. Preview records are not durable-data proof; add storage/migration checks for affected integrity and failure cases.
  - Motion: use a bounded recording and inspect the affected interval via [UI animation verification](features/ui-animation.md), not only settled screenshots.
  - Microphone/model/audible output: use explicitly authorized physical acceptance, with actual backend evidence and separate listening confirmation where required.
- Before a run, inspect the selected test, fixture and target membership. Regenerate the project through `scripts/generate_project.py` when Xcode configuration or non-synchronized source membership changes, preserving the intended backend/signing recipe; do not hand-edit generated files or regenerate every build. Confirm new tests are included, including explicitly listed UI test sources.
- Classify failures as app defects, incorrect expectations/measurements, unsuitable fixtures or infrastructure problems before retrying. Start with the assertion, actual result and relevant code, then inspect artifacts that distinguish remaining explanations. Specialized model/resource stop rules remain stricter.
- Replace invalid checks without dropping the original requirement: supply a valid assertion or appropriate visual/behavioral evidence, otherwise mark the requirement unverified. Do not weaken valid assertions or switch to easier fixtures that hide the failure.
- Reuse guidance still available and applicable in context and evidence whose relevant inputs remain valid. Reading every linked reference or rerunning unchanged checks is not proof. Stop when requested outcomes have sufficient current evidence; report remaining gaps explicitly.

## Mandatory simulator lifecycle

Enter complete heavy commands through `active-ios-simulator-limit run -- <command>` before prebuild or boot. Two permits are shared with other projects and retained through cleanup. The host limiter is not another simulator lifecycle runner; all device/build locks and budgets below remain required.

Reuse `Mural Lifecycle Verification`, UDID `C094F154-7674-4A17-9F6B-319959B1F49A` (iPhone 17 / iOS 27.0), as the single persistent project device across tasks, retries and worktrees. Confirm availability and Shutdown before use. If busy, wait rather than create a substitute. Never create per-test devices or parallel test-worker clones. If missing, inspect the inventory before deliberately replacing it. Additional migration/runtime/screen-size devices require a concrete coverage gap, user approval and an agreed deletion plan before creation; export evidence and delete only those approved temporary devices afterward. Retain the primary device's app/model data.

Choose the relevant command below; these are alternatives, not a sequence to run in full:

```sh
active-ios-simulator-limit run -- make build  # Generic arm64 simulator compilation only; never boots a device.
active-ios-simulator-limit run -- make agent-verify SIM_UDID="$SIM_UDID"  # Three-check smoke fallback.
active-ios-simulator-limit run -- make agent-verify SIM_UDID="$SIM_UDID" TESTS='testThemeSearchFiltersLocally'
active-ios-simulator-limit run -- make agent-verify SIM_UDID="$SIM_UDID" VERIFY_SUITE=qualification
active-ios-simulator-limit run -- make agent-verify SIM_UDID="$SIM_UDID" SIMULATOR_MODE=stock
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

Check the summary first, including intended test identities, exact selected counts and non-skipped execution. Exit 0, zero tests, required skips or successful cleanup alone are not acceptance. Inspect only failed-test details or attachments needed as evidence. Never print entire `.log` files or dump whole result bundles into agent context.

## Preconditions

- Apple Silicon macOS, Xcode 27, iOS 27.0 simulator runtime, Python 3, xcbeautify, ffmpeg/ffprobe and reviewed SimSlim 0.11.0. Other simulator runtimes are not app-qualified; persistent slimming refuses runtimes before iOS 18.5. Physical iOS 27.2 qualification is separate.
- Node.js 20 or newer for the pinned `.tools/serve-sim` package.
- A selected, explicit iPhone 17-family simulator UDID for each run.
- For physical runtime checks: a paired, unlocked iPhone 17 with Developer Mode enabled, a trusted Mac, a valid signing team in `Config/Local.xcconfig`, and the user's authorization to install/run the current build. Safe preparation does not require an unlocked phone or an audible window.
- For live OpenAI checks: an API key entered only through Mural's Settings UI. A ChatGPT subscription is not an OpenAI API credential.

Inspect toolchain configuration when establishing or changing the build path; reuse that inspection while inputs remain unchanged. Device availability/ownership must be fresh for each run. Relevant inspection commands:

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
active-ios-simulator-limit run -- make agent-verify SIM_UDID="$SIM_UDID"
```

Prefer the smallest sufficient **affected-feature selection** below; there is no mandatory smoke run before it. The default smoke fallback reuses three existing checks: onboarding/language selection, meaning toggle/New conversation/preview History, and Apple/Mural voice preference reselection and relaunch retention. Preview History is temporary, while preference retention is asserted across app launches. Neither is native model/audio proof.

`VERIFY_SUITE=qualification` retains all 13 previously qualified UI checks: onboarding/consent/missing-key guards; meaning/backend and unsupported combinations; synthetic setup cancel/drain/retry; both voice checks; theme navigation/local search; secure settings; ended transcript/New conversation/preview History; largest Dynamic Type; and a recorded Settings transition. Use it for profile/runtime or broad integration changes, not every edit. Relevant exhaustive setup and reboot-retention scenarios remain separate; see the feature map.

Every selection checks exact test counts, zero skipped tests and the selected device. `make-action.json` records exact coverage, `timings.json` records preparation/build/lifecycle/total elapsed time, and `cleanup.json` separates setup/command/cleanup durations and outcomes. Stage markers and XCTest output show progress; raw logs remain saved. Native XCTest allows 180 seconds per test, destination lookup is bounded at 30 seconds, and automatic retries/verbose sysdiagnose collection are not enabled. A failed invocation stops later stages; diagnose its first failure/stall instead of blindly rerunning or waiting for the qualification ceiling. The native per-test limit is not a custom whole-suite abort-on-first-assertion mechanism. No test-worker clones or serve-sim mirror are needed. See the [speedup plan](../../../docs/simulator-test-speedup-plan.md) for measured evidence and scope differences.

Measured on the qualified runtime with incremental builds: smoke **4m23s / 4m35s**, median **4m29s**, through confirmed Shutdown; the final focused recorded transition took **4m27s**. The test-action window dropped 75.8% versus the broader 13-check qualification because coverage was selected more narrowly, not because identical tests ran faster. See the linked plan for raw evidence, failed artifact-check attempts, source-decode correction and limitations.

For a focused change (replaces smoke, never appends it):

```sh
active-ios-simulator-limit run -- make agent-verify SIM_UDID="$SIM_UDID" \
  TESTS='testOnboardingChoosesLearningAndSubtitleLanguagesWithoutAnAccount'
```

For custom simulator work, compile first with `make build`, then enclose **all** install/launch/input/capture steps in one bounded script:

```sh
active-ios-simulator-limit run -- python3 scripts/verify_simulator.py --udid "$SIM_UDID" \
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

Preflight the chosen fixture against the selected test. Use known synthetic content, not an arbitrary first match. A missing or incompatible fixture is a blocker or reason to choose another suitable check, not permission to reset retained data or skip a required case. Restore settings through the UI after a check. Do not seed private conversations, keys, or learning exports by editing the container.

## Physical iPhone 17 and Device Hub

Physical testing is explicitly opt-in, never an automatic follow-up to simulator checks. Before any phone build, install, launch or capture, read the applicable procedures in [physical-device verification](references/physical-device.md), including the local MVP/backend override. Preserve the installed `com.kevintruong.mural.dev` bundle, intended signed build/backend, model/voice assets, caches, preferences and personal history. The public simulator build is not the paired phone recipe.

Native tests still require the user's authorized idle/audible window and applicable trust, unlock, microphone-permission and listening gates. Complete safe preparation first, then refresh current process/lock state immediately before runtime. Keep mirroring closed for microphone checks; room-audio capture needs separate permission. Stop on model/resource faults or unsafe thermal conditions, with no automatic retry or backend switch. Cleanup restores settings and stops only owned processes, never shuts down the phone.

### Qualified opt-in native local workflow

Use the [qualified native workflow](references/physical-device.md#qualified-opt-in-native-local-workflow). Initial or affected-contract requalification retains the ordered readiness/acoustic/persistence gates; routine checks select the affected behavior on unchanged qualified contracts. Saved preparation/evidence requires matching identities and does not bypass native model loading or validation.

#### Select the affected behavior

Use the [stage-selection table](references/physical-device.md#select-the-affected-behavior): `acoustic` for one real input turn, `multi` for multi-turn/persistence, `cancel` for End during recording/recovery, and model-free checks for applicable selector/cleanup repairs. Recording cancellation does not qualify inference cancellation or background execution. Do not repeat the whole qualification ladder for every task or skip gates for changed contracts.

#### Prepare first, then run one selected scenario

Follow the [preparation and runtime commands](references/physical-device.md#prepare-first-then-run-one-selected-scenario). They retain exact-PID idle handling, frozen fixtures, playback acknowledgments, bounded execution and ownership-aware cleanup. Read saved failure/summary/cleanup reports before considering another run.

### Device Hub manual/premium fallback

Use the [Device Hub fallback](references/physical-device.md#device-hub-manualpremium-fallback) only for authorized physical typed/visual work that cannot be proved on a simulator. It is not microphone acceptance. Do not bypass the installed-build/backend or idle-ownership rules.

## Live AI checks

Read [live-provider checks](references/physical-device.md#live-ai-checks) only for that affected behavior. Provider calls require a valid key entered through Settings and an authorized live run; never expose keys in commands or evidence. Debug helpers incur usage and do not establish audible output or native local acceptance. A missing key or authorization is a blocker for those checks, not for unrelated local/UI work.

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

This section applies only to simulators. Physical runs use the [owned-process/settings cleanup](references/physical-device.md) in their workflow; never shut down the physical phone.

Cleanup is an acceptance gate, not an optional final instruction. Require `cleanup.json` with `cleanup: PASS` and `final_state: Shutdown`; also inspect the separate command status. Preserve all evidence/app data. A finalizer failure makes the run fail even if tests passed. An ordinary signal cannot interrupt the final cleanup a second time.

SIGKILL or host failure can bypass cleanup. Inspect `session.json`, `command-process.json`, helper ownership records and the exact UDID's lock metadata. Compare PID/PGID, start time and command to current `ps` output before signaling anything. Never automatically reclaim a stale-looking owner or shut down a borrowed booted device. Once ownership is established and surviving owned work is stopped, gracefully finalize recorded captures/helpers, run `xcrun simctl shutdown <that-owned-UDID>` and confirm its state via `simctl list devices -j`. Save the recovery result. Do not erase, delete, uninstall, clear caches/models, shut down all devices, or globally quit Simulator as recovery. The only test-cleanup deletion exception is an explicitly approved temporary device under the lifecycle policy above; never delete the retained primary.

Required closeout: supported checks PASS/FAIL/BLOCKED; profile/runtime/CLI; evidence paths; owned helper/recorder stops; every owned simulator Shutdown; cleanup PASS/FAIL; other projects not targeted; physical microphone/model/native-background checks not run unless separately authorized and actually executed.

## Feature map

Consult [features/README.md](features/README.md) when coverage is unclear, or go directly to the affected feature. Load relevant sections, not every file:

- `features/onboarding-consent.md`
- `features/themes-words-settings.md`
- `features/ui-animation.md`
- `features/conversation-lifecycle.md`
- `features/local-conversation.md` (physical local work)
- `features/live-ai-device.md` (physical live-provider work)

Match the check to the changed behavior. Prefer one sufficient real-path UI journey with outcome assertions; do not automatically run overlapping suites. Layout changes need affected-screen evidence and applicable large-text/appearance checks; include transitions when motion or transient state is affected. Search semantics require filtering/recovery cases, and persistence changes require the appropriate relaunch/reboot path. Repeated gestures can prove distinct behaviors: changing versus reselecting, retaining across relaunch, or the same query under a different filter. Do not delete them merely because the interaction repeats.

For changed data semantics, use assertions against production code for exhaustive matrices plus representative real UI integration; identify material failure cases and write any necessary isolated checks before implementation. Do not reproduce the algorithm in the test or migrate unrelated coverage for this tooling rollout. Retain meaningful UI-state waits and target-driven scrolling.

Reuse saved evidence only after checking relevant production/test/fixture code, build configuration, runtime/Xcode, profile/CLI and exercised state. Record current input hashes and revision/dirty state beside measurements. An old app pass does not qualify new harness behavior or changed inputs; rerun affected checks, not automatically every overlapping suite.

## Failure behavior

- A build failure is a build failure, not a UI result.
- A live frame, process existence, or accepted input event is not readiness or success. Confirm the foreground bundle and changed visible state.
- A missing API key, unavailable phone, signing failure, microphone permission denial, or broken Device Hub input is a named blocker. Do not turn it into a pass by skipping the check.
- If Mural exits, inspect `~/Library/Logs/DiagnosticReports/Mural-*.ips` and the relevant test or simulator logs before retrying.
- An unchanged UI or repeated failure needs a supported explanation before another attempt. Preserve the evidence and confirm cleanup, then use a correction or new observation that predicts a different result. Do not vary gestures, reboots or timeouts blindly; use a supported alternative with independent readback or report the blocker.

## Quick run

```sh
cd "$(git rev-parse --show-toplevel)"
: "${SIM_UDID:?Choose an explicitly owned Shutdown iPhone 17 simulator}"
active-ios-simulator-limit run -- make agent-verify SIM_UDID="$SIM_UDID" \
  TESTS='testOnboardingChoosesLearningAndSubtitleLanguagesWithoutAnAccount'
```

This is a focused synthetic UI check, not the complete smoke selection or a microphone/model test. Inspect the xcresult screenshots and compact summary **after confirmed shutdown**. For broader qualification and the finalized Settings movie, omit `TESTS` and set `VERIFY_SUITE=qualification`. For an animation-only change, select `testSettingsDropdownTransitions` directly. Use `SIMULATOR_MODE=stock` to deliberately restore managed services, not to bypass ownership/cleanup.

Invoke this skill with `/skill:verify-mural` from Pi.
