# Simulator verification lifecycle and SimSlim rollout

## Purpose and approval boundary

Reduce Mac memory used by Mural's simulator verification without weakening verification or disrupting StrengthLogger, other agents, or the user's physical iPhone.

The agreed design is a thin Makefile, a bounded simulator lifecycle script adapted from StrengthLogger, Mural-specific SimSlim profiles, and evidence-backed shutdown. Preserve `xcbeautify` and the existing `.build/verification/` evidence layout.

**Current authorization: implement the simulator rollout, including builds, owned simulator operations, SimSlim setup and verification.** Physical iPhone operations, commits and pushes remain excluded. Preserve unrelated work and the existing Git index.

## Two linked verification tracks

This document owns **simulator memory optimization and automatic cleanup**. The companion [physical iPhone E2E plan](physical-iphone-e2e-plan.md) owns **native device automation with Mac-speaker speech input**, real microphone/model execution, output-speech evidence, and phone-test cleanup.

Keep separate progress and acceptance gates. Physical testing must not block simulator cleanup, and a simulator pass must not be counted as a real voice/model pass. Share the thin Makefile and existing evidence conventions, not a new cross-platform harness:

- `make agent-verify SIM_UDID=...`: default slim simulator verification with enforced shutdown.
- `make agent-verify-device DEVICE_UDID=...`: explicitly requested physical test, once qualified; never an automatic dependency of simulator verification.

The simulator command is implemented and qualified, with focused selection or a three-check smoke fallback; explicit `VERIFY_SUITE=qualification` retains the 13-check rollout coverage. The physical command remains planned, not implemented. Recommended sequence remains simulator rollout first, then the separately authorized bounded physical feasibility gates. Phone connection and proximity are necessary but not sufficient: the companion plan also covers signing, model readiness, audio routing, capture/playback synchronization, privacy, and resource stops. No SimSlim or simulator-shutdown operations apply to the physical phone.

## Progress tracker

Status values: pending, in progress, complete, blocked. Complete means the stated acceptance evidence exists, not just that files were edited. Update this table and the implementation log after each stage. Record failed attempts and blockers rather than silently replacing them with passing results.

| Stage | Status | Deliverable / completion evidence |
| --- | --- | --- |
| 0. Read-only review and plan | complete | Reviewed Mural's instructions, verification skill, recorder, relevant UI tests, app integrations, and StrengthLogger's implementation/results. This document records the proposed rollout and device-only boundaries. No runtime verification performed. |
| 1. Baseline and acceptance checks | complete | Reproduce the documented cleanup gap on an explicitly owned synthetic simulator; record stock memory and define runnable lifecycle checks before implementation. |
| 2. Enforced ownership and cleanup | complete | Adapt the proven lifecycle runner; exact simulator selection, shared per-device locking, bounded commands, cleanup on ordinary exits/signals, verified Shutdown. |
| 3. Thin Makefile and Mural tool integration | complete | Consistent build/verification commands, unchanged evidence conventions, owned serve-sim/recorder finalization, no untracked test-worker simulators. |
| 4. Measure Mural-specific slimming | complete | Compare stock and candidate profiles, inspect exact service state, measure repeated paired medians, and reject candidates that compromise supported checks. |
| 5. End-to-end proof and isolation | complete | Existing representative UI flows, reboot-retained settings, failure-path checks, finalized video, and controlled other-device preservation. Phone-only behaviors explicitly excluded from simulator claims. |
| 6. Default policy and handoff | complete | Validated profile is default; stock restoration and lifecycle checks pass. [Speedup plan](simulator-test-speedup-plan.md) measured smoke at 4m23s/4m35s and final focused recording at 4m27s. Instructions, repeat commands, limitations and final closeout saved; all three owned simulators and helpers stopped. |

- [x] Stage 0: read-only review and plan saved
- [x] Stage 1: baseline and pre-implementation checks
- [x] Stage 2: ownership and cleanup
- [x] Stage 3: Makefile and tool integration
- [x] Stage 4: measured profile selection
- [x] Stage 5: E2E and failure-path evidence
- [x] Stage 6: default instructions and final closeout

## Findings from the review

These are historical pre-implementation findings; completed changes and acceptance evidence are recorded below.

1. Mural has no root Makefile. Its verification skill currently supplies direct `xcodebuild` commands. This is not inherently wrong, but repeated command assembly makes omissions more likely.
2. The skill's quick-run exit trap stops serve-sim and terminates Mural, but does not shut down its simulator. The general shutdown instruction is advisory, not an enforced lifecycle. This is a source-level finding; Stage 1 must reproduce it on a synthetic owned device.
3. Mural already has a bounded recorder at `.agents/skills/verify-mural/scripts/record-simulator.py`. Reuse it rather than replacing it with another recording framework.
4. Mural uses speech, `AVSpeechSynthesizer`, Foundation Models, local recognition, and model assets. SimSlim's `siri` group also covers voice, natural-language, and system model services. Keep the entire group enabled; StrengthLogger's profile is unsuitable unchanged.
5. `App/SpeechSetupContinuation.swift` uses `BGContinuedProcessingTask`. Apple documents that the system displays its progress in a Live Activity. Keep `com.apple.liveactivitiesd`; do not disable the whole widgets group simply because Mural has no conventional widget extension.
6. Account/authentication configuration, secure credentials, backup/share workflows, and web links also warrant keeping their supporting services. Absence of a direct framework import alone does not prove a daemon is unnecessary.
7. Preview conversations are temporary/in-memory. Existing preview History assertions do not prove disk persistence through process termination or simulator reboot.

## Verification boundaries: simulator versus physical iPhone

The user confirms that Mural can be verified on the simulator only to a limited extent. Real recording and the demanding built-in AI/model pipeline require the physical iPhone for current acceptance. This rollout must respect that boundary.

| Surface | What this plan can establish | What it must not claim |
| --- | --- | --- |
| Simulator preview UI | Onboarding, consent/guard UI, navigation, settings, language/backend selection, transcript display, synthetic setup/cancellation states, accessibility layout, recorded UI transitions | Actual microphone fidelity, model download/load/inference, recognition quality, native cancellation/drain, or real background execution |
| Simulator normal launch on a synthetic device | Exact settings retained after termination/shutdown/reboot; disk-backed app behavior only where a real, safe user-facing path is actually exercised | Preview data retention as proof of durable conversations; a selected backend as proof it loaded |
| Simulator lifecycle tooling | Ownership, profile state, memory used by supported simulator workloads, error handling, helper finalization, and shutdown | iPhone RAM savings, AI-model performance improvements, or whole-Mac memory guarantees |
| Physical iPhone | Real microphone/ASR, built-in Apple model availability/loading/inference, TTS/listening, audio routes, native setup/background behavior, thermal/memory characteristics | None of these are proved by the simulator suite |

### Rules for model and audio checks

- No supported end-to-end simulator path for Mural's required built-in model and production recording/AI flow has been established by this review. Treat those as physical-device qualification, not pending simulator tests to keep retrying.
- Some simulator audio or ML APIs may work in isolation. That does not qualify Mural's complete pipeline or reproduce iPhone hardware/resource behavior.
- Do not load/download large model assets, add a substitute backend, enable experimental inference flags, or fabricate a successful model result to make this rollout pass.
- Synthetic setup, thermal, memory, and cancellation scenarios test UI/coordinator behavior only. Label them explicitly as synthetic, not native execution proof.
- Simulator screen video proves visible UI and recorder cleanup, not microphone recording or audible speech correctness.
- Physical-device-only does not mean every action must be manual. The companion [physical iPhone E2E plan](physical-iphone-e2e-plan.md) qualifies native UI automation plus Mac-generated speech played into the real phone microphone. Until qualified, preserve Mural's current paired-phone workflow and reuse prior confirmations. Afterwards, retain targeted human prerequisites/listening checks only where automated evidence is insufficient; do not repeat accepted phone checks merely because simulator tooling changed.
- No phone build/install or model/cache changes are needed for this simulator-only rollout. Keep the existing phone bundle identity, signing, Release recipe, and explicit Core AI opt-in unchanged.
- If a credible supported simulator model path is discovered later, report its exact framework/runtime requirements and limitations first. Propose a separately scoped feasibility check rather than silently expanding this plan.

A successful rollout can therefore be complete for simulator tooling while audio/model acceptance remains **outside this simulator track** and is tracked independently in the companion plan. Until physical checks actually run, report them as not run. An unavailable simulator capability is not a product failure or permission to weaken assertions.

## Intended architecture

```text
make build
  -> existing Xcode build settings
  -> readable output plus saved raw logs
  -> no simulator boot

make agent-verify SIM_UDID=<explicit owned device>
  -> prepare build artifacts before boot where practical
  -> bounded lifecycle runner
     -> validate initially Shutdown device and acquire shared lock
     -> apply/verify Mural profile, or explicitly restore stock
     -> boot readiness and serial supported app checks
     -> preserve logs, xcresult, screenshots, video and reports
     -> finalize owned helpers and restore changed settings
     -> shut down only the owned simulator
     -> confirm Shutdown and record cleanup status
```

Make is a thin command menu, not a replacement for Xcode's build system. Keep lifecycle logic in the existing Python pattern, not complicated Make recipes. Do not import StrengthLogger's entire tooling package or add a cross-repository framework.

## Stage 1: Baseline and checks before implementation

- Preserve unrelated work and record the revision/dirty state.
- Select an installed iPhone 17-family runtime compatible with Mural, initially iOS 27 to match the current workflow. Discover identifiers; never copy StrengthLogger's device IDs.
- Create one clearly named Mural synthetic trial device and record ownership. Reuse it throughout; do not repeatedly create replacements after failures.
- Reproduce the current quick-run cleanup gap using the closest bounded real app path. Save final device state, then explicitly shut down that owned device. If blocked, record the blocker and use the narrowest reliable reproduction.
- Establish a stock baseline with the same preview fixture and app/helper state that later candidates will use.
- Adapt runnable lifecycle/mode acceptance checks before changing runner behavior. Reuse StrengthLogger's proven checks with Mural paths and synthetic-device guards; no new testing framework.

Failure cases to cover:

- Success, failed command, timeout, SIGINT, SIGTERM, or SIGHUP leaves a simulator/helper running.
- Invalid/missing UDID, borrowed booted device, or lock contention selects or stops the wrong device.
- A second project uses the same device concurrently.
- Profile setup fails partway through; tests still run or cleanup is skipped.
- Missing/unreviewed SimSlim, malformed/unknown profile, unsupported runtime, or conflicting options silently bypass slimming.
- Explicit stock mode leaves managed overrides disabled.
- Cleanup failure hides the original test failure or is reported as success.
- A recorder is killed before finalizing; screenshots/logs/results are overwritten or removed.
- Settings changed for checks remain altered; simulator data is erased during cleanup.
- Test parallelization creates unowned worker simulators.

Acceptance: a recorded baseline and repeatable pre-implementation checks exist; the reproduced owned device is Shutdown.

## Stage 2: Enforced ownership and automatic cleanup

Adapt StrengthLogger's `scripts/verify_simulator.py`:

- Require an exact available iOS simulator UDID and an initially Shutdown device. A familiar device name does not establish ownership.
- Use the same real-user lock location: `~/Library/Caches/ios-verification/<UDID>.lock`. Keep cross-project lock semantics intact.
- Record device/runtime, initial state, owner PID, command/process-group identity, evidence directory, requested mode, profile hash, and reviewed CLI version.
- Enclose the full runtime operation in a finite deadline; stop only the owned command group and explicitly tracked detached helpers.
- Handle success, failure, timeout, and ordinary signals. Bound finalization separately so cleanup can finish after a test timeout.
- Preserve command status separately from cleanup status. Return failure when cleanup cannot be confirmed, even if app checks passed.
- Confirm Shutdown through `simctl`, not merely a successful shutdown command or closed window.
- Preserve app data, preferences, caches, model assets, and evidence. Shutdown is not erase/uninstall.
- Resolve the default profile relative to the repository script, not the caller's current directory. Change evidence defaults to `.build/verification/`.

SIGKILL and host failure can bypass cleanup. Preserve owner/process evidence and document conservative manual recovery; never automatically kill stale-looking PIDs or reclaim someone else's booted simulator. The per-device lock does not protect a shared DerivedData directory.

Acceptance: success/failure/signal/timeout/ownership scenarios pass with retained evidence and confirmed shutdown.

## Stage 3: Thin Makefile and existing tool integration

Implemented entrypoints (current selection policy is detailed in the final handoff):

```sh
make build
make agent-verify SIM_UDID="$SIM_UDID"
make agent-verify SIM_UDID="$SIM_UDID" SIMULATOR_MODE=stock
```

- `make build` compiles without booting a simulator; retain Mural's scheme/configuration and arm64 simulator requirements.
- `make agent-verify` runs the documented supported acceptance selection with serial simulator testing. Document a focused selector for narrower future changes instead of running every unrelated test by default.
- Preserve `set -o pipefail`, `tee`, `xcbeautify --is-ci`, unique xcresult paths, and compact `xcresulttool` summaries. Add at most a small shared build-command script if needed to avoid duplicated logging logic.
- Keep `.build/verification/<unique-run>/` as the evidence root. Never move evidence into StrengthLogger's `.pi` convention.
- Keep reusable DerivedData under `.build/`; isolate concurrent Mural jobs by agent/job or reject contention. Do not run concurrent builds/tests against the same directory. Do not add automatic cache cleaning.
- Standardize `SIM_UDID` at the public entrypoint. Explicitly pass it as `SIM` to existing Mural commands where needed so build, launch, input, capture, and cleanup cannot diverge.
- Use `-parallel-testing-enabled NO` to prevent untracked simulator workers. Avoid unnecessary serve-sim startup for native tests.
- Reuse the existing recorder. Record ownership, request graceful finalization, wait, then validate the movie before shutdown. Ensure the enclosing timeout includes bounded finalization.
- Start serve-sim only when required; do not take over an existing mirror. Stop only the mirror started by this run and verify it stopped.
- Restore changed appearance, text-size, or accessibility settings before shutdown. Save finalizer errors, not unconditional success.
- Prefer one bounded script over separate tool calls that leave a device running between turns. Interactive sessions still require explicit ownership and closeout; a trap in an already-finished shell cannot protect later calls.
- Do not add a manual phone launcher or change the paired-device recipe as part of this rollout.

Acceptance: one consistent command runs supported checks, saves the expected evidence, stops its helpers, and confirms Shutdown even when a check fails.

## Stage 4: Mural-specific profile selection and measurement

### Service policy

Use the reviewed SimSlim 0.11.0 behavior as the starting point. Confirm the installed version before mutation; a different version requires category/label review, not an automatic upgrade. Install only if needed during an authorized implementation stage. SimSlim is a developer CLI, not an app dependency.

| Group | Proposed policy and reason |
| --- | --- |
| Siri / Intelligence / speech | Keep the whole group. It includes voice, language, and system model services relevant to Mural. |
| Widgets / wallpaper / Live Activities | Keep the whole group initially. `liveactivitiesd` must remain enabled for the continued-processing integration. |
| iCloud / Apple Account / Keychain | Keep. Account, credential, file-sync and backup behavior must not be casually weakened. |
| Store / push / media; web services | Keep. Preserve supporting media, authentication, link and system behavior. |
| Diagnostics / DeviceCheck; miscellaneous assets | Keep. Preserve diagnostics, attestation support, and system asset handling. |
| Photos/media analysis; messaging/calls; connectivity | Keep initially. Broad groups have possible audio, identity, or sharing interactions; do not remove them merely because no direct import was found. |
| Spotlight/system search | First candidate reduction. Check Mural's own search UI remains functional; system search is a separate capability. |
| Health/Home/Fitness; Mail/Calendar/Contacts; Family/Screen Time; News/Weather/Maps/Games | Broader candidate reductions after checking current capabilities and exact labels. Use stock for integrations affected by them. |

Candidate progression:

1. **Stock:** restore and verify all SimSlim-managed overrides before measuring.
2. **Conservative:** disable system search only; retain the remaining categories.
3. **Broader Mural profile:** additionally disable the four currently unrelated groups listed above, after label review.
4. **Optional wallpaper-only trial:** disable `com.apple.PosterBoard`, keeping `com.apple.chronod` and `com.apple.liveactivitiesd` through SimSlim's existing per-service `keep` support. Do not assume this is safe from StrengthLogger's result. If evidence is insufficient or behavior regresses, retain the entire widgets group.

Do not require a particular daemon count or memory percentage. Keep one validated default profile; retain trial variants in evidence unless a concrete ongoing use justifies another committed profile.

### Measurement method

- Same device/runtime, app build, synthetic fixture, screen, and helper configuration for stock and candidates.
- Use an identical settling interval, initially 60 seconds, then five `simslim measure --json` samples five seconds apart.
- Perform at least two paired comparisons, reversing profile order to reduce startup/order bias. Do not compare different workloads or add category estimates together.
- Save raw samples, medians, exact service state, version/profile hash, and cleanup result after every run.
- Measure a supported preview/UI workload, not native AI loading or inference. Avoid leaving a mirror/recorder running in only one measurement arm.
- Report process-footprint measurements as simulator observations, not whole-Mac RAM savings or iPhone model performance.
- Prefer a smaller, repeatable benefit that preserves reliable checks over a larger result that makes verification misleading.

StrengthLogger's approximately 45% additional saving was expanded versus its conservative profile on a particular workload. It is not Mural's predicted saving. Mural intentionally retains more services. Most importantly, shutting down idle simulators removes their ongoing device workload regardless of the chosen profile.

Acceptance: the chosen profile has repeatable measured benefit and passes supported app checks. If no candidate qualifies, keep enforced cleanup and report default slimming as blocked rather than promoting an unsafe profile.

## Stage 5: Real-path checks, retention, and isolation

Reuse a focused medium-to-hard selection from `UITests/MuralUITests.swift`, including:

- Onboarding language selection and consent/missing-key boundaries.
- Meaning-language/backend selection and unsupported combinations, without loading real models.
- Synthetic setup cancel/drain/retry, including language changes while an old job drains.
- Apple/Mural voice selection, reselection, and relaunch-retained preferences; do not claim speech output from a picker assertion.
- Theme navigation, secure-settings/backup controls, ended transcript, explicit New conversation, and retained preview History.
- Large Dynamic Type and one recorded Settings transition with inspected frames. Reuse the existing animation workflow, not just screenshots of the settled screen.

Select existing test names at implementation time rather than assuming the current suite is frozen. Run the same supported acceptance selection with the candidate and with explicit stock restoration.

Retention check:

- Use a normal non-preview synthetic installation to change a safe setting through the UI.
- Terminate, shut down, reboot, and assert the exact value before changing it again. Repeat with stock restoration.
- Do not call preview History a disk-persistence check. Add a real disk-backed conversation check only if an existing safe UI path does not require unavailable model execution or paid provider calls. Otherwise report that boundary explicitly; do not add a fake production backend.

Lifecycle proof:

- Adapt the existing runnable success/failure/timeout/signal/lock/profile/stock/finalizer checks before modifying their behavior.
- Use a separately owned, controlled sentinel device to prove isolation, then shut it down through its own enclosing lifecycle. Do not depend on another active project's simulator remaining in a fixed state.
- Verify evidence survives cleanup, recordings decode, helper processes stop, exact retained settings persist, and every owned trial/control device ends Shutdown.
- Report skipped/inconclusive checks separately; do not count them as passes.

Acceptance: supported simulator checks and lifecycle checks pass in slim and relevant stock runs, with inspected visual artifacts and honest phone-only exclusions. No physical AI/audio replay is required solely to validate simulator tooling.

## Stage 6: Default policy, documentation, and handoff

Once the profile passes Stage 5:

- Make validated slimming the default for simulator verification, not an optional flag agents must remember.
- Make `SIMULATOR_MODE=stock` / runner `--stock` explicitly restore and verify SimSlim-managed services. Omitting a profile must not masquerade as stock, because overrides persist.
- Require the reviewed CLI for both profile application and reliable stock restoration. Missing CLI fails before tests with clear installation guidance; no silent heavyweight fallback. Pure compilation remains available without SimSlim.
- Fail safely for unknown versions, unsupported runtimes, invalid profiles, and setup failures; still clean up any resources owned by the run.
- Retain the profile across simulator shutdowns; do not undo it and reboot again after each verification.
- Require stock for real system-integration checks affected by disabled services. Stock restoration covers SimSlim-managed overrides, not arbitrary manual device modifications.
- Update `AGENTS.md`, the parent verification skill, feature map, animation guide and affected feature commands so documented entrypoints cannot quietly bypass lifecycle cleanup.
- Preserve device-only instructions and clearly separate synthetic previews from native model/audio evidence.
- Include the repeat commands, evidence paths, measured result, and manual forced-kill recovery instructions in this plan.
- Shut down before reviewing saved artifacts or reporting completion. A Simulator window may remain open without a booted device; never globally quit Simulator or stop another project's device to make a cosmetic claim that no windows remain.

Required closeout:

```text
Supported simulator checks: PASS / FAIL / BLOCKED
Profile / runtime / CLI version: recorded
Measurements: raw samples and comparison path
Evidence: xcresult, logs, screenshots, finalized video, reports
Owned helpers/recorders: stopped, or explicit failure
Owned simulator(s): Shutdown
Other projects' resources: not targeted
Cleanup: PASS / FAIL
Physical recording / AI model / native background execution: outside scope, not run
```

## Intended file changes

| File | Intended change |
| --- | --- |
| `docs/simulator-verification-lifecycle-plan.md` | This plan, stage status, decisions, repeat commands, and evidence log. |
| `Makefile` | Thin build/agent-verification entrypoints and explicit slim/stock selection. |
| `scripts/verify_simulator.py` | Adapt StrengthLogger's lifecycle runner to Mural's paths and evidence conventions. |
| `scripts/check_simulator_lifecycle.py`, `scripts/check_simulator_modes.py` | Adapt existing runnable checks and synthetic-device guards, before implementation changes. |
| `.agents/skills/verify-mural/simslim-default.json` | The measured, validated Mural-specific default profile. |
| `.agents/skills/verify-mural/SKILL.md` | Required lifecycle, exact ownership, new commands, default policy, failures, and final closeout. |
| `.agents/skills/verify-mural/features/README.md` and affected guides | Supported acceptance map, bounded recording/cleanup, stock exceptions, and simulator/device evidence boundaries. |
| `AGENTS.md` | Concise mandatory verification entrypoint and cleanup policy. |

Reuse the existing recorder without changing it unless integration exposes a concrete defect. Add a small build/finalizer script only where needed to centralize real repeated logic. No production Swift changes are planned; an identified app defect or unsupported test path is a separate finding, not permission to expand this tooling rollout.

## Evidence and progress updates

Evidence root: `.build/verification/simulator-lifecycle/<unique-run>/`.

Expected artifacts, as applicable:

- `session.json`, `command-process.json`, initial/final device snapshots.
- Reviewed profile copy/hash, CLI/runtime details, `service-state.json`.
- Formatted-command status, raw build/test logs, unique xcresult, compact test summaries.
- Raw memory samples and `memory-comparison.json`.
- Screenshots/accessibility output, finalized movie, decode result, inspected frame/time notes.
- `cleanup.json` distinguishing command result from cleanup result.
- `result.md` with expected/observed outcomes and explicit evidence limits.

Keep evidence local and uncommitted. Review for private content before sharing. Progress notes should link evidence without copying transcripts, credentials, or large logs into tracked documents.

For each stage update, record:

1. What changed and which acceptance checks ran.
2. Commands and evidence paths, including failed attempts.
3. Observed result, blockers, and any justified plan adjustment.
4. Owned-resource cleanup state.
5. Next stage, or the reason work stopped.

## Safety and scope exclusions

- No `shutdown all`, unscoped serve-sim kill, `killall Simulator`, or global SimSlim watcher.
- No simulator erase/delete, app uninstall, history reset, model/cache removal, container seeding with private data, or host-network changes.
- No interference with StrengthLogger or other active agents; no borrowing their device IDs.
- No physical-device install, microphone exercise, AI-model load, model transfer, or changed phone flags under this rollout.
- No paid provider calls, credentials in commands/evidence, signing changes, generated project edits, publication, or commits.
- No claim that a build proves UI behavior, that preview events prove native AI execution, or that simulator savings predict device inference performance.
- No new background control plane, cross-project framework, or build-system migration.

## Implementation log

### Planning checkpoint

- Read-only review completed and recommendations discussed with the user.
- User accepted adding a thin Makefile while retaining `xcbeautify` and `.build/verification/`.
- User explicitly emphasized simulator limitations for microphone recording and demanding built-in AI/model loading; these are now acceptance boundaries, not deferred simulator tasks.
- Saved this plan only. No build, test, simulator boot/shutdown, SimSlim mutation, dependency install, model operation, or phone action performed.
- Stages 1-6 remain pending for review and implementation authorization. No memory saving or runtime behavior has been measured for Mural under this plan.

### Physical automation planning extension

- User requested an automated acoustic input path: the Mac plays generated speech and a connected nearby iPhone records it through Mural.
- Added the linked `physical-iphone-e2e-plan.md` with its own progress tracker, native-XCTest qualification, capture/playback coordination, real-model checks, audible-output evidence, preservation rules and cleanup gates.
- Kept simulator stages and scope unchanged. The proposed physical Make target is opt-in; no routine simulator command may start phone testing or audible playback.
- This update changes plans only. No device operations, audio playback/capture, model work, builds or tests performed.

## References

- [Physical iPhone E2E and acoustic speech plan](physical-iphone-e2e-plan.md)
- [Mural agent instructions](../AGENTS.md)
- [Mural verification skill](../.agents/skills/verify-mural/SKILL.md)
- [Local conversation and paired-phone workflow](../.agents/skills/verify-mural/features/local-conversation.md)
- [Conversation lifecycle evidence boundaries](../.agents/skills/verify-mural/features/conversation-lifecycle.md)
- [UI animation and bounded recording](../.agents/skills/verify-mural/features/ui-animation.md)
- [StrengthLogger rollout and adoption lessons](../../StrengthLogger/docs/simulator-verification-lifecycle-plan.md)
- [Apple: BGContinuedProcessingTask and its Live Activity](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)
- [SimSlim](https://github.com/MobAI-App/simslim), with exact installed-version/category review required before use.

### Implementation authorization and Stage 1 preparation

- User authorized the simulator rollout; no phone actions, commits or pushes.
- Evidence root: `.build/verification/simulator-lifecycle/rollout-20260927-085406/`.
- Preserved starting revision `45caaf3d35b1459cdccceffcb1c94b19ffc97dc5`, dirty status and exact staged patch in that evidence directory. The pre-existing staged plan and untracked physical plan remain untouched in the index.
- Created only Mural synthetic trial `C094F154-7674-4A17-9F6B-319959B1F49A` (Mural Lifecycle Verification, iPhone 17 / iOS 27.0). Initially Shutdown. No existing simulator claimed.
- Reviewed installed SimSlim 0.11.0 category/label listing (`simslim-profiles.json`); no installation/upgrade needed. Siri, widgets/Live Activities, accounts, media, web, diagnostics and assets must remain enabled.
- Adapted StrengthLogger's runnable lifecycle/mode checks before implementing the runner. Mural has no name resolver; invalid-selection checks target the exact-ID runner interface instead. Optional old-runtime refusal must also use a Mural-owned synthetic device, never an existing other-project device.

### Stage 1 complete

- Fresh Debug arm64 simulator `build-for-testing` passed without booting any device (`baseline-build.log`). Existing app warnings: iOS 27 audio-interruption deprecations, LiveTransport async-alternative suggestion, signed WebRTC stripping warning. No build errors.
- `baseline-command.sh` reproduces the quick-run's real install/preview-launch/app-termination path, omitting its mirror and unrelated UI test so the measured workload has no helper. `baseline-stock/gap-result.json` asserts the old cleanup leaves **Booted**. Inspected `baseline.png`: Mural's synthetic greeting UI, not native microphone/model execution.
- Used StrengthLogger's unchanged runner in explicit stock mode as the outer safety envelope for this pre-implementation reproduction. No StrengthLogger files or devices were mutated. `baseline-stock/cleanup.json`: command 0, cleanup PASS, final Shutdown.
- Five stock samples after 60 seconds, 5 seconds apart: median **2630.0 MiB**, saved in `baseline-memory.json`. This first-boot baseline is not paired savings evidence.
- Adapted pre-implementation mode check fails because the Mural runner does not yet exist (`modes-before.log`). Runnable checks and failure cases predate runner changes.
- Stage 2 begins; only the recorded trial is owned, and it is Shutdown.

### Stage 2 complete

- Adapted `scripts/verify_simulator.py` directly from StrengthLogger, retaining the real-user cross-project per-UDID flock, exact available iOS ID/Shutdown guard, separate command and cleanup statuses, finite setup/command/finalizer/shutdown bounds, ordinary-signal handling and conservative forced-kill recovery.
- Mural changes: repo-relative profile, `.build/verification/` defaults, identical `SIM` and `SIM_UDID`, requested mode in session evidence, 30-second SIGINT grace for Mural's recorder (which allows 25 seconds to finalize). Default profile is **provisional search-only**, not promoted/qualified.
- `lifecycle-1/result.json`: all 13 scenario groups PASS, including failure 23, timeout 124, SIGINT/SIGTERM/SIGHUP, concurrent-owner rejection, prebooted refusal, finalizer failure, child termination, decodable recording and retained artifacts. Cleanup failure remains failure even with a successful command; original command 23 is retained when both fail.
- Created separately owned Mural control `0118BF91-AD6C-4C1B-A998-3659E3A594FD`. It remained Booted throughout isolation checks, then `control-1/cleanup.json` confirmed Shutdown. Trial also Shutdown. An external session changed a non-owned simulator's state; it was observed only, never targeted, and not used as the isolation oracle.
- Stage 3 pre-implementation failure checks: reject invalid Make mode before building; reject shared DerivedData contention; never boot for pure compilation; propagate build/pipeline failures; timeout/cancellation must await runner shutdown; native tests must select the same UDID serially; recorder must finalize and decode before shutdown. Existing lifecycle/mode checks cover core cleanup, while real Make/UI runs will cover integration.

### Stage 3 complete

- Added the thin Makefile with `make build` and `make agent-verify SIM_UDID=... [SIMULATOR_MODE=stock]`. Shared shell command assembly preserves raw logs, pipefail, xcbeautify, unique result bundles and compact summaries. No phone target or recipe changed.
- `scripts/mural_simulator.py` holds a nonblocking canonical DerivedData lock across preparation and the lifecycle command. Generic arm64 build-for-testing finishes before boot. Cancellation forwards to and awaits lifecycle cleanup; standalone compilation is bounded and stops its own process group. `lock-refusal.log` proves concurrent build refusal before Xcode. `make-build/` proves compilation works without booting the controlled simulator.
- `modes-1/result.json`: ten default/custom/stock/setup-error/missing-tool/version/Make-mode checks PASS. Unsupported-runtime check remains for Stage 5; no existing other-project old-runtime device was used.
- `ui-stock-1/`: one Make command passed all 11 supported selection tests and the separate Settings dropdown transition test (12 total, zero skipped). Exact trial UDID and serial testing recorded. Before/after device IDs match: no new worker simulators.
- Existing bounded recorder reused unchanged; PID/owner/log saved, movie finalized (139.408 seconds), positive-duration ffprobe and full ffmpeg decode passed before Shutdown. No serve-sim mirror was needed or started by native tests. Detached helpers still require an explicit ownership-aware cleanup hook; do not start them outside the enclosing lifecycle.
- `ui-stock-1/cleanup.json`: command 0, cleanup PASS, Shutdown. Control also remains Shutdown. Stock restored zero managed disables. Overview inspected after shutdown; detailed transition-frame inspection remains Stage 5.
- Added exact passed-count/zero-skips/device assertions to compact-summary handling so an empty or accidentally skipped test selection cannot count as acceptance.
- Stage 4 uses the same built app and explicit on-device **preview UI** fixture in every measurement arm, with no mirror/recorder. Profile choices are still candidates, not validated defaults.

### Stage 4 first comparisons: candidates not qualified

- `memory-comparison.json` records six clean boots, the same explicit preview screen/build/device, 60-second settle and five samples 5 seconds apart, order stock/conservative/broader/broader/conservative/stock. Every run confirmed Shutdown; images inspected show the same Spanish/English synthetic greeting UI.
- Stock medians: 2510.4 / 2600.0 MiB. Search-only: 4106.2 / 2708.0 MiB (both worse). Broader: 3557.8 / 2383.5 MiB (first worse; second saves 216.5 MiB, 8.3%). Neither candidate has repeatable benefit, so neither qualifies. Raw CPU/process counts show substantial startup activity; no samples were discarded or silently replaced.
- Exact category audit finds no Health/Home, PIM, Family, Maps/Games or CoreSpotlight integration in the current app. App search uses SwiftUI searchable over local records. Siri, widgets, account/keychain, media, web, photos, messaging, connectivity, diagnostics and system assets were retained. SimSlim verified the requested profile on every slim boot (5 / 47 disabled managed labels).
- Proceeding only to the already-authorized optional wallpaper trial: broader disables plus `com.apple.PosterBoard`, explicitly keeping `com.apple.chronod` and `com.apple.liveactivitiesd`. Save separate paired results, not replacements for the failed candidates. If it fails the same acceptance gate, stop promotion and report default slimming blocked.

### Stage 4 complete: Mural wallpaper exception qualifies for final acceptance

- `memory-wallpaper-comparison.json`: two new paired comparisons, reversing order, same 60-second settle/five samples/5-second interval and no helpers. Stock 2784.6 / 2694.7 MiB; candidate 2021.0 / 1972.2 MiB. Savings **763.6 MiB (27.4%) / 722.6 MiB (26.8%)**. These are summed simulator process footprints, not whole-Mac or iPhone savings. Earlier failed candidates remain fully recorded.
- Candidate disables search, Health/Home/Fitness, PIM, Family/Screen Time, News/Weather/Maps/Games, plus only PosterBoard from widgets. `wallpaper-service-audit.json` compares actual launchctl overrides to the exact 48-label expected set in both runs. Entire Siri group, chronod and liveactivitiesd remain enabled.
- `ui-wallpaper-1/`: all 13 supported UI tests PASS (12 main + 1 recorded transition), zero skipped, exact trial device. `search-stock/` also passes the added local theme-search check; together with `ui-stock-1/`, stock covers the identical 13 checks. Added E2E search coverage because previous navigation checks did not exercise local search filtering.
- Candidate recording finalized and fully decoded (121.187 seconds); cleanup PASS/Shutdown. All ten measurement runs ended Shutdown. No models, microphone capture, paid calls, or phone operations.
- Added opt-in normal-installation retention UI checks ahead of Stage 5 execution. They use no preview/default injection, never start a conversation, and skip outside an explicitly named Mural Lifecycle simulator. Summary assertions reject skips. The ordinary default suite excludes these multi-boot checks.
- Candidate is selected for Stage 5, not yet promoted as the routine default. Next: exact normal settings across reboot and stock restoration, final recorder/failure checks and inspected transition frames.

### Stage 6 checkpoint: routine speedup takes priority

- Promoted the measured service selection to `simslim-default.json`; service lists match the measured candidate. `lifecycle-default/result.json` passes all 13 lifecycle groups with the unchanged Mural recorder; controlled sentinel preserved. `modes-default/result.json` passes 12 profile/stock/setup/refusal groups. All owned devices ended Shutdown.
- Updated Make/lifecycle instructions and simulator feature guides; physical instructions remain separate. Final handoff is not yet complete.
- User requested a separately tracked, measured routine-test speedup before continuing. See [simulator-test-speedup-plan.md](simulator-test-speedup-plan.md). Focused/smoke dispatch and budget checks are now implemented, but measurements are blocked by an observed active StrengthLogger XCTest job; it was not interrupted. All three Mural-owned devices remain Shutdown. Final handoff stays paused until speedup measurements pass. The original 13-check qualification remains available; narrowing routine selection does not replace profile acceptance evidence.

### Stage 5 complete

- Same 13 supported checks passed on stock and the selected profile; videos finalized/decoded. `visual-inspection.md` records viewed overview/dense transition frames, actual time ranges, large-text screenshot and extraction limitations. No new affected-flow UI defect identified in the inspected transitions.
- `retention-exact-set/`, `retention-exact-slim/`, `retention-exact-stock/`, `retention-exact-restore/`: four normal-installation UI runs PASS, zero skipped. Exact accessibility values **French · France / German** survive process relaunch, simulator shutdown/reboot and explicit stock restoration, asserted before changing either value. Restored the UI-established baseline **English · International / Vietnamese**. Each run ends cleanup PASS/Shutdown. Earlier `retention-*` preliminary runs used substring assertions; these are superseded by the exact-value acceptance artifacts, not counted as additional proof.
- Disk-backed conversation creation is not claimed: no existing safe production path completes without unavailable model execution or provider use. Preview History tests prove only temporary UI behavior. No fake production backend or container seeding added.
- `check-helpers.py`, `helper-command.sh`, `helper-finalize.sh` are repeatable evidence scripts. `helper-check-results.json`: real owned detached serve-sim mirror plus unchanged Mural recorder finalized on success, failure 23, timeout 124 and SIGTERM 143. Every movie fully decodes; mirrors report stopped and all four recorded mirror PIDs are absent (`helper-process-closeout.json`). Only initially absent exact-device mirrors were started, with ownership intent before detach and identity checked before stop.
- `modes-partial/result.json`: 12 mode checks PASS, adding fault injection **after real SimSlim setup** (tests never start; cleanup still shuts down) and real unsupported iOS 18.2 refusal before boot. Created a third dedicated Mural Lifecycle Runtime Refusal simulator solely for this guard; its ID is in `old-udid.txt`, and it has never been booted. No other project's old-runtime device used.
- All currently owned trial/control/refusal devices are Shutdown. Stage 6 promotes only the already measured and UI-qualified service selection, then reruns default-mode/lifecycle routing checks and updates instructions.

### Stage 6 complete: resumed after measured speedup

- The separately tracked speedup passed: smoke whole commands **262.75s / 274.73s**, median **4m28.74s**; final focused recorded transition **266.58s**. All include incremental build, startup and confirmed shutdown. Test-action time is 75.8% lower than the broader qualification because selection narrows from 13 to three; identical test bodies did not get faster. See the speedup plan for exact boundaries, input manifests and preserved failed artifact-check attempts.
- During artifact audit, corrected only the recorded-video finalizer: direct strict source decoding requires positive duration, exact expected/decoded frame counts and an empty error log. It avoids null-output timestamp conversion errors without changing recordings or dropping frames. Valid/empty/truncated/no-recorder regression cases pass; final real focused recording decodes **3782/3782** frames. Historical stock/candidate movies also pass this stronger check (**2998/2998**, **3735/3735**). Reused unaffected smoke and app/profile acceptance rather than rerunning overlapping suites.
- Default service lists still exactly match the measured candidate; no further SimSlim changes. Earlier default lifecycle (13 groups), mode (12 groups), stock/slim 13-check UI qualification, exact reboot retention and real mirror/recorder success/failure/timeout/cancellation evidence remain applicable to unchanged behavior. Fresh Make smoke/focused runs validate the changed selection/budget/finalizer path. Native XCTest timeout options are enabled; no native-stall injection is claimed.
- AGENTS, parent skill, feature map and animation instructions now use the bounded entrypoints, focused-first selection, explicit broader qualification, honest timing/evidence reuse, native per-test bounds and strict source decoding. Physical recipes and the unrelated physical plan remain unchanged.
- `final-closeout.json` is saved in both evidence roots. Trial, control and old-runtime refusal devices all confirmed Shutdown; all four speedup runtime process groups gone; all four earlier detached mirror PIDs absent; trial mirror reports stopped. Original staged patch and unrelated physical plan remain byte-identical. No other-project device or physical iPhone targeted; no commit/push.

## Final handoff

### Results and evidence

| Check | Result / evidence |
| --- | --- |
| Mural-specific memory saving | **763.6 MiB / 27.4%** and **722.6 MiB / 26.8%**, paired simulator process-footprint medians; `memory-wallpaper-comparison.json`. Earlier failed candidates retained. Not whole-Mac or iPhone/model savings. |
| Profile / runtime / CLI | `.agents/skills/verify-mural/simslim-default.json`, iPhone 17 / iOS 27.0 (24A5423a), Xcode 27.0 (27A5252f), SimSlim 0.11.0. Exact disabled labels audited; Siri, chronod and liveactivitiesd retained. |
| Supported UI / retention | Same 13 supported checks passed on stock and selected profile; exact normal-installation language settings survived relaunch/reboot/stock restoration. No durable conversation or actual speech claim. |
| Cleanup / isolation | Lifecycle success/failure/timeout/ordinary signals/locks/setup/finalizer failures PASS; controlled sentinel preserved and then shut down. Real owned mirror and recorder cleanup PASS. |
| Routine performance | Smoke median **4m29s**, final focused recording **4m27s**, all accepted runs below ten minutes. Broader qualification remains separate. |
| Artifact validation | Strict full-frame source decoding; corruption rejected; inspected recordings/transition frames retained. |
| Physical microphone / AI / native background | **Not run, outside simulator authorization and acceptance.** |

Rollout evidence: `.build/verification/simulator-lifecycle/rollout-20260927-085406/`.
Speedup evidence: `.build/verification/simulator-test-speedup/run-20260927-114527/`, including `result.md`, `comparison.json`, `verify-results.py`, input manifests, xcresults, recordings and `final-closeout.json`.

### Repeat commands

Use an explicitly owned, initially Shutdown exact UUID; fresh evidence names are mandatory. Never substitute another project's device or run both overlapping selections automatically.

```sh
make build
# Known change: select the smallest sufficient affected check.
make agent-verify SIM_UDID="$SIM_UDID" TESTS='testThemeSearchFiltersLocally'
# Broad-change fallback: three representative checks.
make agent-verify SIM_UDID="$SIM_UDID"
# Profile/runtime or broad integration qualification: retained 13-check selection.
make agent-verify SIM_UDID="$SIM_UDID" VERIFY_SUITE=qualification
# Explicit restoration for integrations affected by disabled services.
make agent-verify SIM_UDID="$SIM_UDID" SIMULATOR_MODE=stock TESTS='testThemeSearchFiltersLocally'
# Fast selection/shared-budget regression and saved-result verification, no simulator boot.
python3 scripts/check_simulator_selection.py
python3 .build/verification/simulator-test-speedup/run-20260927-114527/verify-results.py
```

The stock command illustrates a local-search comparison; choose the actual affected integration's test when relevant. Unknown selectors must not pass. Lifecycle/mode acceptance scripts remain `scripts/check_simulator_lifecycle.py` and `scripts/check_simulator_modes.py`; use their explicit owned-device guards and fresh evidence, including an independently owned bounded sentinel when checking isolation. Repeat memory scripts/methodology are retained in the rollout evidence; do not overwrite earlier samples.

### Confirmed owned-resource closeout

| Owned simulator | UUID | Final state |
| --- | --- | --- |
| Mural Lifecycle Verification | `C094F154-7674-4A17-9F6B-319959B1F49A` | Shutdown |
| Mural Lifecycle Control | `0118BF91-AD6C-4C1B-A998-3659E3A594FD` | Shutdown |
| Mural Lifecycle Runtime Refusal | `CFFB4C0B-0560-43B2-B8E5-BA74EAD45F4C` | Shutdown; never booted by this rollout |

Cleanup is **PASS**. Retained simulator installations/data are intentional; shutdown is not erase/uninstall. No owned mirror/recorder/process group remains running. A Simulator application window is not proof of a booted device and is not globally closed.

### Limits and forced-kill recovery

- Evidence reuse requires unchanged relevant production/test/fixture/build/runtime/profile inputs. Earlier qualification lacks the newer per-file manifest; its original revision/runtime/profile evidence is not a claim of byte-identical historical inputs. New harness behavior was verified separately.
- Native microphone, model assets/inference, speech output, native background/drain and durable production conversation creation require separate supported physical acceptance. No phone tests were inferred from preview UI.
- The profile is qualified only on the stated runtime. Use stock for affected disabled integrations; neither missing SimSlim nor unknown versions silently bypass setup. Cold builds/host load can exhaust the routine budget and must fail without weakening assertions.
- Ordinary failure/timeout/cancellation runs finalize and shut down. SIGKILL, host failure or unavailable simulator services can prevent confirmation: retain evidence and report failure, never claim guaranteed cleanup under those conditions.
- Recovery: inspect `session.json`, `command-process.json` and helper ownership records; verify PID/PGID, command/start identity and exact-UDID lock ownership against current processes before signalling anything. Never reclaim stale-looking PIDs automatically. Once ownership is established and surviving owned work/captures are stopped, run `xcrun simctl shutdown <that-owned-UUID>` and confirm Shutdown in `xcrun simctl list devices -j`; save the recovery result. No global shutdown/kill, erase, delete, uninstall, cache/model removal or physical-phone operation.
