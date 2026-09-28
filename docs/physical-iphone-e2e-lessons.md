# Physical iPhone E2E: lessons and optimization backlog

## Status and source of truth

The native physical workflow is qualified within the limits recorded in the [implementation plan](physical-iphone-e2e-plan.md). The [verification skill](../.agents/skills/verify-mural/SKILL.md#qualified-opt-in-native-local-workflow) owns runnable commands, stage selection and safety gates; [AGENTS.md](../AGENTS.md) owns mandatory policy. This document records lessons and future work, not a second runner specification.

Both optimization rounds are implemented and physically qualified. The first matched two-turn/persistence comparison fell from 221.25 s to 159.02 / 157.55 s including cleanup, about 28% shorter. The four follow-up priorities plus the checklist correction subsequently measured 155.96 / 152.56 s, about 2.5% lower again, but with added checklist sampling/screen evidence and changed production code, not identical instrumentation. All original scenario assertions remain. The user separately confirmed both iPhone replies in both final runs of each round. Physical checks remain explicitly opt-in. No room audio was recorded.

The iPhone is the closest source of truth for the actual microphone, recognition, tutor, speech and native lifecycle paths. That does not make every phone test comprehensive: automated TTS events are not listening evidence, and recording cancellation is not background or inference cancellation. Simulator UI checks remain useful and do not need to be duplicated when the phone scenario already proves the affected behavior.

## Measured baseline

Qualified environment: paired iPhone 17, iOS 27.2, Xcode 27, signed Core AI Release, retained recognition and Supertonic3 assets/caches. Mac-generated Samantha speech at rate 150 traveled through the speakers and real phone microphone. No injected transcript or fake model reply.

Evidence paths below are relative to `.build/verification/physical-iphone-e2e/`:

| Scenario | Evidence directory | Runtime command including cleanup |
| --- | --- | ---: |
| Two turns and exact transcript after relaunch | `20260927-213906-2903` | 207.3 s |
| Fresh identical repeat, retained caches | `20260927-214250-12298` | 214.5 s |
| End during recording, drain, distinct new conversation | `20260927-215132-33287` | 163.3 s |
| Model-free nested-sheet/settings recovery | `20260927-213804-99776` | Not used as a timing baseline |

The first two runs averaged 210.9 seconds, roughly 3m31s. These are two observations, not a stable performance distribution. Separate signed preparation/build time is **excluded**, so do not call these full build-to-closeout timings. Human waiting/listening time is also not characterized by these numbers. Closeout: `qualification-20260927/result.md`; each run retains its own result/cleanup and applicable human confirmation.

Both full runs passed native assertions with zero failures/skips and cleanup PASS. The user separately confirmed both phone replies audible in each run. Cancellation passed its narrower recording/recovery assertions. No cold-cache, sustained thermal, accent-wide or teaching-quality benchmark was performed.

Much of the long qualification session was harness diagnosis and human handoffs, not repeated measurements of steady-state inference. Avoid claiming a percentage speedup from removing that one-time work.

## Matched runtime optimization result

One fresh instrumentation-only baseline and two optimized runs used the same app executable, phone/runtime/backend, frozen fixtures, normalization, retained caches, user-confirmed placement and scenario/assertions. All used MacBook Pro built-in speakers at unchanged user-controlled volume 56, unmuted. Test/host source differs intentionally for instrumentation/optimization and is identified by each receipt/session. No model/cache resets or production app changes were made.

| Scenario | Evidence directory | Runtime through cleanup | Automated result |
| --- | --- | ---: | --- |
| Fresh baseline: two turns + exact relaunch persistence | `20260927-225903-58902` | 221.25 s | PASS |
| Optimized same scenario | `20260927-231126-90382` | 159.02 s | PASS |
| Fresh optimized repeat | `20260927-231413-97363` | 157.55 s | PASS |
| Optimized single acoustic qualification | `20260927-230906-84796` | 105.48 s | PASS, narrower scope |
| Optimized recording cancellation/recovery | `20260927-231701-4101` | 126.84 s | PASS, distinct scope |

Optimized two-turn mean: 158.28 s, saving 62.96 s (28.5%) versus the fresh baseline. This is one baseline and two optimized observations, not a statistical latency distribution or an inference speed claim. No percentage comparison uses the narrower acoustic/cancellation scenarios. Exact learner/assistant text, counts and order remain asserted after relaunch; all final runs have one passing native test, zero failures/skips and cleanup PASS.

The two native capture waits totaled 24.18 s before, versus 10.40 / 9.46 s after. UI setup before Prepare fell from 17.18 s to 10.43 / 10.90 s; transcript verification and persistence also shortened. Send-to-Ready remained roughly 33-35 s combined. Overall savings also include variation in preparation and unattributed XCTest startup/finalization, so do not attribute every saved second to the code changes. Host phases partition total time; native intervals overlap the native-test host phase.

Separate preparation commands took 19.59 s for the instrumented baseline and 16.39 s for the final optimized test build. Adding those builds to the first respective runtime gives 240.84 s and 175.41 s; this is not a controlled build-speed comparison. Intermediate development/recovery checks and human waiting are excluded. Repeated runtime uses the matching saved preparation, not another build.

Final closeout artifact: `runtime-optimization-20260927/result.md`. Real-model/native acoustic acceptance is automated. Audible speaker output for both final optimized two-turn runs is **human-confirmed**; no room capture, teaching-quality, sustained thermal or broad background-lifecycle claim. The user did not separately answer the late-speech/audio-issue/heat questions in this confirmation. The earlier human-confirmed qualification remains separately recorded above.

## Failures converted into operating rules

| Observed failure / friction | Cause or finding | Prevention / retained limit |
| --- | --- | --- |
| Signed runner could not install under free-profile app limit | Runner needs its own identity/profile and available slot | Keep main app and runner identifiers separate. Stop on missing slot; delete another app only with explicit authorization. QA deletion was a one-time approval. |
| Discovery said disconnected despite working wired requests | Discovery tunnel state was not sufficient readiness evidence | Use bounded direct device status/control checks; do not infer success from discovery either. |
| Syslog showed only connected, no app events | That capture path did not provide evidence on this runtime | Use qualified app-scoped `devicectl --console` launch and require fresh backend events. No device-wide archive fallback. |
| Duplicate backend events rejected a valid process | Event-line count was mistaken for distinct process count | Correlate distinct PID and current run/turn; duplicates within one PID are not another app. |
| Incremental build had no compiler invocation | Compiler proof gate ignored valid unchanged executable | Reuse original compiler evidence only for identical executable bytes. Never touch source timestamps or clear caches to force compilation. |
| Host reporting edits forced unnecessary preparation | Compiled-input and host-script identity were conflated | Track host hash separately; reuse preparation only when device, compiled inputs and artifacts match. |
| Meaning-language assumption was wrong | Real user preference differed from the planned fixture | Snapshot actual UI preference and restore it. Never reset personal settings/history. |
| Permission popup outlasted short capture wait | Protected approval remained a human gate | Bounded permission/readiness wait; play only after fresh capture and UI gates. Never auto-approve or emit speech into an unready recording. |
| Correct recognition failed on `3` versus `three` | Text oracle was stricter than the user's accepted meaning | Preserve the failed attempt; subsequent runs predeclare only the accepted numeric-token equivalence plus case/punctuation/whitespace. Preserve raw text. |
| Input selector found no text view | Production control was a multiline text field | Query actual accessibility type, not visual appearance. |
| End button or transcript counts/dismissals failed | One-way scrolling and queries including underlying/nested sheets | Scroll toward targets; scope transcript contents and Done buttons to their specific containers. Qualify cleanup repairs without models first. |
| Repeated requests to close an already idle app | Ownership/status handling was ad hoc | Use saved status and exact-PID `stop-idle` only after idle confirmation and installed-executable verification under lock. Never stop unknown/personal work. |
| Repeated inline Python and Make troubleshooting | Operational knowledge was not retained in entrypoints | Use saved `verify_device.py`, Make stages and report command. Repair recurring defects there, preserving failure evidence, rather than rebuilding one-off wrappers. |
| Playback acknowledgment probe rejected a three-second tool timeout | `devicectl` requires at least five seconds | Use its five-second timeout inside a six-second owned host bound. Failed model-free probe `20260927-230721-80896` retains unconfirmed cleanup; direct status found no surviving Mural processes and separate recovery `20260927-230817-83126` passed. |
| Preparation risked phone Auto-Lock | Foreground setup could be long | Temporary app preparation-only idle-timer hold restores prior value. Acquire/restore was observed; long-duration lock prevention is not separately qualified. Never change security policy. |
| Existing decoder receipt repeatedly became incompatible | In-place installation moved the data-container UUID; only the absolute model-path hash changed | Policy 2 hashes canonical sandbox-relative location; outside paths stay absolute. Keep manifest/device/OS/compute checks and actual validated loading. A receipt hit does not guarantee a fast native load. |
| Completed setup checkmarks reset just before the greeting | Setup ownership ended while the UI remained `.preparing` across suspended speech synthesis | Exit preparation synchronously before synthesis. Require monotonic native checklist observations and inspect retained XCTest video through the transition, not just Ready. |

A repaired harness failure is not a passing original run. Keep failed artifacts and separate recovery results. Model/resource failures and unsafe thermal conditions stop the session without automatic retry or backend changes.

## Already implemented, not new speedup claims

- Opt-in Make entrypoints backed by one bounded host runner and native XCUITest.
- Safe signed preparation before the audible window; matching preparation receipts and unchanged-executable compiler proof reuse.
- Frozen speech fixtures, fresh current-turn playback gates and scoped app logs.
- Saved status, exact idle-PID stop, settings recovery and compact result reporting.
- Model-free recovery regression for diagnostics scrolling and nested transcript/history dismissal.
- Owned-process cleanup, original preference restoration and separate automated/human evidence.

The documentation now makes stage selection explicit: `acoustic` for one real input turn, `multi` for conversation/persistence, `cancel` for recording cancellation. The typed baseline and fresh full repeat belong to applicable qualification, not every routine check. Narrowing scope saves work but is not faster identical coverage.

## Recommended implementation order

### 1. Policy, routing and reusable lessons - complete

Updated AGENTS, the verification skill, feature map and plan links. Safe preparation precedes a consolidated readiness request. Routine runs choose the affected scenario; initial or changed-contract qualification retains baseline, acoustic gate and multi-turn ordering.

### 2. Remove redundant accessibility work - implemented and qualified

Physical `reveal` returns when its target is hittable; the Settings loop breaks immediately. Previously `for ... where` reevaluated the remote accessibility predicate through every remaining iteration even after finding the target. Limits, target-driven scrolling, scoped containers and all outcome assertions remain unchanged.

Model-free diagnostics/nested-sheet/settings regression `20260927-230400-72070` passed before further model work. Final acoustic, multi/repeat and cancellation runs qualified all affected physical callers. No simulator helper rewrite or duplicated unit suite.

### 3. Qualify playback-completion-driven capture - implemented and qualified

Replaced fixed 12-second recording sleeps with a fresh run/turn-specific random-token acknowledgment. XCTest emits its request after the Send-label gate. Host still requires the current native capture and UI marker before playback, then checks successful `afplay` completion within five seconds and no early Send. Only then does bounded `devicectl copy to` place the token in the **XCTest runner's temporary container**, never the production app container. Native XCTest accepts only its exact token within 12 seconds, retains a 0.75 s trailing margin, and removes the temporary receipt. Missing, wrong or late content cannot release Send; no automatic retry or network service.

Prewritten host checks cover missing/stale/wrong-turn/duplicate requests, invalid nonce, unfinished/failed/overlong playback and early Send. The model-free probe `20260927-230817-83126` qualified file transport and stale-content replacement before real acoustic qualification. Normal acoustic, two-turn/repeat and cancellation paths passed with nonzero frames and unchanged text/persistence assertions. These are representative failure checks, not physical fault injection of every possible file-transfer failure. Existing timeout/cleanup host checks remain passing.

Fixture duration alone is not a safe Send timer: the first file is about 1.97 seconds, but playback startup/completion varies. Preserve these completion gates and the qualified trailing margin; do not change speech speed or matching rules to manufacture a gain.

### 4. Add a focused phase breakdown - implemented and qualified

Keep existing whole-command totals and separately identify preparation/build, install/launch, XCTest startup, readiness, capture/playback, inference, persistence and cleanup where reliable markers exist. Record human handoff time separately when measured. Use monotonic durations within each clock domain; do not subtract host and device timestamps without demonstrated alignment.

Acceptance: totals reconcile or explicitly identify overlap/unattributed time. No new telemetry service, device-wide recording or private-content collection. This measurement must precede any claimed optimization result.

Implemented first, before optimization: host monotonic phases partition preflight, build/artifact validation or install/launch/native-test/result validation, and cleanup. Native uptime markers separately measure UI setup, preparation, capture window, Send-to-Ready, assertions, persistence and teardown; these intervals overlap the host native-test phase and are never added to its total. Existing per-turn playback receipts remain available. Native test-command time also includes XCTest startup/finalization; this initial instrumentation does not pretend to isolate those or all inference subphases.

Host checks cover nonmonotonic/duplicate boundaries, missing/incomplete native markers and separate clock domains. They were written and observed failing before implementation, then passed. Instrumentation-only preparation: `.build/verification/physical-iphone-e2e/20260927-223510-26248/`, build and cleanup PASS, 19.59 s overall (17.50 s signed build). App executable bytes are unchanged and retained compiler proof was reused. That preparation did not install, launch, use the microphone or play audio. The fresh baseline and optimized runs above subsequently qualified native markers; missing intervals on a failed/incomplete test remain incomplete evidence, not zero-duration phases.

### 5. Matched comparison and promotion - automated qualification complete

Compare before/after on the same device/runtime, backend, fixture bytes, placement, output route/volume, retained-cache policy and exact scenario/assertions. Record source/test/host hashes, build receipt, dirty state, thermal observations and host contention. Run serially in an approved audible window. Preserve failed attempts; a fresh comparison is not permission for retry-until-green.

Report build, runtime and cleanup separately plus the full measured total, matched sample count and variation. A shorter scenario is a scope reduction, not an implementation speedup. Promote only with unchanged recognition, real-response, persistence and cleanup evidence; audible output remains separately human-confirmed unless an explicitly approved recording protocol proves it. No target percentage is promised.

The observed matched result is recorded above. All requested runtime changes are implemented, automated acceptance passed, and both final optimized runs have explicit human listening confirmation. No additional runtime optimization is needed to close these implementation stages.

Skipping installation is deferred unless installed executable identity can be reliably proved. Matching version strings or a resident PID are insufficient. Never trade cache preservation, safety gates, meaningful waits or complete cleanup for timing.

## Four follow-up priorities and checklist correction - implemented and qualified

1. **Stable preparation receipt identity.** The prior implementation in commit `3a2734c` existed and worked within one sandbox, but hashed its absolute path. Read-only before/after receipt comparison proved that installation changed the data-container UUID and only `modelPathSHA256` differed. Policy 2 resolves symlinks, hashes the model's path relative to its own sandbox, and retains an absolute identity outside that boundary. Changed locations, manifests, model/scope, OS, device, compute units and policy still invalidate. Old receipts safely miss once; every hit still performs normal native load/contract validation after full asset verification. Prewritten relocation/boundary tests and the existing failure matrix passed. On the phone, receipt bytes stayed identical across another container relocation and successful real acoustic turn.
2. **One initial Settings visit.** Read/log the original preference before any mutation, then select the approved meaning language in that same visit. Teardown still restores and reopens Settings to verify. Model-free recovery and every real run passed. Initial UI setup measured 8.46 / 8.05 s, previously 10.43 / 10.90 s; only part of the whole-command change is attributable to this visit.
3. **One settled transcript snapshot.** A native snapshot scoped to Transcript supplies exact label counts and order, plus a retained hierarchy attachment. Real passage visibility/target-driven scrolling and normal disk-backed relaunch remain. Both full runs passed exact observed learner/assistant text/count/order; underlying Talk labels are still excluded.
4. **Prepared `.xctestrun` launch.** Runtime copies the fingerprinted prepared manifest into the run's evidence, resolves its original product root, preserves signed identities/settings and adds explicit stage/acknowledgment environment. It uses `xcodebuild -xctestrun ... test-without-building`, not project/scheme package resolution. Unexpected format/targets/identity fail closed; original prepared bytes remain untouched. Ownership, backend proof, exact non-skipped result count, native deadlines and cleanup remain. The same bounded Make target handles it; no new runner service or dependency.

**Checklist defect:** after setup finished, the coordinator still exposed `.preparing` while awaiting greeting synthesis, so the UI fell back to engine progress with empty completed stages. `speakLocal` now leaves that phase synchronously, before suspension. Actual Speaking still begins only on the playback callback, and Record remains disabled until ready. No stale-completed overlay hides genuine revalidation.

A pre-fix native test failed on checking/voice reverting in `20260927-233637-48547`; cleanup passed. Retained native XCTest video, without mirroring, showed the same bug. Corrected baseline `20260927-234817-79128` passed the new monotonic-checklist guard. Both full movies passed strict source decode and exact frame-count validation. Agent inspected dense 12 fps contact sheets at **40-42 s before / 43-45 s after**, plus the after 35-50 s overview through actual Speaking. Completed checks now remain checked until the card exits. This is physical transition evidence, not a settled screenshot claim. No typography/layout redesign or new large-text/background-lifecycle qualification is claimed.

### Follow-up acceptance and measurements

| Scenario | Evidence directory | Runtime including cleanup | Result |
| --- | --- | ---: | --- |
| Model-free single-visit selection, diagnostics, nested sheets and restoration | `20260927-234724-76844` | 46.26 s | PASS |
| Native readiness, checklist handoff and typed real reply | `20260927-234817-79128` | 101.24 s | PASS; one-time receipt migration |
| One actual acoustic turn after reinstall | `20260927-235040-84887` | 98.47 s | PASS; receipt hit, actual validated loading |
| Two distinct turns + exact transcript after relaunch | `20260927-235312-91141` | 155.96 s | PASS |
| Fresh same-scenario repeat | `20260927-235628-99584` | 152.56 s | PASS |
| End during recording, drain, distinct new conversation | `20260927-235929-7127` | 128.96 s | PASS |

All have zero failed/skipped native tests and cleanup PASS. Targeted receipt/setup checks: 26 passed. Host request/result/safety/timeout/prepared-plan checks passed. Separate signed preparation `20260927-234638-75017` took 40.64 s; it rebuilt changed production code, unlike the prior test-only build, so no build-speed comparison is claimed. Main bundle, Core AI Release flags, assets/caches, personal history and original Traditional Chinese preference were preserved; speaker volume remained user-controlled 56/unmuted. No simulator run or room recording.

Two-turn mean is **154.26 s**, versus the previous **158.28 s**: observed reduction **4.02 s / 2.54%**, not a guaranteed or isolated gain. Scenario coverage is retained and expanded with the checklist guard and retained screen video; production code also changed. Two samples per round do not establish a latency distribution. Native loading still cost **19.40 / 16.54 s** in the full runs despite correct receipt hits; cancellation's first load cost 25.17 s. The expensive work can occur inside mandatory loading, so a skipped prewarm is not equivalent to eliminated compilation. No model/asset/backend change, forced cache hit or automatic retry was used.

User separately confirmed **both iPhone replies in both new full runs**. Saved `human-acceptance.json` beside each run; no old listening confirmation was reused. No additional human heat/late-speech/teaching-quality claim. Closeout and comparison: `followup-20260927/result.md` and `timing-comparison.json` under the evidence root.

### Remaining opportunities, not implementation blockers

The four approved priorities are complete. Further substantial savings would require measuring why the first mandatory native load is still slow across installation, and whether a supported installed-artifact identity check can safely avoid unnecessary installation. Version strings and process presence are not sufficient identity proof. Do not remove load/asset checks, accelerate speech, skip persistence or shorten readiness/cleanup bounds to chase a target. No further optimization or hard runtime floor is established by these measurements.

## Next-run checklist

1. Read changed inputs and saved report; choose the narrowest scenario that proves the change.
2. Discover the exact phone, inspect bounded status, prepare signed artifacts and frozen fixtures while the phone may remain locked.
3. Confirm one private audible window and only missing human actions. Close mirroring; do not collect room audio without separate consent.
4. Run the selected native stage with actual capture/model gates. Stop at the first model/resource or unsafe thermal failure.
5. Inspect compact results, raw recognition/order evidence and cleanup. Save any necessary listening confirmation separately.
6. Restore settings and stop owned processes. Report PASS/FAIL/BLOCKED with scope and evidence; do not silently extrapolate to background execution or teaching quality.

## September 28: model-free Simplified pair and receipt cleanup race

The Simplified Talk extension adds only a model-free `pair-check` so far; the existing Vietnamese native qualification is not FireRed evidence. See the [current qualification plan](asr/chinese/simplified-talk-qualification-plan.md).

- `20260928-083618-32989` reproduced a completion-receipt race: XCTest consumed and immediately unlinked the exact nonce file, then devicectl's post-copy destination stat failed with file-node error 7000. The host aborted native teardown. Preserve that failed result/cleanup; no models or audio ran.
- Shared correction accepts only the exact destination-specific missing-node error with a fresh native ACK containing the exact run/index/nonce once. Other errors, missing/wrong/duplicate ACKs, timeout, unfinished playback and early Send still fail. Existing bounds and trailing audio margin are unchanged; no receipt sleep/retry or silent acceptance of failed playback. Prewritten host failure checks passed.
- Separate model-free recovery/qualification `20260928-083908-39499`: one native pass, zero failures/skips, cleanup PASS; **28.78 seconds through cleanup**. Traditional Chinese was restored from the failed run's original-preference record and independently read back. Settings/FireRed diagnostics/scrolling/transport were exercised without Prepare or history access. This run's copy returned normally; do not label it physical injection of the race branch.
- Signed test preparation was **14.01 seconds**, separate from runtime, using unchanged production executable/compiler proof. Screen movie exported and fully decoded; screenshot inspected. No audible-output, acoustic recognition, native FireRed or timing-speedup claim. All owned work stopped and no room audio recorded.
- Fresh `pair-check` `20260928-084236-47188` passed actual Traditional-to-Simplified selection and automatic original-preference restoration/readback without a recovery override, **36.48 seconds**, one test and cleanup PASS. Recovery had started already on Simplified, so this second model-free run proves a distinct required behavior, not an acoustic/model retry.
