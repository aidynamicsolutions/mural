# Simulator test speedup plan

## Goal and relationship to the rollout

Run the smallest simulator acceptance selection that proves the affected behavior. Target **4-6 minutes** for routine verification and require **at most 10 minutes including incremental build, setup, tests, evidence finalization and confirmed shutdown** for the measured acceptance runs. Preserve broader coverage separately; do not claim identical coverage became faster.

The user authorized implementation and measurement of this plan before resuming Stage 6 of [the simulator lifecycle rollout](simulator-verification-lifecycle-plan.md). This plan has passed; the lifecycle rollout was then resumed and its final handoff completed. No commits, pushes, physical iPhone operations, other-project simulator mutations, cache cleaning or new test framework.

## Progress tracker

| Stage | Status | Completion evidence |
| --- | --- | --- |
| 1. Baseline, selection and failure analysis | complete | Saved qualification xcresults: 13 checks, zero skipped, 894.173 seconds test-action window. Existing selectors/helpers reviewed; failure cases below defined before implementation. |
| 2. Implement selection and bounded timing | complete | Selection/shared-budget checks pass. Native 180-second per-test timeout, bounded destination lookup, live stage markers and no automatic verbose diagnostics added; installed CLI options and shell syntax checked. Real execution follows in Stage 3. |
| 3. Measure and verify | complete | Smoke PASS at 262.75s / 274.73s; corrected focused-recording path PASS at 266.58s. Exact counts/zero skips, strict full-frame decode, cleanup PASS/Shutdown. `verify-results.py` reproduces aggregate PASS; input-reuse boundaries recorded. |
| 4. Document and resume rollout | complete | Measured results/limits and repeatable evidence saved; verification instructions updated. Lifecycle Stage 6 resumed and completed, with all owned simulators/helpers stopped and unrelated/staged work preserved. |

## Baseline

Evidence: `.build/verification/simulator-lifecycle/rollout-20260927-085406/ui-wallpaper-1/`.

- `supported-ui-summary.json`: 12 passed, zero failed/skipped.
- `settings-transition-summary.json`: one passed, zero failed/skipped.
- First test action start to last action finish: **14m54.173s**. This excludes the earlier build/profile setup and later cleanup, so it is not a measured old whole-command duration.
- `test-timings.json` and `transition-timings.json` show expensive unrelated combinations: recognizer/language guards about 106s, two voice checks about 196s combined, synthetic cancel/drain about 94s, dropdown transitions about 95s.
- Proposed smoke test bodies total **167.432s** in those saved results. The 4-6 minute end-to-end estimate is a target until measured, not a promise derived from adding test durations.

## Selection policy

1. **Known affected feature:** `TESTS='testMethod ...'` replaces the default. No mandatory smoke run before a focused check. Choose the smallest sufficient set, not the easiest passing scenario.
2. **Broad change or unclear scope:** `VERIFY_SUITE=smoke` (default), reusing:
   - `testOnboardingChoosesLearningAndSubtitleLanguagesWithoutAnAccount`
   - `testMeaningLabelWorksAfterEndingAndManualResetKeepsHistory`
   - `testOnDeviceVoiceSelectionPersists`
3. **Profile/runtime or broad integration qualification:** `VERIFY_SUITE=qualification` retains the existing 13-check selection unchanged, including recorded Settings transitions. Relevant exhaustive combinations, reboot-retention and lifecycle fault injection remain separately runnable when their semantics change. Qualification may exceed ten minutes and is not the routine default.

Preview History is not durable conversation storage. The voice check proves preference retention across app relaunch, not speech output. Normal-installation reboot checks remain necessary for affected persistence changes. No selection proves real microphone/model/native-background execution.

## Apply the other project's lessons

- **Test distinct behaviors, not repeated gestures.** Changing a selection, reselecting it, retaining it across relaunch, and recovering from no search results are different assertions. The same query under different filters can also test a different semantic rule. Do not remove such cases just because taps/text repeat.
- **Keep data matrices out of slow UI automation.** When data/filter semantics change, cover exhaustive combinations with assertions against the real production implementation plus representative UI integration. Enumerate failures and write any necessary isolated checks before implementation; do not duplicate the algorithm in a test. No data-matrix migration is needed for this tooling-only change, and existing UI assertions are not deleted.
- Separate representative user journeys from exhaustive matrices; do not delete or weaken assertions.
- Select by the changed behavior: layout/animation, search, consent, setup/drain, or persistence. Do not automatically run overlapping smoke, feature and qualification suites.
- Existing scrolling stops at a hittable target; retain it. Fix fixed-count scrolling only if encountered in an affected path.
- Keep meaningful UI/keyboard/sheet/drain waits and cold-runner readiness. Do not disable animations or shorten waits blindly.
- Reuse locked incremental DerivedData, one serial XCTest invocation where possible, and no unnecessary mirror. Do not clean caches or create parallel simulator workers.
- Coordinate heavy simulator work across projects. Read-only observation is allowed; locks on different devices do not prevent host contention. Report/defer an observed competing job rather than stop its simulator. No new scheduler/control plane.
- **Fail fast and expose progress.** Retain live xcbeautify output/raw logs and add native XCTest timeout enforcement, with a 180-second per-test allowance, above the slowest selected baseline (106 seconds). Bound destination lookup. Disable automatic verbose sysdiagnose collection that can prolong a failed run; retain xcresult, screenshots and raw failure logs. The existing shared routine deadline still covers startup/build stalls. Stop the measurement sequence on the first failing invocation, inspect that test/stage, and never retry blindly or wait for the qualification ceiling to diagnose a visible stall. No custom log-watcher or scheduler.
- Record selected coverage and timings honestly, including incremental build, startup and cleanup. Scope reduction is not an identical-coverage speedup. Mural's independently qualified SimSlim profile is unchanged; memory savings are not attributed as test-speed savings.
- **Reuse evidence only while relevant inputs are unchanged.** Check revision/dirty changes, affected production/test/fixture code, build configuration, runtime/Xcode, SimSlim version/profile and the exercised settings/path. Reuse prior qualification only for unchanged behavior; it cannot prove newly added selection, deadlines or progress handling. New smoke/focused runs validate the changed entrypoint. Save current input hashes/toolchain/configuration beside the measurements; repeat affected acceptance if an input changes.

## Budget and evidence

Routine jobs share one 600-second acceptance budget across preparation and runtime. Stop active build/setup/test work early enough to reserve 180 seconds for cleanup; do not give each phase a fresh ten minutes. Broader qualification has a separate documented bound. Cold builds that exhaust the budget fail rather than test stale artifacts.

Cleanup retains its own existing safety bounds. Never kill cleanup to manufacture a sub-ten-minute result. A timeout, cleanup failure, host stall or total duration above budget is a failed timing acceptance, even if some UI assertions passed. SIGKILL/host failure remains an explicitly documented manual-recovery limitation.

Save fresh evidence under `.build/verification/simulator-test-speedup/<unique-run>/`: exact selection, revision/dirty state, monotonic command/phase timings, raw formatted build/test logs, compact xcresult summaries, recorder/decode artifacts when selected, cleanup result, and exact owned device Shutdown. Preserve failed attempts. Compare the new xcresult test-action window to the old test-action window separately from new whole-command time.

## Failure cases defined before implementation

- Invalid suite, malformed/whitespace-only/duplicate selectors silently select a broader suite or pass without testing.
- Focused selection appends smoke checks instead of replacing them; qualification loses a selector.
- Missing, skipped, wrong-device or failed tests count as acceptance.
- Build and runtime each reset the budget, or an exhausted build budget still boots a simulator.
- Timeout/cancellation skips finalization, releases the build lock too early, loses the original failure, or reports a fast pass.
- Timing excludes build/setup/cleanup, evidence is overwritten, or a partial qualification is represented as equivalent coverage.
- Recorder startup/readiness is removed, movies fail to decode, or helpers/owned devices remain running.
- Another project's workload is stopped, the phone is targeted, or unrelated/staged changes are modified.
- A test stalls or verbose automatic diagnostics consume the whole qualification ceiling without a useful bounded failure; progress is hidden or failures trigger automatic repeated suites.
- Old evidence is reused after relevant source/fixture/configuration/runtime/profile changes, or newly changed harness behavior is attributed to an older pass.

Use a small pre-implementation isolated check only for selector/budget dispatch boundaries that are impractical to prove by repeatedly waiting ten minutes. Real Make/XCTest runs remain primary acceptance. Existing real lifecycle failure-path evidence remains applicable unless its behavior changes.

## Acceptance

- Two consecutive default smoke runs pass exactly three checks, zero skips, each under ten minutes through shutdown.
- A focused recorded transition runs only its requested test, passes, produces a decodable movie and confirms shutdown under ten minutes.
- Compare matching test-action windows; seek at least 2x reduction, targeting 2.5-3.7x for routine coverage. Report the smaller selected scope prominently.
- Qualification still selects the same 13 checks; no rerun of the already-passing full qualification solely to time the narrower default.
- Invalid selection and shared-budget failure paths fail closed. Existing ownership/profile/stock/cleanup guarantees remain intact.
- Exact starting index and unrelated physical plan are preserved. Every rollout-owned simulator/helper is stopped before handoff.

## Implementation log

### Stage 1 complete; Stage 2 started

- Saved this plan before speedup implementation, incorporating the user's smallest-sufficient-check guidance and ten-minute routine goal.
- Re-read the Make driver, Xcode shell, lifecycle owner, unchanged bounded recorder and feature guidance. Existing waits/target-driven scrolling will not be altered.
- Confirmed original staged patch remains byte-identical. Lifecycle rollout's default-profile lifecycle checks (13 groups) and mode checks (12 groups) already passed and ended Shutdown; no reason to replay the full suite for selection-only changes.
- Next: write selection/budget checks before implementation, add minimal dispatch/timing changes, then measure real smoke/focused runs.

### Stage 2 complete

- Evidence root: `.build/verification/simulator-test-speedup/run-20260927-114527/`.
- Wrote `scripts/check_simulator_selection.py` before implementation. `selection-before.log` fails because selection dispatch does not yet exist. The final script proves unchanged qualification membership, focused replacement, invalid selectors, shared build/runtime deadline, no runtime after build failure/exhaustion, retained timeout/cancellation/failure statuses, slow-cleanup overrun failure and a separate qualification budget. It fakes only expensive dispatch/clock boundaries; these are not UI or actual shutdown claims.
- Moved selection into the existing Make driver. Added `VERIFY_SUITE=smoke|qualification`; `TESTS` replaces either selection. Kept all 13 qualification methods and existing XCTest assertions, waits and target-driven scrolling unchanged. No production Swift edits or new dependencies.
- Added `make-action.json` coverage and `timings.json` preparation/build/lifecycle/total duration. Routine jobs share 420 seconds of active work with 180 seconds reserved for cleanup, against a 600-second total acceptance budget. Qualification uses 2400 seconds; standalone compilation retains its 900-second bound. Lifecycle evidence now records setup/command/cleanup durations without changing ownership or cleanup behavior.
- First real Make preflight check found that Make normalizes `TESTS='  '` to an empty string. Recorded the failure in `empty-selection.log`, then added the empty-string regression before its fix (`empty-selection-before.log`). Stopped exporting undefined TESTS: native Make export behavior now distinguishes omission from an explicitly empty selection. Both empty and whitespace-only selections fail before device lookup/build instead of silently broadening scope.
- `selection-final.log`: all 12 isolated cases PASS. `invalid-suite-final.log`, `duplicate-selection-final.log`, `empty-selection-final.log`: real Make refusals PASS before lookup/build. Python/shell syntax, local Markdown links and `git diff --check` PASS. Updated AGENTS and verification feature guidance to prefer affected checks without a mandatory preceding smoke run.

### Stage 3 blocked: competing project workload

- Read-only process inspection observed StrengthLogger's active `xcodebuild` PID **50088**, scheme **StrengthLoggerUX**, running `testOfflineExerciseDiscoveryFiltersSelectionAndWorkout` on its own simulator `A5015D6F-AFB0-4864-9E3E-86FEE9A74E72`. It was still active after code/docs validation (elapsed 16m32s at the final observation). See `competing-job.txt` and host-workload snapshots.
- Did not signal that process, change that simulator, or start competing Mural tests. Different device locks would not isolate shared XCTest services/host load. Stop here rather than produce misleading uncontended timings or weaken acceptance.
- `pre-measurement-closeout.json`: all three rollout-owned simulators confirmed Shutdown; exact original index and unrelated physical plan preserved. `owned-mirror-state.json`: trial mirror stopped. No speedup runtime runs, phone operations, commits or pushes.
- **No measured speedup claimed yet.** Stage 4 and lifecycle Stage 6 remain paused until the real measurements below pass.

### Resumed with additional lessons

- User confirmed the competing job finished. Read-only checks agree: no active xcodebuild/xctest/SimSlim process and no booted simulator. No other project's resources were targeted.
- Incorporated distinct-behavior coverage, production-code data-matrix boundaries, no automatic overlapping suites, native per-test stall limits/live progress, and explicit evidence-reuse gates before further implementation.
- Current revision remains `45caaf3d35b1459cdccceffcb1c94b19ffc97dc5`; original staged patch and unrelated physical plan remain byte-identical. Xcode 27.0 build 27A5252f and SimSlim 0.11.0 match the earlier qualification.
- Reviewed installed `xcodebuild -help` (saved in evidence) for native destination/per-test timeout and diagnostic-collection flags. Implemented those native bounds and stage markers in the existing shell, with no custom watchdog or Swift changes. Existing twelve selection/deadline checks still pass (`selection-resumed.log`). No UI waits, assertions or fixtures weakened. Same-selection repeats are required only here to establish repeatability, not automatically for future feature changes.
- Saved `inputs-before-measurement.json` (213 relevant current file hashes plus revision/toolchain/CLI), resumed dirty state/patch, and an empty active-job snapshot. Earlier qualification has revision/profile/runtime evidence but no equivalent per-file manifest; do not claim historical byte-for-byte identity. Production app code/configuration is unchanged, and original qualification test bodies/service selection remain applicable; fresh runs establish the changed entrypoint's behavior.

### Stage 3 measurement: smoke 1

- `smoke-1/`: default Make invocation passed exactly three tests with zero failures/skips on the owned trial. Native timeout/destination/diagnostic flags were accepted by Xcode. No automatic retry or overlapping suite ran.
- External `/usr/bin/time`: **262.75s (4m22.75s)** including build, setup and confirmed shutdown. Driver timing: 262.662s; build 12.343s, profile setup 13.487s, command 231.292s, cleanup 4.050s (ownership/process overhead accounts for the remaining time).
- Matching xcresult test-action span: **212.764s**, versus historical qualification 894.173s. Different scope: three representative checks instead of 13. Do not call this an identical-coverage acceleration. Repeat remains required before final reporting.
- Cleanup PASS/Shutdown, no competing build/test/profile process observed before the next run. No phone operations or other-project mutations.

### Stage 3 measurement: smoke 2

- `smoke-2/`: same three distinct-behavior tests PASS, zero failures/skips, no retry. External whole-command **274.73s (4m34.73s)**; xcresult test-action span **220.672s**. Cleanup PASS/Shutdown.
- Two-run whole-command median is **268.74s (4m28.74s)**. Both meet the 4-6 minute target and ten-minute ceiling. Matching test-action spans are approximately 4.20x / 4.05x shorter than the historical 13-check qualification, because scope is narrower. Selected test bodies themselves did not become faster; final comparison will report that separately.
- Next: only the focused recorded transition, not another overlapping qualification run.

### Stage 3 artifact audit: strict source decode correction

- `focused-transition/` passed exactly one UI test in 182.04s through shutdown; movie duration 138.433333s. Viewed the overview and 64-65s native menu dismissal at 30 fps after Shutdown.
- Aggregate acceptance initially failed because the old `ffmpeg -f null` check returned zero while logging non-monotonic output-mux timestamps (`video-decode.log`). Preserved this attempt; it is not an app-test failure. Adding `-xerror` or preserving the demux timebase did not remove those null-output messages, so neither attempt is counted as a fix.
- Source inspection shows a variable-frame-rate HEVC recording with timebase 1/600, 3692 packets, monotonically increasing source DTS and nondecreasing decoded PTS. Direct strict source decoding (`ffprobe -err_detect explode -count_frames`) decoded **3692/3692 frames**, no errors. This avoids the unnecessary output encoder/muxer without rewriting or dropping source frames.
- Failure cases before the correction: accept a partial/corrupt recording because FFmpeg returns zero; reject valid variable-rate capture due to null-output timestamp conversion; accept zero frames/nonpositive duration; disturb non-recorded runs. Add a runnable valid/empty/truncated/no-recorder check before replacing the finalizer's decode command with strict source frame-count validation (empty error log, positive duration, exact expected frame count).
- Replaced the recorded branch with strict direct source decoding: positive duration, exact decoded/expected frame counts, and empty decoder-error log. `check-video-finalizer.py` was written before the correction: its before run fails for missing source-frame proof; its after run passes valid variable-rate, empty, truncated and no-recorder cases. Corrupt/empty artifacts fail closed; no-recorder behavior is unchanged. No simulator operations were needed for those artifact checks.
- Rechecked historical stock and candidate qualification movies offline through the stronger finalizer: **2998/2998** and **3735/3735** frames decoded, no errors. Original movies/logs remain intact. No profile/UI qualification rerun needed for this output-mux correction.
- The finalizer's recorded branch is the only behavior changed. Reuse the two smoke timings because neither starts a recorder nor enters that branch; rerun only the focused recorded path after the fix. `inputs-finalizer-fix.json` and `video-finalizer-change.patch` preserve exactly that one-file difference from the original input manifest. No production/UI/test/profile inputs changed.

### Stage 3 complete: measured acceptance

- Corrected finalizer path rerun: `focused-transition-final/`, exactly one UI check PASS, zero failures/skips. **266.58s (4m26.58s)** whole command including build, setup and confirmed Shutdown. The longer startup/finalization versus the initial 182.04s attempt is retained and reported, not hidden.
- New movie: 181.1 seconds, **3782/3782 frames decoded**, empty error log. Viewed the new overview after Shutdown; prior dense transition inspection remains applicable to unchanged UI/test/capture behavior and its original movie also passed strict source decoding. See `visual-inspection.md`.
- Repeatable saved-evidence check: `python3 .build/verification/simulator-test-speedup/run-20260927-114527/verify-results.py` produces `comparison.json` with PASS. It verifies all three accepted run selections/counts/devices/budgets/cleanup results, strict recording proof, current input hashes and the narrowly justified reuse of smoke after a recorded-only finalizer change. It does not boot devices or rerun tests.
- Smoke whole-command median: **268.74s (4m28.74s)**. All accepted runs meet 4-6 minutes and the ten-minute ceiling.
- Like-boundary comparison: historical 13-check test-action window **894.173s** versus three-check median **216.718s**, a **4.13x / 75.8% reduction**. This is scope reduction, not identical-coverage acceleration. The same three test bodies were 167.432s historically versus 180.616s now; they did not get faster. No old whole-command measurement exists, so no whole-command percentage is claimed.
- `final-closeout.json`: all three rollout-owned devices Shutdown, all four new command groups gone, all four earlier detached mirror PIDs absent, trial mirror stopped, original index and unrelated physical plan preserved. No phone operations or other-project mutations.
- Stage 4 begins: update final policy/handoff and resume the lifecycle plan without repeating unaffected qualification/memory matrices.

### Stage 4 complete: handoff resumed and finished

- Published `result.md`, `comparison.json`, `visual-inspection.md`, current input manifests, preserved failed attempts, repeatable result/finalizer checks and final closeout under the speedup evidence root.
- Updated agent/verification guidance with focused-first selection, distinct-behavior coverage, production-code matrix boundaries, bounded native progress/failure behavior, honest timing and evidence-reuse rules. The movie finalizer uses complete source decoding rather than an unnecessary output transcode.
- Resumed and completed lifecycle Stage 6: promoted-profile/memory evidence remains unchanged, final commands/recovery limits are documented, and all owned resources are confirmed stopped. No phone action, commit or push; exact original index and unrelated physical plan preserved.
- No further full qualification, memory matrix or smoke reruns were needed after the recorded-only finalizer fix. Stop with passing evidence rather than adding overlapping coverage.

## Repeat commands and required results

Observe workload state read-only and run from the repository root. Do not stop other projects' jobs to create an idle host. Reuse only the recorded Mural trial, initially Shutdown:

```sh
python3 scripts/check_simulator_selection.py
SIM_UDID=C094F154-7674-4A17-9F6B-319959B1F49A
E="$PWD/.build/verification/simulator-test-speedup/repeat-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$E"
set -o pipefail
for attempt in 1 2; do
  /usr/bin/time -p make agent-verify SIM_UDID="$SIM_UDID" \
    EVIDENCE="$E/smoke-$attempt" 2>&1 | tee "$E/smoke-$attempt-command.log" || exit $?
done
# Run this only after both smoke attempts pass, including cleanup.
/usr/bin/time -p make agent-verify SIM_UDID="$SIM_UDID" \
  TESTS='testSettingsDropdownTransitions' EVIDENCE="$E/focused-transition" \
  2>&1 | tee "$E/focused-transition-command.log"
```

Use fresh child names if any attempt already exists; never overwrite failed evidence. For each smoke attempt require `supported-ui-summary.json` with three passed/zero failed/zero skipped on the exact UUID, `timings.json` under 600 seconds, and `cleanup.json` PASS/Shutdown. For the focused run require only one test, the same timing/cleanup checks, positive-duration/full-decode movie evidence, and inspect the saved transition after shutdown. Save an aggregate result comparing each new xcresult start/finish span with the old 894.173-second test-action span; report whole-command times separately. If any acceptance fails, record it and stop rather than expanding the budget or dropping a required check. Once all pass, complete this tracker and resume lifecycle Stage 6.
