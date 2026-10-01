# Physical iPhone E2E: lessons and optimization backlog

## Status and source of truth

The native physical workflow is qualified within the limits recorded in the [implementation plan](physical-iphone-e2e-plan.md). The [verification skill](../.agents/skills/verify-mural/SKILL.md#qualified-opt-in-native-local-workflow) owns runnable commands, stage selection and safety gates; [AGENTS.md](../AGENTS.md) owns mandatory policy. This document records lessons and future work, not a second runner specification.

Both optimization rounds are implemented and physically qualified. The first matched two-turn/persistence comparison fell from 221.25 s to 159.02 / 157.55 s including cleanup, about 28% shorter. The four follow-up priorities plus the checklist correction subsequently measured 155.96 / 152.56 s, about 2.5% lower again, but with added checklist sampling/screen evidence and changed production code, not identical instrumentation. All original scenario assertions remain. The user separately confirmed both iPhone replies in both final runs of each round. Physical checks remain explicitly opt-in. No room audio was recorded.

The iPhone is the closest source of truth for the actual microphone, recognition, tutor, speech and native lifecycle paths. That does not make every phone test comprehensive: automated TTS events are not listening evidence, and recording cancellation is not background or inference cancellation. Simulator UI checks remain useful and do not need to be duplicated when the phone scenario already proves the affected behavior.

## Breeze Simplified MVP closeout: user acceptance

The user confirms the installed ordinary build handles a live mixed Mandarin/English
turn with names/numbers, Simplified meanings/word lookup and several ordinary turns without
unexpected Pause/Resume. Separate closeout confirmation accepts on-screen Simplified Help,
audible English replies and no Chinese Help playback. Retained exact-UUID native reopen /
explicit edit / raw retention and fresh real OpenCC/persistence/boundary checks complement
that human evidence. The tested Simplified MVP PoC is accepted; do not manufacture another
acoustic run to replace valid user feedback or restart accepted warm-start investigation.

A fresh Traditional spoken session remains unverified. Failed prerecorded/support/profile
runs stay failed, and neither broad accuracy nor sustained memory/thermal safety is proved.
These are source/feature acceptance boundaries, not hidden passes. See the
[MVP closeout](asr/chinese/breeze-simplified-implementation-20260928.md#mvp-closeout-user-accepted-simplified-workflow).
Private closeout evidence: `.build/verification/breeze-simplified-closeout-20260930/`.

The optional profiler monitor had its Breeze check nested under the resource/provisioning
branch. Source review moved the shared premature-exit check to all profiler stages, without
interrupting an already-requested native drain. A focused host regression rejects early
exit 0/1, permits deliberate termination intent only, and retains final trace exit/cleanup
validation. This is not a new passing native profiler scenario or a latency optimization.

## Breeze warning UX follow-up: September 30

A UIKit notification is not itself a model failure. The ordinary observer called stop,
then the coordinator exposed Resume; retained native events show that transition within
about 20 ms. User live English smoke feedback was positive, but their subsequent Resume
report was not separately log-correlated. Normal Talk now keeps notification-only events
non-blocking and content-free logged, preserving actual sampled-ceiling/thermal/model stops.

Five distinct model-free UI requirements passed across focused runs; host fault checks
passed. Initial enabled-Record assertions were unsuitable for a fixture with no ASR model:
inspect the actual Ready/no-Resume screenshot and engine prerequisite before editing
production code or widening timeouts. Corrected checks retain notification/setup/turn
preservation and separate hard-stop/drain recovery requirements. Failed attempts remain saved.

The receipt is hitting and skipping prewarm. Breeze load/validation still took
161.432-172.361 s versus about one second for asset verification. Do not diagnose this
as a missing receipt, claim warm resident models, or disable loading validation.
Measure individual model loads before choosing a latency optimization.

Signed Core AI Release preparation took 30.00 s including cleanup; actual compiler,
converter/resources and strict identities passed. Initial idle confirmation timed out.
A later fresh authorized handoff installed the exact ordinary artifact in place, retaining
the existing runner. Model-free `breeze-finish` passed 1 test / 0 failures / 0 skips in
98.54 s through cleanup, with native dictionary and On-device / English / Simplified
Chinese readback. No ASR models/microphone were requested; updated native warning
continuation remains unverified, not PASS.
Evidence: `.build/verification/breeze-memory-warning-nonblocking-20260930/`.

### Separate Breeze model-load diagnosis

The existing production component fences establish encoder loading at 141-150 s,
decoder at 18-22 s, Mel at 0.064-0.066 s and remaining validation under 8 ms, across three
retained receipt-hit runs. The new host report retains complete and failed/incomplete
boundaries separately. This identifies the actual `MLModel.load` bottleneck, not a cache
miss or a new optimization gain. Core AI's Vietnamese GPU flag does not change Breeze's
CPU/Neural Engine configuration.

Repeated reinstallations change the sandbox's absolute model path; Apple's specialization
cache is path/configuration-sensitive. The sandbox-relative receipt does not own that cache.
Use the actual Core ML `cached` / `prepare and cache` trace label before diagnosing
recompilation or choosing compute changes. Keep manifest/native validation intact.

The preparation-only Core ML/Time Profiler stage remains blocked at model-free qualification.
App RPC availability did not imply Instruments readiness: initial exact-PID attachment failed
while Instruments listed the phone offline. A data-capable USB connection enabled capture.
The new native setup whitelist missed its stage and skipped; the required skip was caught,
retained and fixed. The corrected run then failed UI automation initialization before the
test body. Both saved preflight and later status show unlocked, so do not blame Auto-Lock
without intermediate evidence. No models were requested or automatically replayed. The
trace has the Core ML schema but no load events; it cannot classify the encoder cache.
Original cleanup failures stay failed. Exact-PID recovery where needed, finalized captures,
no remaining owned host processes and fresh empty phone inventories are recorded separately.

User follow-up closes the immediate startup investigation for the PoC: without reinstalling,
they ended the conversation, fully quit the app, reopened it and reached ready after
Prepare & start in approximately **five seconds**. This is human-reported whole-readiness
timing, not a matched automated comparison or a traced cache label. It strongly supports
the installation-related cold-load explanation; the user accepts slow first preparation
after reinstall as testing behavior. Do not repeat profiling or propose CPU/GPU/quantization
changes solely for that known post-install cost. Label cold and unchanged-install warm runs
separately, preserve readiness budgets/validation, and reopen only for a warm regression,
a relevant changed model/runtime/compute contract or explicit cold-start optimization.
The failed profiler qualification remains failed and deferred, not retroactively passed.
Avoid unnecessary reinstalls of identical artifacts only after identity/cleanup qualification;
never substitute model re-export, quantization, skipped validation or forced receipts.
Evidence: `.build/verification/breeze-load-profile-20260930/` and the
[feature checkpoint](asr/chinese/breeze-simplified-implementation-20260928.md#september-30-breeze-load-profile-encoder-bottleneck-confirmed-cache-cause-unconfirmed).

## Breeze Simplified display checkpoint: September 30

The [feature checkpoint](asr/chinese/breeze-simplified-implementation-20260928.md#local-qualification-checkpoint-september-30)
records host/OpenCC and model-free UI qualification, not acoustic acceptance. The ordinary
signed Core AI Release preparation took 56.77 s including cleanup (54.78 s signed build),
separate from runtime. Actual compiler flags, converter linkage, all dictionaries and notices
were verified; no ASR weights were fetched and no phone model was loaded by verification.

Incremental Xcode built the new MuralCore notice but initially retained the old bundle copy
inside the simulator app. Inspect actual embedded resources, not only package build outputs.
Preserve the failed run and invalidate only the proven stale build-product copy under the
canonical DerivedData lock; never repair this by touching sources or deleting device caches.
The simulator's four requested checks passed across bounded runs, retaining the combined
run's budget failure and the original resource failure separately.

The paired installer refused a newly reopened matching Mural process after the initial
exact-PID idle stop. Fresh idle confirmation timed out, so installation and native testing
remain pending. Keep status, exact-PID stop and installation adjacent after the handoff;
preserve a new process rather than assuming earlier idle authorization describes its state.
No native ASR/rendering, voice/support, history edit, warning or thermal result is claimed.
Private evidence: `.build/verification/breeze-simplified-20260930-122221/`.

### Resumed Breeze qualification and dictionary regression

The [resumed checkpoint](asr/chinese/breeze-simplified-implementation-20260928.md#september-30-resumed-native-checkpoint-display-poc-passed-acoustic-qualification-incomplete)
supersedes the pending-install status above without converting historical failures to passes.
One reviewed Mandarin acoustic turn passed native and host script/raw/English-byte assertions
in 260.27 s through cleanup. Actual ASR readiness/load remained 169.56 / 168.50 s despite
retained assets/receipt hits; recorded footprint peaked at 2,035,239,568 bytes, thermal
nominal/fair. An active warning continued only in the explicitly authorized memory diagnostic.
This is not a memory optimization, lifetime proof or removal of thermal stops.

Native exact-UUID reopen/preference freeze/explicit edit/raw retention passed separately
in 111.64 s without another ASR load. Reduced coverage/load count is not a faster identical
acoustic/persistence journey. Main/runner identities and personal/model data were preserved.

A native support assertion exposed pinned TWVariantsRev mapping Simplified 么 to 幺.
Do not rewrite expected Simplified text to match that dictionary behavior: reproduce with
real dependency goldens, preserve ambiguous literal input, keep Traditional 麼 conversion
and valid 幺 unchanged. Eleven goldens, persistence, synthetic UI and a real on-phone
converter regression now pass with the original pin/options. No saved projection is rewritten.
The English-only acoustic attempt still returned wrong words; the corrected attempt returned
no words, with the actual No speech recognized notice. Stop and retain these failures rather
than altering ASR/VAD settings or blindly replaying. Fail promptly on absent recognition;
a Ready control alone is not proof of a completed recognized/replied turn.

Console teardown may precede delivery of the final stdout cleanup marker. Emit deliberate
termination intent before the native operation, while retaining final settings readback,
not-running assertions, exact test counts and cleanup as independent gates. Protected
UI-automation startup refusals remain separate from app/model failures and need human action.
The failed corrected support run's recording export contained a pending-attachment error,
not movie bytes; retain scoped hierarchy/log evidence and mark motion evidence unavailable.

Ordinary Core AI Release is restored, final On-device / English / Simplified Chinese readback
and model-free native dictionary check passed in 51.92 s. Build remains separate: latest
runner preparation 20.36 s including cleanup, identical corrected main executable. All owned
work ended; no physical shutdown. Native lookup/Help, fresh reply listening (user could not
confirm), technical-name/number accuracy and a new Traditional acoustic session remain open.
No new Vietnamese acoustic result is claimed. Private evidence remains under
`.build/verification/breeze-simplified-20260930-122221/`.

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


## September 28: native build isolation and memory-export lessons

- Native FireRed/Core AI candidate preparation now generates a project in the evidence directory, with absolute source/package and scheme-container references. This leaves the ordinary project/signing settings untouched, including on failure, and keeps ordinary/native products in distinct locked DerivedData. Initial build failed on the relative scheme container; corrected generator build `20260928-085643-78359` passed in **114.06 seconds through cleanup**, without installation or models. Retain actual compiler/linker, symbol, bundled-pin, signing and native-input fingerprints; a generic Core AI launch log is still not FireRed qualification.
- A file-size limit applies to the entire exporter process, not just the desired table. Do not confuse failure under that limit with unavailable trace data. For the preserved 2 GB trace, bounded streaming gzip export succeeded: **286 MB XML in 42.05 seconds**, approximately 33 MB disk growth, with incremental parsing instead of a giant in-memory XML tree. Preserve the original using an APFS clone and bound wall time, stream size and disk growth separately.
- Local `xctrace help export` omitted working time-window options. Current manual plus bounded probes established `--time-end`/`--duration` support; explicit `--time-start 0s` is rejected, so omit the zero start. Compact Statistics views are much cheaper than detailed allocation histories: four selected-end summaries completed in about 14-15 seconds each. Two detailed window exports hit their 120-second bounds and remain failures, not partial passes.
- Distinguish whole-app Mach footprint, heap/anonymous allocation bytes, VM resident/dirty/compressed fields, and cumulative allocation. VM rows may overlap; never sum them blindly. Selected-end persistent allocation totals were stable while loaded and dropped substantially later, but that does not recover the missing native drain/+30-second footprint or explain the original warning. No memory fix, native qualification or measured shipping performance gain is claimed.
- Six MELI reference clips/scoring rules were human-approved through embedded interview audio before model output. That is reference-review evidence, not iPhone acoustic/TTS acceptance. Proper-name and separate Yes/No coverage remain missing. See the [qualification plan](asr/chinese/simplified-talk-qualification-plan.md) and private evidence for exact identities and blockers.


## September 28: resource capture gate and missing first-use provisioning

- The default `xctrace` Regions Map export can be empty even when VM snapshots exist. The saved 15-second baseline yielded useful rows with an explicit interior `--time-end 14s`; allocation stacks and a bounded timestamped capture interval also remain required. Do not lengthen the soak or waive capture merely because the default view is empty. Physical model-free `resource-check` `20260928-103050-96405` passed capture/long-ACK/Settings/restoration and cleanup in **149.22 seconds**, with no models/audio. Earlier failed exports remain preserved.
- A backend event emitted during initialization is earlier than complete app launch. Require a fresh exact-PID device inventory before Instruments attachment, then recheck unlock after profiler setup. One XCTest initialization failure remains failed with unconfirmed native teardown; later independent process inspection and separate passing model-free recovery do not rewrite it. The phone was locked on later inspection, but the user did not observe the failure, so causality is unproven.
- First resource attempt `20260928-103718-12418` stopped in preflight, not in FireRed inference. The inspected movie showed the not-published error; narrow successful Documents inventory found no FireRed directory and did find CoreAI. Absence of models must be checked, not inferred from a historic preparation receipt or old installation. No FireRed load, acoustic input, tutor/TTS, loaded-idle or real native-release proof was obtained. Cleanup PASS, original Traditional Chinese restored, owned captures finalized. **186.43 seconds through cleanup** is a failed-preflight timing, not model latency.
- Source review separately found diagnostic admission evaluated the idle engine's default rather than Talk's requested model. The initial verbal diagnosis confused that latent issue with the first failure; saved UI evidence corrected it. Review all preflight error paths before declaring a cause. Fixes also stop missing retained assets before catalog work, surface resource preparation faults immediately, avoid duplicate baseline markers from recreated engines, and disallow voice fallback during the resource experiment. Signed builds pass; native corrected-path acceptance remains pending.
- The user explicitly retained manual touches every 30 seconds instead of a temporary extended idle-timer hold, and approved actual Mac output at 63%. No security/idle-timer or volume change, room recording, automatic model retry or asset deletion occurred.
- The user did not approve restoring Mac-staged weights. The requested rectification is first-use acquisition inside the app using the existing installer, followed by native qualification on that same managed package. Proposed order separates download/verification from loading; it does not treat the earlier feasibility probe as combined Talk memory acceptance. See the [current plan and in-app-first amendment](asr/chinese/simplified-talk-qualification-plan.md#approved-amendment-in-app-first-use-not-mac-staged-recovery).


## September 28 session review: preventable command and integration mistakes

The repeated `make: Error` lines did not have one Makefile cause. Some were my implementation/operational mistakes; others were correctly enforced safety refusals that I should have anticipated. Preserve the checks and improve preparation, not suppress exit codes.

| Mistake / observation | Evidence and consequence | Prevention next time |
| --- | --- | --- |
| Repeatedly entered runtime while an idle Mural process still existed | `20260928-120950-33898` and `20260928-122334-61598` refused before installation. User-confirmed idle was incorrectly treated as equivalent to no process. | Refresh saved `status` immediately before runtime, especially after a user opens Settings or a long build/handoff. Use exact-PID `stop-idle` only with existing idle authorization. The guard was correct; it is not a launch API bug. |
| Tried to stop a PID after it had already disappeared | `20260928-122543-66142` refused; its saved `phone-processes.json` was empty. The extra inspection delay made the earlier PID stale. Nothing was stopped. | Keep process inspection and the authorized stop adjacent. If the process exits naturally, use fresh empty inventory as the precondition to continue; do not repeatedly target the old PID or kill a replacement. Races remain possible, so fail-closed identity checks stay. |
| Split the native build flag but missed a UI switch using the old flag | `20260928-112017-15379` failed compilation with a nonexhaustive `RootView` switch. This was my source error, not signing, package resolution or Make. | Trace every use of the old flag/type across app entry, enum cases, views, bridges, generation and compiler-proof fixtures before editing. Compile the affected candidate before requesting phone time. Corrected native and ordinary builds passed separately. |
| Simplified a real redirect into an inaccurate test fixture | `20260928-114321-74679` transferred both graphs but failed on `tokens.txt`. My `parse_qsl` inspection omitted blank values, and the test omitted quoted ETag syntax. | Save literal HEAD/GET Location values and parse with `keep_blank_values=True` when inspecting query structure. Exercise exact observed values with the actual HTTP delegate, including legitimate empty values and mutation refusals. Test the smallest real asset/path before committing phone time to gigabytes. A fabricated URL can prove the wrong contract. |
| Let the test wait for activation after setup had already failed | The same run displayed `Resume setup` and the generic interruption card while XCTest waited on a long completion acknowledgment. No token completion or publication marker existed. | Distinguish transferring, verifying, activated and native-ready. Qualification setup faults now emit `firered_provision_fault`; the existing cooperative abort stops the test promptly. Do not hide a transfer failure by changing the UI to say download complete. |
| Interrupted host ownership left child processes behind | User cancellation ended the host before its finalizer completed; the owned XCTest and console remained. A saved ownership-aware recovery under the shared locks restored settings and stopped owned work. `recovery-cleanup.json` PASS is separate from the failed original. | Treat tool cancellation as unknown cleanup, not success. Inspect saved owner/PID/PGID/start identities, cooperatively drain native tests and confirm process absence before another run. Ordinary runner signal handling does not prove survival of every harness kill/host crash. Do not claim that this limitation has been eliminated. |
| Chose an obsolete screenshot path first | `idevicescreenshot` failed to start screenshotr. `devicectl device capture screenshot` then captured the requested Mural error screen. | Use the current qualified CoreDevice screenshot command. Do not mount another developer image, reinstall, or change permissions to rescue the older tool when the supported path works. |
| Used a display screenshot as a process-status shortcut | A later pre-stop screenshot captured non-Mural foreground content. It did not establish whether background Mural was idle and unnecessarily widened evidence scope. | Use scoped process/lock inventory and the user's idle confirmation. Capture only an authorized foreground app/surface; prefer the owned XCTest app screenshot. Do not inspect other-app content to infer Mural ownership. Keep accidental evidence private; do not publish it. |
| Initially attributed a prior preflight failure to a different latent source bug | The earlier missing-assets run `20260928-103718-12418` was caused by absent assets/unpublished acquisition. The requested-model admission issue was real but not that observed failure. | Read the actual error screen, first failing event and relevant inventory before naming root cause. Label a source-review finding separately until it reproduces the symptom. |

### Qualified correction evidence, not retrospective passes

- Literal-token-header regression: failed before the narrow allowlist fix, then **37 package/HTTP/installer checks PASS**. Host fault/recovery checks also passed. Graph signed-CDN host/path rules, pin verification, exact ranges and atomic activation were not relaxed.
- User-approved retained-state recovery `20260928-121115-36976`: **49.47 seconds through cleanup**, one passing native test, zero failures/skips, cleanup PASS. It fetched only **79,172 bytes**, preserved both graphs, reverified/activated the **1,234,657,933-byte** managed package and asserted the error card absent. Screenshot inspected; native video strictly decoded **485/485 frames, 24.30 seconds**. This is recovery of first-download provisioning within the existing installation, not a new clean-install test or native-model qualification.
- Current-artifact model-free `resource-check` `20260928-122726-70556`: **162.39 seconds through cleanup**, one native test PASS, no skips/failures, useful capture and Settings/nonce/restoration checks, cleanup PASS. No model or audio work. Earlier preflight refusals remain separately recorded.
- Actual combined FireRed memory, acoustic quality and lifecycle acceptance remain open. The documentation review pauses further native loading; download or model-free success does not close those gates.

### Before the next launch

1. Review the exact stage, saved failure/result and cleanup. Fix the first cause; do not blindly repeat a failed Make command or rebuild unchanged executable bytes.
2. Prepare matching signed artifacts/fixtures and check the actual package/backend variant. Then refresh device/process/lock state after the readiness handoff, not only before a long build.
3. If Mural exists, resolve only the exact confirmed-idle PID through `stop-idle`. If it disappeared, confirm absence; if personal work or ownership is uncertain, stop. Carry the user's existing idle approval forward rather than asking the same question again.
4. Run one bounded scenario with explicit device and prepared receipt. Keep setup/model faults observable and cleanup reserved. For screenshots, use the current supported app-scoped workflow, not mirroring or unknown foreground captures.
5. Report preflight/build/runtime outcome separately from cleanup and human listening. Update the execution plan when a stage advances or fails; never replace the failure record with its recovery.

The runnable commands remain in [verify-mural](../.agents/skills/verify-mural/SKILL.md#prepare-first-then-run-one-selected-scenario); this section explains why they must be followed, not a second orchestration system.


## September 28: FireRed resource stop and trace closeout

The managed native continuation `20260928-125336-34898` received an iOS memory warning during the first microphone recording, before decode. Stop behavior is not successful acoustic/resource qualification. Preserve `resource-fault.json` and the failed test; do not rerun to complete the matrix or infer safety from sampled headroom. Sampled peak footprint was 1,523,698,920 bytes; warning footprint 1,406,668,128. Post-drain +10 footprint fell to 106,432,904, but full idle/+30 acceptance is missing. No human listening confirmation was obtained.

- Under an explicit current idle-phone handoff, make fresh status, exact matching Mural PID stop and runtime adjacent. A new PID requires fresh bundle/process verification under the same authorization, never substitution of an old PID or killing another app. Preflight refusals are not native retries.
- Profiler finalization exceeded its 60-second bound; group teardown also raised `PermissionError`. Original cleanup remains FAIL. Later empty host/phone inventories and readable saved trace are a separate recovery result (`recovery-inspection.json`), not permission to rewrite cleanup or equate target exit with profiler exit.
- Offline selected Statistics succeeded on a trace clone: persistent heap/anonymous VM fell from 1,410,619,792 bytes at 85 seconds to 34,990,256 at 104 seconds. About 1.09 GB occupied three large malloc classes before the warning, without call-site attribution. Do not equate these values with Mach footprint or cumulative allocation volume with residency.
- Detailed allocation export hit its finite bound and cleanup permission error. Preserve both failures; do not broaden exports indefinitely, waive ownership checks or guess longer timeouts as a fix. Diagnose the finalization issue offline and qualify any repair model-free before considering another expensive native run.

The warning cause remains inconclusive. Further loading needs a concrete reviewed causal experiment, not unchanged repetition. See the [qualification tracker](asr/chinese/simplified-talk-qualification-plan.md) and private `simplified-managed-20260928/resource-analysis/` artifacts.


## September 30: Breeze memory-warning diagnostic, qualification incomplete

- Reuse the existing runner/main-app identities; the runner is not a second Mural data
  sandbox. The user explicitly approved automation of new test conversations and Mac
  speaker input. Preserve assets, pointers, signing, voices and personal history.
- A receipt hit did not make Breeze loading fast: native preparation measured about
  168 seconds, mostly AudioEncoder loading. Borrowing the VI 90-second readiness wait
  failed. The measured Breeze wait is now 200 seconds, retaining the existing 300-second
  XCTest and 420-second host budgets. This is corrected measurement, not a speedup.
- Teardown must recognize both Cancel setup and End. The shared selector correction
  passed two model-free simulator checks, cleanup PASS/Shutdown, before another model
  scenario. Separate native recovery restored/read back the logged original preference;
  it did not turn the original failed/unconfirmed-cleanup run into a pass.
- Normal policy stopped on a real iOS memory warning after decode. An explicitly
  authorized isolated MURAL_BREEZE_MEMORY_POC build logged warnings without pausing
  active Breeze. Thermal/model/time stops and the existing memory ceiling remained.
  Actual compiler commands, app bytes, exact OpenCC pins/resources/notices and signatures
  distinguish the diagnostic from ordinary Core AI Release. No production qualification
  follows from bypassing a warning.
- Diagnostic memory-poc-acoustic: one native test PASS, warning observed, real reply
  completed and separately human-confirmed audible English. Peak process footprint
  2,039,777,864 bytes; thermal states 0/1; ASR load 166.08 seconds, preparation 167.08.
  Whole runtime through cleanup 286.56 seconds; initial diagnostic build was separate,
  124.81 seconds. Different scope/instrumentation prevents a speedup comparison.
- The reviewed mixed clip produced English instead of its Mandarin words. Display
  matched raw recognition, so this did not exercise Han conversion. Script rendering
  cannot fix recognition. Keep word accuracy, raw/display equality, Simplified meanings,
  human audibility and persistence/edit judgments separate.
- Whole-application swipeDown was followed by an unrelated-app interruption and a
  resume preparation, so the full host check failed despite the completed spoken phase.
  Do not weaken the single-preparation/frozen-pair assertion to hide it. A bounded
  content-coordinate gesture and foreground guard are compiled; their new model-free
  regression must pass before another acoustic check. Do not inspect unrelated-app
  recording frames. The source video decodes fully; only scoped Mural appearance was
  visually reviewed, not the complete transition.
- For custom evidence roots, explicit DEVICE_PREPARED also selects prior compiler proof
  during preparation. Byte-identical app requirements remain; source hashes now include
  untracked delivery files. No cache clearing or timestamp manipulation to force compile.
- Restore the ordinary binary before handing the phone back or asking for a later test
  window. Here the user withdrew readiness before restoration, then device status was
  unavailable: no further phone mutation is permitted. Clearly report the terminated
  diagnostic still installed, queued normal restoration, last read-back preference and
  missing gates. Never hide that installation behind a generic cleanup PASS.

Private evidence: .build/verification/breeze-simplified-20260930-122221/. Corrected runner
builds and host checks passed; the new scrolling regression, Mandarin-dominant F00A clip,
lookup/Help, durable reopen/edit and Traditional native confirmation are pending. No
quantization, model re-export, broad soak, push or OS thermal override occurred.
