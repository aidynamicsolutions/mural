# Physical iPhone end-to-end verification with acoustic speech input

## Decision and scope

Use a Mac script to play repeatable speech through the Mac's speakers while native XCUITest operates Mural on a nearby, connected physical iPhone. Mural must record through the real iPhone microphone and use its actual on-device recognition, tutor, and speech paths.

Keep this as a separate, linked track from the [simulator lifecycle and SimSlim plan](simulator-verification-lifecycle-plan.md). Simulator memory optimization can finish independently. Physical voice testing has additional signing, audio, privacy, data, and model-resource risks; a blocker here must not delay safe simulator cleanup or be hidden by simulator passes.

**Current authorization: implementation, signed native runner builds/installations, scoped evidence and bounded physical tests using synthetic speech are approved.** Complete safe preparation first, then confirm the audible window and any room-audio capture. Preserve the existing bundle, Core AI Release opt-in, assets, caches, preferences and personal history. No commits or pushes.

This design is now qualified within the recorded acceptance limits below, including real acoustic turns and exact transcript persistence. Historical planning and failed attempts remain in the log; they are not current pending work. The goal is to minimize repeated human operation, not to pretend hardware prerequisites or subjective listening checks disappear. Future runs remain opt-in and require a confirmed audible window, not blanket permission from this historical authorization.

For current stage selection and commands, use the [verification skill](../.agents/skills/verify-mural/SKILL.md#qualified-opt-in-native-local-workflow). For measured timings, failure prevention and pending speed experiments, see [physical E2E lessons](physical-iphone-e2e-lessons.md).

## Progress tracker

Status: pending, in progress, complete, blocked. Mark a stage complete only with its recorded acceptance evidence. Preserve failed attempts and limitations.

| Stage | Status | Deliverable / completion gate |
| --- | --- | --- |
| 0. Research and plan | complete | Reviewed native UI automation, mirroring microphone restrictions, current Mural device instructions, and existing capture/backend events. Saved this plan; no runtime qualification. |
| 1. Device and safety preflight | complete | Explicit owned phone session, compatible signed runner, correct app/backend/assets, agreed audible test window, and synthetic-data boundaries. |
| 2. Native control and real-model baseline | complete | XCUITest drives normal Mural without preview fixtures; real preparation and a typed conversation succeed with the intended backend and retained data. |
| 3. Qualify acoustic input | complete | Pre-generated Mac speech is played once after actual capture starts; real capture, matching transcription, and timing/order evidence pass for one bounded turn. |
| 4. Repeatable medium-to-hard voice E2E | complete | Distinct spoken turns, real tutor responses, output-audio evidence, and exact transcript retention after relaunch; repeat on a fresh run without resets. |
| 5. Failure handling and cleanup | complete | Missing readiness, cancellation/timeout, disconnect/lock and audio failures cannot produce false passes or leave playback/capture/test processes running. |
| 6. Explicit entrypoint and handoff | complete | Documented opt-in device command, fixture recipe, evidence/results, cleanup, and separately reported human-only quality gaps. |
| 7. Runtime optimization follow-up | complete | Phase timing, early-exit UI queries and actual-playback acknowledgment implemented; model-free, acoustic, two-turn/repeat and cancellation acceptance passed. User confirmed both iPhone replies audible in each final optimized two-turn run. |
| 8. Receipt, native-launch/query optimization and checklist handoff | complete | All four priorities and checkmark fix implemented. Native model-free/baseline/acoustic/multi/fresh-repeat/cancellation acceptance and cleanup PASS; before/after transition video inspected. User confirmed both iPhone replies in both new full runs. Observed further reduction about 2.5%, with added checklist/video coverage; mandatory first native loading remains expensive. |

- [x] Stage 0: research and plan
- [x] Stage 1: device/safety preflight
- [x] Stage 2: native control and real-model baseline
- [x] Stage 3: acoustic input qualification
- [x] Stage 4: repeatable voice E2E
- [x] Stage 5: failure handling and cleanup (representative bounded paths, limitations below)
- [x] Stage 6: explicit command and handoff
- [x] Stage 7: first runtime optimization and human listening confirmation
- [x] Stage 8: four follow-up priorities, checklist regression and physical qualification

The original qualification stages are complete within the limitations below. Follow-up documentation and runtime optimizations are implemented with automated physical acceptance; see the [ordered implementation results](physical-iphone-e2e-lessons.md#recommended-implementation-order). Human listening for both final optimized two-turn runs is separately confirmed. Do not run expensive simulator experiments and phone-test builds concurrently against shared build artifacts.

## What the test does

```text
Mac: prepare short, fixed speech files using an installed voice
  -> native XCUITest operates normal Mural on the physical iPhone
  -> confirm the intended backend and real readiness
  -> tap Record through the app UI
  -> observe the current turn's actual capture-start event
  -> Mac plays that turn's file through its speakers
  -> iPhone microphone captures the sound
  -> tap Send after the utterance and bounded trailing margin
  -> real ASR -> real on-device tutor -> real speech output
  -> verify results, end, relaunch, inspect saved synthetic transcript
  -> stop owned playback/capture/test processes and preserve evidence
```

The USB connection carries development/control traffic and may supply power. The planned speech input travels through the air, not over USB. The iPhone performs model loading and inference; no simulator or Mac substitute stands in for it.

Use native tools first:

- Existing `MuralUITests` target for UI actions and assertions.
- `xcodebuild` with `xcbeautify --is-ci`, saved raw logs, and unique xcresult bundles.
- macOS `say` to generate audio files and `afplay` to play them, or an approved local recorded fixture when a suitable installed voice is unavailable.
- Existing Mural-only device logging and current turn identifiers for correlation.
- One small bounded host runner, using standard-library/shell facilities. No Appium, global service, new provider, or shared device-management framework unless a concrete native-tool blocker justifies it.

## Prerequisites: more than just proximity

### User/environment prerequisites

- A compatible physical iPhone is connected, paired/trusted, development-enabled, unlocked as required, and available exclusively for the bounded test window. Reuse existing setup rather than asking the user to repeat it unnecessarily.
- The iPhone is stationary near the Mac in a quiet space with its microphone and speakers unobstructed. Record approximate distance/orientation and repeat them between runs.
- Mac playback reaches the built-in speakers, not headphones, Bluetooth, AirPlay, or another room. Mural uses the intended iPhone input/output route. Do not silently reconfigure someone else's active audio session.
- Use an agreed moderate volume. Preserve original mute/volume/routing settings and restore any changes; never maximize volume automatically. Keep small documented calibration values for rate, gain, lead/tail margins and placement rather than assuming identical hardware acoustics.
- No active personal Mural conversation, phone call, unrelated recording, or competing agent session. Use short synthetic phrases only. Recording the room requires a suitable private environment and explicit permission for the capture scope.
- Trust, unlock, permissions and other protected prompts remain human gates when needed. Do not bypass them or change passcode/Auto-Lock/security policy to make tests run.

### App/model prerequisites

- Discover the current physical UDID. Do not use a historical identifier or infer ownership from the device name.
- Preserve the existing phone bundle `com.kevintruong.mural.dev`, signing configuration, data, and retained assets. The XCTest runner needs its own valid identity/provisioning; do not blindly apply the app's bundle override to every test target.
- Read the current local-conversation and Core AI checkpoint instructions before any build. At planning time, the paired iPhone uses explicit Release `MURAL_COREAI_TALK` opt-in. Confirm the actual compiler flags and `local_talk_asr_backend` event, not just the requested command or successful build.
- Keep the approved language pair/backend. Start with the currently qualified English/Vietnamese path and short English utterances. Do not activate blocked FireRed/Simplified Chinese loading or introduce a new recognizer to test this harness.
- Confirm required Apple model availability and retained recognition/TTS assets without clearing caches, re-exporting models, downloading replacements, or changing model policy. Missing assets/readiness is a blocker.
- A Prepare button or Ready label alone does not prove every model loaded. Some native work happens at Send; require backend/inference events and actual turn results before claiming the full pipeline.
- Use On-device mode only. No premium fallback, API keys, or paid provider calls.

### No mirroring during microphone capture

Apple states that iPhone Mirroring cannot access the phone microphone, and Device Hub physical-device interaction can cause apps to record silence. Close owned mirroring/control sessions before capture, checking for unrelated ownership first. Native XCTest control is a different path, but its real audio compatibility still needs Stage 3 qualification.

Do not open Device Hub just to record the test if that changes microphone behavior. Prefer XCTest attachments/recording where supported; separately prove the chosen evidence method does not alter capture.

## Stage 1: Preflight and checks before implementation

Inspect the current app/test scheme, signing and source registration, then define the assertions and failure cases before implementing the host runner. Reuse the existing test target and real UI controls. Do not create a second production backend or a fake successful audio state.

Record a fresh local run specification:

- Device/runtime, app revision/build/configuration, runner identity, backend and language pair.
- Retained asset/cache state without an expensive redundant hash sweep; use the app's existing verification path.
- Synthetic phrases, expected recognition, fixture voice/rate/duration/hash, speaker route/gain and placement.
- Finite preparation, capture, inference and total deadlines based on existing device evidence, not assumed simulator timing. Set a bounded cleanup/drain window too.
- Ownership of the phone session and every host/phone test process, initial settings, and evidence location.

Failure cases to specify up front:

- Wrong/locked/disconnected phone, absent permission or invalid runner signing.
- Wrong app/backend, missing assets, unavailable system model, or unexpected cloud route.
- Playback starts before capture, starts twice, uses a stale turn event, goes to headphones, or continues after cancellation.
- Playback is truncated by Send or the recording limit; another turn's text is mistaken for the result.
- Silence or noise produces nonempty but incorrect recognition and is falsely counted as success.
- UI says Speaking but no sound is emitted; an evidence recorder changes the audio route.
- Host log delivery is delayed/missing, the test runner times out, or a helper remains alive.
- Thermal/resource warning, memory warning, model failure, or prior work still draining causes an unsafe automatic retry.
- Test setup resets user settings/history or reuses someone else's process/recording.

Acceptance: all necessary setup is available, ownership and limits are recorded, and the planned checks cannot accidentally target personal work. If a prerequisite is missing, stop before playback or model work.

## Stage 2: Native control and real-model baseline

- Build/sign only the necessary runner and approved app configuration. Prefer retaining the intended installed app/build when supported; do not casually replace the active opt-in Release with ordinary Debug or baseline Release.
- Run explicit physical-only tests behind a deliberate device-E2E opt-in, so an ordinary test-suite invocation cannot unexpectedly load phone models or start this workflow. A skipped opt-in test is not acceptance. Existing `--preview`, fake setup, or seeded conversation tests are not model acceptance, even when executed on a phone.
- Through normal UI, select the approved local configuration, Prepare, wait for real readiness, and send a short synthetic typed message. Verify a real tutor response and normal state transitions, then End and inspect the saved synthetic conversation.
- Correlate actual app backend/readiness/model events with the current process and turn. Typed input proves UI/tutor integration and the exercised preparation, not microphone capture or ASR inference.
- Preserve the existing paired-phone workflow until native automation has been qualified. No tester subagents, broad phone log archive, or new generic test framework.

Acceptance: native UI actions and actual local model behavior work without mirroring. Stop here if runner/real-model behavior is blocked; do not try to solve it with acoustic playback.

## Stage 3: Qualify acoustic speech input

### Generate and freeze speech before the test

Use an installed local voice to generate a short file, not live text-to-speech timed by a guessed sleep. Illustrative commands for the future runner, not commands executed while writing this plan:

```sh
/usr/bin/say -v "$VOICE" -r "$RATE" -o "$EVIDENCE/turn-1.aiff" \
  'I bought three apples on Tuesday.'
/usr/bin/afinfo "$EVIDENCE/turn-1.aiff"
# Only after the current physical capture-start gate succeeds:
/usr/bin/afplay "$EVIDENCE/turn-1.aiff"
```

- Validate the generated file, record its duration/hash and exact source text, and replay those same bytes for comparable attempts.
- No voice download, paid TTS service or new dependency by default. If a suitable installed voice is absent, report it or use an approved local fixture.
- First qualify one short English utterance, comfortably below Mural's recording cap. Add multilingual recordings later only with suitable, intelligible fixtures and a specific coverage need.

### Coordinate with real capture, not a timer alone

Mural already emits `capture_started` after `AVAudioEngine.start()`, plus `asr_trial_capture` with a fresh turn UUID. It also emits `asr_trial_send`, `asr_trial_final`, and `asr_input` frame counts. Reuse these instead of adding app instrumentation unless a concrete evidence gap appears.

- Start a scoped Mural-only log capture before the UI action and record the starting offset/process identity.
- The host runner may play a fixture only after a new capture-start event for the current run/turn and the expected UI recording state. Historical events must not trigger playback.
- Give each turn exactly one playback. Capture-start proves engine startup, not audible input; recognition/frame evidence supplies the later checks.
- Qualify how the phone test and host playback coordinate before building a suite. First try the existing UI-test/log channels, known fixture duration, and small measured lead/tail margins. Record actual observed ordering. A bounded recording window is acceptable only when evidence confirms the entire playback fits inside it; delayed delivery, missing events, or early Send makes the attempt fail/inconclusive, not pass.
- If these channels cannot reliably coordinate playback completion and Send, stop and identify that blocker. Add only the smallest explicit acknowledgement mechanism needed; do not quietly introduce a long-running server or guess longer sleeps indefinitely.
- Playback must finish before Send, and no new recording may begin while Mural is speaking or prior inference is draining. Wait for real state transitions; margins accommodate acoustics, not missing readiness.
- Never compare host and iPhone monotonic clock values directly. Preserve each clock domain, host event-receipt timestamps and native turn order; do not derive precise cross-device latency without a qualified alignment method.

### Prove that speech was genuinely captured

Require the current turn's actual capture/send/final events, nonzero input frames/captured duration, and matching visible recognized text. Nonempty text alone is not success.

Define acceptable normalization before the run: case and punctuation may be ignored; number spelling may have an explicit equivalent. Do not remove wrong words, change the reference after seeing output, or count the previous turn's transcript. Preserve actual recognition and failures.

Acceptance: one bounded normal Record/Send turn captures the Mac's speech and produces the expected recognition with actual on-device processing. The host playback stops and all evidence remains local. This is a harness qualification gate, not the final E2E scenario.

## Stage 4: Repeatable medium-to-hard voice E2E

After acoustic qualification, run a small real scenario rather than a long stress suite:

1. Normal local preparation with the intended backend; wait until Mural's greeting/playback has finished.
2. Record/Send a first distinct phrase, for example `I bought three apples on Tuesday.` Require matching recognition, a real completed tutor response, and return to the correct ready state.
3. Record/Send a second phrase with different facts, for example `My appointment is at ten tomorrow.` Require the second recognition and response to belong to that turn, without duplicated/stale first-turn text or overlapping recording/playback.
4. Observe actual speech output for the responses. Use the output-evidence rules below rather than treating a Speaking label as proof.
5. End through the UI. Relaunch normally, open the just-created synthetic transcript, and assert both exact observed learner turns and completed assistant text persisted once, in order. Do not reset or inspect unrelated private conversations.
6. In a separate bounded scenario, exercise one relevant native cancellation/recovery transition, such as End during generation followed by waiting for drain and starting a distinct new conversation. Assert no late old turn or speech is attributed to the new session. Do not claim all background/thermal lifecycle paths from this one check.
7. Repeat the main scenario in a fresh run with the same retained assets and fixture bytes. No automatic repeat-until-green, ten-turn soak, cache reset, or claim of cold-cache performance.

AI responses are not deterministic. Assert a real response, correct turn association, completion/state transitions and durable text, and retain output for a predeclared content rubric. Do not require identical generated wording or claim teaching/language correctness merely because any text appeared.

### Output speech evidence

- Native TTS start/completion events establish playback pipeline behavior, not that the physical speaker was audible or pronunciation correct.
- Prefer a short external Mac microphone capture of the phone response when permission and privacy conditions allow. Capture only the bounded synthetic test window and correlate it with the actual response phase so the Mac's own reference speech is not mistaken for Mural's output.
- Check the saved audio is decodable and contains the expected response segment; nonzero file size or waveform energy alone does not prove speech correctness. Record which segments were actually listened to or otherwise inspected and by whom.
- First verify that host audio/video capture does not change Mural's input/output route or microphone availability. Avoid USB audio redirection for the initial speaker-path check because it can change the route being tested.
- If external capture is unavailable, request one targeted human listening confirmation and label the result partially human-confirmed. Do not report a fully autonomous audible-output pass. Reuse existing confirmations only for behavior/builds they actually cover.
- Synthetic Mac speech does not establish recognition quality across human accents, rooms, microphones, or natural mixed-language speech. Pronunciation, usefulness and teaching quality retain focused human review where automated evidence is insufficient.

Acceptance: actual microphone -> recognition -> tutor -> speech output -> retained conversation is evidenced for the bounded scenario, with every automated/human/blocked part labeled. A logs-only run can pass its narrower assertions but not complete the audible-output gate.

## Stage 5: Failure handling, ownership and cleanup

- Use one explicitly owned phone test session. Refuse concurrent use; record process identity/start time before stopping anything. Reuse a small real-user per-device lock pattern without simulator-specific operations, not a phone control service.
- Bound `say`, `afplay`, log capture, native testing, output capture and finalization. Stop owned playback immediately on cancellation, lost capture readiness, disconnect, timeout or resource warning.
- Preserve original test failure separately from cleanup failure. Timeout, missing log, unavailable audio, skipped tests and unsupported native behavior are not passes.
- Stop on the first memory warning, unsafe thermal state, model/asset error or runaway duration. Let the app's existing cancellation/drain policy finish within its documented bound; no automatic backend fallback or rapid re-Prepare. Do not intentionally induce memory/thermal stress.
- End the synthetic conversation where safe, preserve finalized text, stop the owned test runner/Mural work as appropriate, and confirm owned host helpers stopped. If safe drain cannot be confirmed, report it rather than claiming idle.
- Restore changed app preferences and Mac/phone audio settings. Keep synthetic saved records/evidence rather than deleting data to make cleanup look clean. Never clear an active personal session.
- Never apply SimSlim, `simctl shutdown`, a reboot, erase/uninstall, or model/cache deletion to the physical phone. Phone cleanup is stopping owned work, not switching off the user's device.
- Test host-runner failure handling using a minimal prewritten runnable check where deliberately triggering the failure on the phone would be unsafe. Do not build unit suites for coverage; enumerate failure modes before implementing the helper.
- For SIGKILL/host crash, keep recoverable owner/process evidence and a conservative manual recovery procedure; no global kill commands or automatic stale-PID reuse.

Acceptance: representative safe failure paths and helper checks preserve errors/evidence, leave no owned playback/capture/test process running, and preserve the phone's data and usable state.

## Stage 6: Explicit entrypoint and instructions

Implemented entrypoint, separate from default simulator verification (defaults to build-only `prepare`; runtime requires an explicit stage and confirmed readiness):

```sh
make agent-verify-device DEVICE_UDID="$DEVICE_UDID"
```

- Opt-in only. `make build` and `make agent-verify` must never unexpectedly play speech, record the room, install on a phone, or load phone models.
- Add a thin target to the same Makefile proposed by the simulator plan. Keep the direct bounded script usable without making this track depend on all simulator stages.
- Keep scripts/test selectors small and Mural-specific. Extend `UITests/MuralUITests.swift` or use the project's supported source-registration path; never edit generated Xcode files by hand.
- Update the verification skill with a physical-native workflow only after it is qualified. Mark which manual steps it replaces and which privacy/security/listening checks remain human; do not leave contradictory “all phone testing is manual” instructions.
- Document the exact repeat command, required placement/audio conditions, chosen fixture/voice, accepted recognition normalization, timeouts, backend identity, result classification and cleanup.
- Do not use this automated run as an unqualified performance benchmark: instrumentation, repeated caches and acoustic conditions influence timings.

## Evidence and reporting

Evidence root: `.build/verification/physical-iphone-e2e/<unique-run>/`.

Retain locally:

- Run specification, source state, app/runner identity, physical UDID/runtime and ownership.
- Fixture text, voice/rate, duration/hash, actual playback start/end and exit status.
- Mural-only logs with process/turn correlation; record missing/redacted events as gaps.
- Full build/test logs, unique xcresult, summaries, screenshots and available validated screen video.
- Actual recognized text, saved synthetic transcript assertions, response/state outcomes, and scoped output audio if authorized.
- Explicit automated versus human-confirmed versus inconclusive results.
- Cleanup record for playback, logging, recording, test process, app state, and restored settings.

No real keys, private conversations or broad device archives in tracked files. Keep fixture/output captures uncommitted and inspect for unrelated room speech before sharing. A screen recording without sound is not audio evidence.

Required closeout:

```text
Native device control: PASS / FAIL / BLOCKED
Intended backend / real model execution: evidence or explicit gap
Acoustic input / recognition: PASS / FAIL / INCONCLUSIVE
Tutor / state / persistence: PASS / FAIL / INCONCLUSIVE
Audible output: automated evidence / human-confirmed / not verified
Native lifecycle scenario: exact scenario and result
Owned playback, capture and test processes: stopped / explicit failure
Settings/data: preserved or changes listed
Cleanup: PASS / FAIL
Simulator optimization: separate plan and status
```

## Intended changes and non-goals

Anticipated implementation touches: one bounded physical-device host script, explicit native device tests in the existing target, a thin Make target, and the relevant verification documentation. A small fixture manifest may hold concrete phrases and calibrated values if it avoids duplication. No production inference/microphone refactor is planned; missing observability or a product defect is a named finding to scope separately.

This plan does not reopen accepted model-quality work, authorize blocked model branches, promise accent-wide recognition, introduce cloud inference, require new audio hardware, or automate every system interruption. Begin with the existing Mac speakers and physical iPhone; justify anything more with an observed blocker.

## Implementation log

### Safe preparation started

- Read repository and current physical verification instructions; existing untracked plan preserved. Source baseline `ab56012`; no other starting changes.
- Fresh discovery: connected wired, paired iPhone 17, Developer Mode enabled, iOS 27.2 (24B5084k). This differs from the earlier iOS 27.0 checkpoint, so old runtime/model passes are not reused.
- Existing `com.kevintruong.mural.dev` installation confirmed. No app launch, installation, model load, playback or capture yet.
- Mac output is muted at volume 0. Do not change it until the audible window is agreed. Samantha and Daniel voices are installed.
- Device Hub belongs to another project's simulator. Do not terminate it; physical mirroring closure remains a runtime gate.
- Reuse the existing Makefile with a thin opt-in device target. Implement/qualify baseline before enabling acoustic and multi-turn stages, rather than ship an unqualified all-stages suite.
- Failure assertions specified before code: absent/wrong UDID or opt-in, busy ownership/build lock, wrong app/runner identity or compiler backend, active/personal session, unexpected pair, missing log readiness, model/resource errors, skips/zero tests, timeout/cancellation, and incomplete process/drain cleanup must fail closed. No automatic retry. The host-only check will exercise safe refusal and process cleanup without touching the phone.

### Native runner preparation, first build

- Added `make agent-verify-device DEVICE_UDID=... DEVICE_STAGE=prepare` and physical-only baseline XCTest in the existing target. Defaults remain simulator-only; device preparation never launches/installs/plays audio.
- Added distinct overridable app/runner bundle settings in the source generator and regenerated the project, preserving the default public identities. Never apply a shared `PRODUCT_BUNDLE_IDENTIFIER` override to both targets.
- Host-only prewritten failure check PASS: explicit request gates, exact non-skipped result counts, fresh-process ordered backend/model events, resource/model failure rejection and timeout process-group cleanup.
- First build stopped at missing runner provisioning profile, before installation/model execution. Evidence: `.build/verification/physical-iphone-e2e/20260927-162646-91961/`; cleanup PASS, phone not launched. Required signed-runner authorization covers requesting the profile through Xcode automatic provisioning with the existing team; add `-allowProvisioningUpdates`, not a signing-identity change.
- Preparation records source and executable fingerprints for the later test-without-building gate. Baseline refuses stale artifacts, wrong phone, busy locks or active mirroring/capture. Acoustic stages intentionally remain unavailable until baseline qualification.

### Signed preparation passed; audible gate pending

- Signed Release app and distinct native runner build PASS with the existing team and explicit `MURAL_COREAI_TALK`; actual Mural compiler invocation and both signed bundle identities verified. Evidence: `.build/verification/physical-iphone-e2e/20260927-162800-95063/` (`build.log`, `prepared.json`, `result.json`, `cleanup.json`).
- Host safety checks passed again. No installation, app launch, model execution, speaker playback or room recording. Cleanup PASS; no owned helpers remain.
- Next gate: user confirms private audible window, idle/available unlocked phone, placement, moderate built-in speaker route, and Device Hub closure coordinated with its existing owner. Baseline first produces phone greeting/typed-response speech; no Mac microphone capture is needed for that baseline. Stages 2-6 are not yet qualified.

### Paused at the user's audible-window gate

- User is leaving for dinner and will explicitly say when to resume. Do not start installation, native testing, model work or playback while waiting.
- Output-evidence choice: one targeted human listening confirmation; **no Mac room recording**. Placement and moderate speaker route/volume remain unconfirmed. Device Hub was still running for another project at the last read-only check; do not stop its process.
- Stage 1 is blocked on that readiness gate, not a failed runtime qualification. Stage 2 native test and host runner are implemented/built but unqualified; acoustic/multi-turn stages are not implemented or run. No test skip or build success is counted as device acceptance.
- Resume by rediscovering the exact phone and checking ownership/mirroring/placement/readiness. Prepared build: `.build/verification/physical-iphone-e2e/20260927-162800-95063/prepared.json`. If inputs remain identical, intended bounded baseline command is:

  ```sh
  make agent-verify-device DEVICE_UDID="$DEVICE_UDID" DEVICE_STAGE=baseline \
    DEVICE_READY=YES \
    DEVICE_PREPARED="$PWD/.build/verification/physical-iphone-e2e/20260927-162800-95063/prepared.json"
  ```

  This is an **unqualified baseline command**, not acoustic/full-suite acceptance. It installs the prepared app/runner through native XCTest, performs the synthetic typed path, and checks ordered real backend/model evidence. No room capture or Mac playback. After native qualification, implement/qualify one actual acoustic turn before the multi-turn/persistence scenario.
- Closeout at pause: signed build PASS; native control/model/acoustic/persistence/audible/lifecycle NOT RUN. Host refusal/timeout checks PASS. All owned preparation processes stopped; cleanup PASS. Phone app/data/assets/preferences and Mac audio settings unchanged. Other project's Device Hub untouched. No simulator testing, commits or pushes.

### Resumed: native runner installed, baseline stopped before model work

- User resumed the audible window and closed Device Hub. Preserved unrelated `AGENTS.md` and skill edits made during the pause.
- First resumed preflight refused discovery's `disconnected` tunnel state. Direct lock-state RPC succeeded twice; this is not a reliable physical reachability field on this runtime. Corrected the gate to require the exact paired physical iPhone plus successful bounded direct lock/app queries. Missing existing app and required unlock now refuse explicitly.
- Incremental preparation correctly refused missing actual compiler evidence (`20260927-202816-32202`). Touched only the app source timestamp to force a compiler invocation, with no source/content change, then signed preparation passed: `.build/verification/physical-iphone-e2e/20260927-202844-33413/`. No cache/model removal.
- Native attempt `20260927-202902-33963` could not install its runner: three free-profile app slots were occupied. Original automatic cleanup was conservatively FAIL because no test teardown ran; subsequent app/process inventory and xcresult prove no runner started and no owned helpers remain. Saved `cleanup-reviewed.json` PASS separately without overwriting that initial failure.
- User explicitly authorized deleting **Mural QA only**. Removed `com.kevintruong.mural.qa` under the device lock; confirmed `com.kevintruong.mural.dev` remains installed. This authorized deletion is the sole data-removal exception, limited to QA and its container. Evidence: `.build/verification/physical-iphone-e2e/qa-slot-20260927-203206/`.
- Next attempt `.build/verification/physical-iphone-e2e/20260927-203209-41695/`: native runner installed, launched normal Mural and read real UI successfully. Baseline failed closed at the language gate: retained pair is **English / Traditional Chinese**, not the plan's English / Vietnamese. No Prepare, model inference, microphone capture, Mac playback or preference changes occurred. XCTest terminated its owned app; phone process query showed no Mural/test runner afterward. Cleanup PASS.
- Additional blocking evidence gap: scoped `idevicesyslog -p Mural` captured only `[connected]` and exit, despite observed app launch. No actual backend/readiness/resource events are available. Do not invoke models or acoustic testing until a fresh Mural-only event channel is qualified; no broad device archive or fake readiness substitute.
- Native install/launch/UI control is evidenced, but Stage 2 as a whole is NOT passed. Preserve current Traditional Chinese preference; planned English/Vietnamese testing must explicitly snapshot/restore it through UI, not silently change the backend or relax the expected pair. Stages 3-4 remain unimplemented/unrun pending these gates. Stage 5 has host timeout/refusal and real prelaunch/setup failure evidence, not complete phone failure-path qualification.

### Scoped console qualification and first real preparation

- Qualified a bounded app-only `devicectl ... launch --console` with `OS_ACTIVITY_DT_MODE=YES`: actual fresh Core AI backend event, no models requested, owned app/console stopped. Evidence: `console-qualification-20260927-203519/` under the physical evidence root. The failed syslog route is not reused.
- Runner now requires that fresh backend event before starting XCTest; XCTest activates that same console-attached app. Requires no existing Mural process before in-place install/launch, monitors scoped faults, and verifies phone process absence after cleanup. Host event check supports console PID/thread prefixes.
- Native baseline `20260927-203836-57188`: actual Prepare reached Ready in **22.009 s**, staged Core AI GPU backend, existing fp8 encoder selection and pal8 decoder support. Retained TTS was Supertonic3; no model/voice/backend preference changed. No memory warning or serious/critical thermal event observed. Typed input was not sent because the XCTest selector incorrectly asked for a TextView instead of the production TextField. This is a harness failure, not model acceptance or a model retry.
- Native teardown End/drain/termination and restoration of Traditional Chinese were confirmed by XCTest; phone process list empty, cleanup PASS. Corrected the selector to the actual labeled TextField. No acoustic playback/capture occurred.
- User requested avoiding automatic screen lock during lengthy preparation. Added temporary foreground preparation-only `UIApplication.isIdleTimerDisabled`, preserving/restoring its prior value on Ready, error/cancel, consent wait, background/inactive and root disappearance. Manual lock and system Auto-Lock preferences remain unchanged. Failure cases defined before implementation: idle/consent/away must not hold it; repeated preparation must not overwrite the saved prior value; completion/cancel must restore that value. The prewritten host event contract now requires acquisition and restoration during the real baseline. A short native preparation cannot by itself qualify a long unattended auto-lock interval.

### Native baseline PASS; acoustic gate next

- `.build/verification/physical-iphone-e2e/20260927-204620-74113/`: native XCTest **1 passed, 0 failed, 0 skipped** on the intended physical phone. Actual staged preparation **21.178 s**, Apple tutor response **3.155 s**, completed synthetic learner/assistant text verified in Transcript. No preview/injected transcript/fake response.
- App-scoped keep-awake acquisition and restoration to `false` confirmed around real preparation. This proves the intended property lifecycle, not a long unattended auto-lock interval or every cancel/background path.
- Traditional Chinese meaning preference restored and asserted, app/test/log processes stopped, cleanup PASS. No microphone recording or Mac playback; audible-output listening still unconfirmed.
- The host initially rejected repeated backend-init events, incorrectly treating multiple owner initializations in **one PID (80427)** as ambiguous processes. Added failure checks first, corrected correlation to require exactly one distinct PID, then re-evaluated the unchanged saved native/log evidence. `reviewed-result.json` records PASS; original `failure.json` remains. No model rerun for this parser-only correction.
- Stage 2 complete for native control, real typed tutor and saved transcript. ASR inference, acoustic input, relaunch persistence and lifecycle recovery remain unverified. Next: freeze `say` fixture bytes, agree physical placement and moderate built-in Mac speaker volume, then implement/qualify exactly one current-capture-gated acoustic turn. No room recording per user choice.

### Acoustic preparation implemented; placement confirmation pending

- User confirms the baseline phone greeting and tutor reply were **both audible**. This is targeted human confirmation for that baseline, not automated audio analysis or acoustic-stage acceptance.
- User chose to set comfortable Mac volume themselves, rather than authorize the runner to change it. Readback is **50%, unmuted**, built-in MacBook speakers. No agent audio-setting changes; preserve the user-selected value. Still no room recording.
- Frozen fixture `.build/verification/physical-iphone-e2e/fixtures-v1/turn-1.aiff`: Samantha, rate 150, `I bought three apples on Tuesday.`, 1.968345 seconds, SHA-256 `1670c9c29ac928b5849ce4fde4dbc31fef3d01497afba7097a506f9984522111`. Generated locally with `say`; not played yet.
- Added opt-in `DEVICE_STAGE=acoustic`. Requires non-muted built-in speakers, recorded placement, frozen fixture hash and prepared signed inputs. One playback only, gated by fresh capture-start/turn evidence AND native Send-label UI marker. Late gate (>5 s), early Send, playback overrun, model/resource warning, wrong/duplicate turn or empty frames fail. Owned playback stops before native-test group finalization.
- Native recording window is 12 seconds, fixture is about 2 seconds; receipts/playback times stay in host clock domain and phone turn events retain theirs. Require current matching capture/send/final ID, nonzero frames/duration, normalized exact recognized sentence and a completed real reply/saved transcript. This is not a cross-clock latency benchmark. Channel timing remains a qualification question, not an assumed pass.
- Prewritten host failure checks expanded before parser code for duplicate/wrong turn IDs and zero frames. Host checks and signed preparation PASS: `.build/verification/physical-iphone-e2e/20260927-205424-93440/`. No acoustic run yet; user did not answer placement field, so confirm actual proximity/microphone clearance before playback.

### Acoustic qualification failed its frozen text criterion; stopped before Stage 4

- User confirmed 20-30 cm placement, unobstructed microphone and cool phone. Two preflight refusals preserved the same reported Mural PID after user closure confirmations. Scoped identity check then terminated only that residual Mural process under the device lock; no data removed. Evidence in `20260927-205708-99757/residual-*.json`.
- First acoustic attempt `20260927-205810-2393` encountered the native `kTCCServiceMicrophone-alert`. The five-second Send-label wait expired; no Mac playback or ASR Send occurred. User subsequently confirmed manually approving that prompt. Capture started late, and the host refused playback without the UI gate. This is a permission/automation failure, not an ASR result. No prompt was automatically accepted.
- Added a bounded 90-second native permission/capture wait, keeping the actual fresh-capture/UI playback gate at five seconds. Added session-specific `restore-settings` native recovery (the known original here is Traditional Chinese), which performs no Prepare/model/microphone actions. Recovery `20260927-210321-16141` PASS.
- Actual acoustic attempt **`20260927-210400-17573`**: Mac `afplay` exited 0 before Send; native capture/send/final UUID **04493471-8A71-4EF1-A11A-503D0EE45973**, **648,000 source frames**, **216,000 converted frames**, **13.5 s captured**, **5.439 s Send-to-final**. Real tutor completed (9.685 s Send-to-reply); native output event at 10.106 s. No recorded memory warning, serious/critical thermal state, provider attempt or monitored model-failure event.
- Visible raw recognition was **`I bought 3 apples on Tuesday.`** Frozen reference was **`I bought three apples on Tuesday.`** Only case/punctuation/whitespace equivalence was predeclared, so this run is **FAIL**, not a retroactive pass. Recognition is meaningful actual acoustic evidence, but Stage 3 is not complete. Any later number-equivalence rule must be declared before a new separately bounded attempt; preserve this failed result.
- A second concrete harness defect: with expanded diagnostics scrolled down, teardown's one-direction `reveal` could not reach End above it. Automatic cleanup therefore reported FAIL. Host stopped owned playback/console/test processes, and subsequent **settings-only recovery `20260927-210744-27203` passed**, restored Traditional Chinese through UI and confirmed no phone process. Failed-run `reviewed-result.json` preserves the original failure and links recovered cleanup PASS. This scrolling/exception-safe restoration gap must be fixed and safely qualified before promoting the acoustic runner.
- **No automatic acoustic/model retry after this actual recognition failure.** Stage 4 multi-turn/relaunch/cancellation/fresh-repeat work is not implemented or run. Stage 5 is incomplete despite host safety checks and successful bounded settings recovery. Stage 6 has a Make entrypoint and qualified baseline instructions, not a fully qualified voice suite.
- Final state: all owned playback/capture/test/console processes stopped; original app language restored, assets/caches/history retained (synthetic records kept). User-selected Mac 50% unmuted unchanged by the agent. No room capture. Baseline greeting/reply audibility is human-confirmed; this acoustic reply has no separate listening confirmation. Mural QA alone was deleted with explicit authorization. No simulator run, commit or push.

### User accepts number rendering; cleanup correction awaits unlock

- User explicitly accepts `3` versus `three` and considers acoustic recognition passed. Stage 3 is now **PASS with human-approved numeric equivalence**, supported by the existing real capture/frame/turn/model evidence. The original automated exact-text failure is retained; it is not rewritten as an originally passing assertion. Acoustic-response speaker audibility remains separate/unconfirmed.
- Future predeclared normalization now permits the exact token `3` = `three`, in addition to case/punctuation/whitespace. No other words are removed or changed.
- Corrected native `reveal` to scroll toward the target's actual frame, not always downward in content. Added a model-free recovery regression that opens/scolls diagnostics, returns to its header and restores the known original meaning preference. This is not yet device-qualified.
- Signed preparation PASS: `20260927-211217-38080`. Included tracked `Core/` sources in the preparation fingerprint alongside app/tests/configuration. Runtime recovery qualification `20260927-211245-39317` refused because the physical phone requires unlock; no install, launch, model work or playback occurred. Keep-awake is intentionally limited to active app preparation, never a global phone-security setting.
- Next necessary human action: unlock the connected phone without opening Mural. Then run the model-free cleanup regression before implementing/running Stage 4. No new acoustic run was triggered just to turn the accepted numeric result green.

### Cleanup navigation qualified; two-turn persistence implementation

- Model-free cleanup regression **PASS**: `.build/verification/physical-iphone-e2e/20260927-211516-44725/`. Native test opens and scrolls diagnostics, navigates back toward the offscreen header, restores Traditional Chinese and terminates. No Prepare/model/microphone/playback. Signed runner, exact result and cleanup PASS. A resident Mural process after unlock was identity-checked and terminated only within the confirmed exclusive test window; evidence in `20260927-211417-42246/residual-*.json`.
- Added opt-in `multi`: two distinct actual acoustic turns, real completed replies, exact observed text/count/order in Transcript, normal app terminate/relaunch, then only the newest synthetic On-device history record. Prior model phase must finish and End/drain before the console is allowed to exit for persistence-only relaunch. No startup fixtures or reset.
- Second frozen local Samantha/rate-150 fixture: `My appointment is tomorrow morning.`, SHA-256 `7bc34a03703de4a571c7298e4d8b693e5dc7b8c537e49ea94f753a1f084a96e5`. Future corpus normalization declared before the run: case/punctuation/whitespace and token `3=three` only; second sentence otherwise exact.
- Before implementation, expanded host failure checks for missing second capture and zero second-turn frames. Production verifier now requires expected count, distinct UUIDs and each turn's own ordered capture/send/input/final evidence. Per-turn host playback records retain receipt/start/end/exit; stale UI markers cannot trigger a subsequent fixture.
- Host checks PASS. Two-turn device execution, fresh repeat, audible-output confirmation for those runs and cancellation/recovery scenario remain pending. This is not a Stage 4 completion claim.

### Workflow efficiency correction and final qualification

- User requested reusable scripts and investigation of repeated Make failures. Consolidated evidence inspection, compiler proof reuse, prepared-build selection, read-only status and exact-PID idle termination into the checked-in `scripts/verify_device.py`, with `make agent-device-report`. No more repeated inline Python for those operations.
- Separated real safety refusals from test failures. Runtime failures now automatically save/print the compact xcresult summary and focused assertion location, plus cleanup. Preparation does not demand an unlocked screen; runtime still does. `status` never installs/launches. `stop-idle` requires the exact freshly inspected, human-confirmed idle PID and matches it to the installed main bundle under the lock; no automatic killing of personal work.
- Fixed incremental preparation: reuse actual compiler-command proof only when the app executable hash is identical. Do not touch source timestamps, clean caches or rebuild to recreate an already-proven command. Runtime automatically chooses a matching device/source/artifact receipt; explicit `DEVICE_PREPARED` remains optional. Host script identity is recorded separately from compiled inputs, so host-only changes no longer force app recompilation.
- Prewritten helper checks cover proof absence/changed bytes, wrong source/device receipt, incorrect/ambiguous idle PID, missing/skipped results, fresh-process event correlation, missing/duplicate/wrong acoustic turns, nonzero frame evidence and timeout process cleanup. They pass. Ordinary builds/default simulator verification remain unchanged; no new dependency or broad device service.
- Two-turn attempt `20260927-212718-73135` reached both real replies and exposed a global accessibility-query mistake: Talk's latest learner text remained behind the transcript sheet, causing a false duplicate. Scoped exact text/count/order assertions to the transcript ScrollView; no weakening of duplicate detection. Attempt `20260927-213229-86206` then passed the actual persistence assertions but exposed ambiguous nested-sheet `Done` buttons. Scoped dismissals to `Our conversation` / `Past conversations`, including teardown. Both failures are preserved; neither was labeled a model defect or silently retried unchanged.
- Model-free recovery regression **PASS** at `20260927-213804-99776`: expanded/scrolled diagnostics, nested synthetic history/transcript dismissal, preference restoration, process shutdown. The failed run's preferences were restored before further model work. Recovery now requires `DEVICE_RESTORE_MEANING` from recorded original state, not a hardcoded language. Native tests log that original preference.

#### Final passing runtime evidence

All paths below are under `.build/verification/physical-iphone-e2e/`:

| Scenario | Run | Automated outcome | Whole command including cleanup |
| --- | --- | --- | --- |
| Two distinct acoustic turns + replies + exact saved text/count/order after normal relaunch | `20260927-213906-2903` | PASS, 1 test, 0 failures/skips; cleanup PASS | 207.3 s |
| Fresh repeat, same frozen bytes and retained caches | `20260927-214250-12298` | PASS, 1 test, 0 failures/skips; cleanup PASS | 214.5 s |
| End during recording, drain, distinct new conversation | `20260927-215132-33287` | PASS, 1 test, 0 failures/skips; cleanup PASS | 163.3 s |

- Cancellation deliberately stops the first recording before Send. Its UUID has no Send/final/audio event; End precedes the next distinct capture. The fresh appointment turn completes with exactly one learner passage in the new saved transcript. This proves **recording cancellation/recovery**, not cancellation during encoder/decoder/tutor inference or a background lifecycle matrix.
- Both main runs use real iPhone microphone input from Mac `say`/`afplay`, actual staged Core AI ASR, real tutor and retained TTS. Native exact transcript assertions and attachments prove both observed learner/assistant texts persisted once and in order after relaunch. No preview, injected transcript or fake response. No resource/thermal/model-failure event in the passing scoped logs. These are bounded observations, not continuous physical-temperature or memory-peak measurements.
- **Human audible-output confirmation:** user explicitly heard both iPhone tutor replies in both successful main runs, distinct from Mac input, and reported “Everything is all good” when asked about overheating, unexpected late speech and audio problems. This is human-confirmed speaker output, not automated room-audio analysis or a linguistic/teaching-quality assessment. No room audio was captured.
- Failure handling qualification includes actual locked/resident-device refusals, signing-slot refusal, missing permission/readiness, strict text failure with stopped playback, corrected transcript/cleanup UI failures and separate model-free recovery; host checks exercise bounded timeout and false-pass guards. No destructive physical disconnect, deliberate thermal/memory stress, SIGKILL/host-crash recovery or all possible permission/routing failures were induced. Those remain explicit limits; do not extrapolate this representative qualification to them.
- Shared native helper fixes were verified through the affected model-free recovery and full runs. The final cancellation branch adds no change to the already-passing multi-turn behavior or production model/UI paths, so no duplicate full model replay was performed merely for that separate branch. No simulator runs were needed for this explicitly physical harness track; simulator policy remains separate.
- Updated the verification skill with qualified opt-in commands, fresh fixture recipe, data/privacy gates, numeric normalization, evidence/results, idle-PID handling and recovery. Preserved unrelated simulator-policy edits and externally staged work. No commits or pushes were performed by the agent.

#### Final closeout

```text
Native device control: PASS
Intended backend / real execution: PASS, scoped Core AI GPU staged ASR + real tutor/TTS
Acoustic input / recognition: PASS (predeclared numeric equivalence in final runs)
Tutor / state / persistence: PASS, two distinct turns plus fresh repeat
Audible output: human-confirmed for both replies in both main runs
Native lifecycle: End during recording, drain, new distinct session PASS
Owned playback, console/capture and test processes: stopped; saved cleanup PASS
Settings/data: original meaning language restored; user-controlled Mac volume unchanged
QA app: deleted only with explicit user authorization; main bundle/assets/caches/history retained
Cleanup: PASS for final runs; failed attempts and separate recovery evidence retained
Simulator optimization: separate plan; not run or changed by physical qualification
```

## Progress log

### Planning extension

- User proposed Mac-generated audible speech with a connected, nearby iPhone and requested it be included in the verification plans.
- Chose two linked tracks so simulator memory cleanup is not coupled to physical-model/audio feasibility.
- Confirmed existing Mural capture-start/turn/frame events provide a starting point for host synchronization; delivery timing and automation compatibility remain unverified.
- Defined qualification before promotion, real-microphone and real-model evidence, output-speech limits, resource stops, privacy boundaries and owned-process cleanup.
- Updated documents only. No scripts implemented, tests run, sounds played, microphone capture started, phone installed/controlled, or model loaded. Stages 1-6 remain pending.

### Documentation and efficiency follow-up

- Consolidated qualification lessons and measured runtime-command baselines in [physical E2E lessons](physical-iphone-e2e-lessons.md). Build time is separate; no speedup is claimed from documentation changes.
- Added concise physical acceptance policy to AGENTS and affected-behavior stage selection to verify-mural. Real phone execution is primary for microphone/models/audio/native lifecycle; simulator UI and guards remain useful and separate.
- Documented preparation-first readiness, saved Make/report operations, model-free harness recovery and distinct automated/human/unverified results. Routine checks no longer read as a mandatory baseline/acoustic/multi/cancel sequence.
- Ordered pending work: accessibility-query efficiency, playback-completion synchronization, phase timing, then matched qualification. These are not implemented or qualified by this documentation pass. No phone tests, builds, recordings, commits or pushes were performed for it.

### Runtime optimization started

- User authorized implementing and qualifying runtime optimizations. Measurement comes first so later comparisons retain identical scenario/assertion coverage.
- Added host phase durations and separate native uptime markers, without changing test actions, fixed recording windows, matching rules or production app behavior. Prewritten host checks first failed for missing timing helpers, then passed after implementation.
- Fresh discovery/status found the paired iPhone 17 unlocked and no Mural process. Read-only status evidence: `20260927-223301-21307`, cleanup PASS. No mirroring/build competition was observed in the scoped process check.
- Signed instrumentation-only preparation: `20260927-223510-26248`, build/cleanup PASS in 19.59 s, unchanged app executable with reused compiler proof. Evidence paths are under `.build/verification/physical-iphone-e2e/`. Native timing and speed improvements are not yet qualified; no installation or acoustic run occurred. Next: confirm one private audible window, capture a fresh unchanged-behavior baseline, then optimize and compare.

### Runtime optimization qualification in progress

- User confirmed the audible window. Fresh instrumentation-only `multi` baseline `20260927-225903-58902` passed real recognition/replies, exact relaunch persistence and cleanup in 221.25 s. Two native recording waits were 12.09 s each. Human listening for this new batch remains unconfirmed.
- Physical helper loops now return/break once a target is hittable rather than reevaluating remote accessibility predicates for every remaining iteration. Scrolling limits and outcome assertions are unchanged. Model-free navigation/restoration `20260927-230400-72070` passed.
- Added a current-run/current-turn random-token acknowledgment: only after successful bounded `afplay` completion, host copies the token into the XCTest runner's temporary container; XCTest waits for the exact token, then retains a 0.75 s trailing margin. No production app changes, transcript injection, service or backend changes. Missing/wrong/late acknowledgments never release Send. Host failure checks were written first and observed failing before implementation.
- Initial model-free transport probe `20260927-230721-80896` failed because devicectl requires a minimum five-second timeout. No audio/models ran. Original cleanup remains unconfirmed, not relabeled PASS. Direct status `20260927-230814-82881` confirmed no Mural processes; corrected transport/settings recovery `20260927-230817-83126` passed with cleanup PASS. The probe uses stale test-token content before the matching fresh acknowledgment.
- Single actual acoustic turn `20260927-230906-84796` passed real recognition, reply and saved transcript with cleanup PASS in 105.48 s. Native recording wait was 4.40 s versus the baseline's 12.09 s; this is not yet a full-scenario speed comparison. Prepared test build `20260927-230704-80071` preserves identical production app executable bytes. Next: identical multi-turn/persistence and fresh repeat, plus cancellation because its recording path shares the handshake.

### Runtime optimization automated closeout

- Optimized identical `multi` scenario `20260927-231126-90382`: **159.02 s**, fresh repeat `20260927-231413-97363`: **157.55 s**, both one passing native test, zero failures/skips, real acoustic recognition/replies, exact text/count/order after relaunch and cleanup PASS. Fresh instrumented baseline was **221.25 s**. Mean optimized runtime **158.28 s**, saving **62.96 s / 28.5%** in this small sample, not a latency distribution or inference-speed claim.
- Distinct cancellation `20260927-231701-4101`: **126.84 s**, PASS. End during the first recording produces no Send/final/audio for that UUID; drain precedes a fresh distinct recording with exactly one learner passage saved. No inference/background cancellation claim.
- Same production executable, runtime/backend, frozen speech, normalization and scenario assertions. Mac built-in speaker volume was 56 unmuted throughout this comparison, unchanged by the runner; retained assets/caches and original Traditional Chinese meaning preference preserved/restored. Native recording waits fell from 12.09 s each to 4.46-5.20 s in the matched optimized runs. Preparation/inference and XCTest overhead also vary; not all whole-command savings are attributed to the patch.
- Separate signed preparation was 19.59 s baseline / 16.39 s final optimized build; excluded from the runtime numbers above. No skip-install shortcut, backend change, model transfer, fake response, transcript injection, mirror, room recording or simulator test was used.
- Final host safety checks and diff checks passed. Scoped process inspection found no owned playback/console/test process remaining; each final physical run saved cleanup PASS. The failed timeout-argument probe and separate recovery remain recorded rather than overwritten.
- Evidence closeout: `.build/verification/physical-iphone-e2e/runtime-optimization-20260927/result.md`. Updated lessons and verification skill with the qualified mechanism and boundaries. **Automated runtime acceptance complete; human audible-output confirmation for this new batch is still pending.** No commits or pushes.

### Human confirmation and further opportunity review

- User explicitly confirmed: “Yes, I did hear both iPhone replies in each final two turns run.” Saved `human-acceptance.json` beside `20260927-231126-90382` and `20260927-231413-97363`. This closes the final runs' audible-output gate; no separate assertion about unusual heat, late speech, teaching quality or automated room-audio analysis is added.
- Reviewed existing timing, app and XCTest logs only; no new playback, capture, installation or test. The 28.5% observed improvement is not a proven ceiling.
- Found a concrete next investigation: both optimized runs reject a staged-decoder preparation receipt as incompatible and spend 16.07 / 14.63 s prewarming again. The key includes an absolute model-path hash, so install-related relocation is a candidate, not an established cause. Preserve all invalidation/asset/backend checks while diagnosing the differing key field.
- Also identified redundant setup Settings visits, repeated settled-transcript queries and project package resolution during test-without-building. Details and priorities are in the lessons document. These are investigation proposals, not implemented changes or promised gains. Main install cost alone is only about 1.8 s; real speech/model waits are not disposable test overhead.

### Follow-up priorities and checkbox regression reproduced

- User approved all four saved-evidence priorities and reported checkmarks reverting just before initial speech. Existing audible-window authorization carries forward; no room audio capture. Prior user changes remain intact.
- Native baseline reproduction `20260927-233637-48547` failed exactly at the new monotonic-checklist assertion: checking and voice became unchecked during greeting synthesis. Saved XCTest screen video and inspected `before-transition.jpg` show the transition, not just the final state. Real preparation/greeting ran; the test stopped before a typed turn. Cleanup PASS and original preference restored.
- Receipt investigation of commit `3a2734c` found its absolute-path identity is the issue, not absent implementation. Read-only runs `20260927-233523-44845` and `20260927-233817-52481` captured only app metadata and the known content-free decoder receipt. In-place installation changed the data-container UUID. The manifest, model, device, OS, compute and policy fields stayed identical; only `modelPathSHA256` changed, exactly matching each absolute container path. Reproduction paid 21.88 s for decoder prewarm again.
- Failure analysis and isolated checks preceded production changes: sandbox relocation must reuse identical verified assets, while different in-container locations, external paths, symlink escapes and all existing specialization inputs invalidate. The new checks first failed for missing production path-identity support. Implemented canonical sandbox-relative identity with absolute fallback and policy 2; legacy receipts safely miss once. Full asset verification and actual load/contract validation remain mandatory, including receipt hits.
- Root UI correction leaves `.preparing` synchronously before greeting synthesis suspends; actual `.speaking` still waits for playback. It does not retain stale completed steps during genuine background re-preparation or expose Record early.
- Native runner now copies the fingerprinted prepared `.xctestrun`, resolves its original product root, preserves signed identities/settings, injects only stage/acknowledgment environment, and retains native screen attachments. Host rejection checks passed and the physical reproduction exercised this launch successfully, without project package resolution. The original prepared manifest is untouched.
- Implemented one initial Settings visit with original preference recorded before mutation, and one settled transcript snapshot for exact label counts/order. Actual visibility scrolling, restoration readback, normal relaunch and real acoustic/model assertions remain. Signed build and passing affected physical acceptance are pending; no new speedup or fix acceptance claimed yet.

### Follow-up first acceptance gates passed

- Targeted receipt/setup checks: 26 PASS; host safety/launch-plan checks PASS. Signed production/runner preparation `20260927-234638-75017`: PASS, 40.64 s including cleanup. Model-free Settings/diagnostics/nested-sheet/acknowledgment recovery `20260927-234724-76844`: PASS, 46.26 s, original Traditional Chinese restored.
- Real typed baseline `20260927-234817-79128`: PASS, checklist never regressed, normal real reply and saved transcript, cleanup PASS. Policy migration correctly misses once and writes the new receipt after validated loading. Native screen movie fully decodes; overview shows completed checks retained until the card exits directly to greeting synthesis, rather than reverting.
- One actual acoustic turn `20260927-235040-84887`: PASS, exact predeclared recognition, real reply, saved text and cleanup in 98.47 s. Installation moved the sandbox again but the preparation receipt now hits; prewarm is skipped and mandatory model load/contract validation still runs. No model/resource fault or backend change.
- Important measurement limit: the receipt hit still spends **15.18 s in the actual native decoder load** after installation. Eliminating the redundant explicit prewarm does not prove the same number of seconds disappeared; Core ML may still do native work during loading. Preserve that gate and report actual whole-scenario timings rather than claiming hypothetical savings.
- Current native baseline/acoustic speaker audibility is not yet human-confirmed. Two-turn/relaunch, fresh repeat, affected recording cancellation and dense transition inspection remain pending. No simulator or room recording was used.

### Follow-up complete: all four priorities and checklist fix qualified

- Two full actual acoustic/model/relaunch runs **PASS**: `20260927-235312-91141` **155.96 s** and `20260927-235628-99584` **152.56 s**, each including cleanup, exact text/count/order and the new checklist regression guard. Distinct recording cancellation/drain/new-session run `20260927-235929-7127`: **PASS, 128.96 s**. No retries, backend changes, simulator work or room recording.
- Mean full runtime **154.26 s**, versus prior optimized **158.28 s**: observed **4.02 s / 2.54%** reduction. This retains and expands scenario assertions, but adds checklist sampling/video and changes production code, so it is not an isolated identical-instrumentation comparison. Do not promise another 15-second saving: receipt hits still took **19.40 / 16.54 s** in mandatory first decoder loads. Cancellation's first load was 25.17 s. All hits still passed actual native loading/contract checks and real subsequent inference.
- Strict source decode PASS: pre-fix recording 1,604/1,604 frames, 59.818 s; corrected recording 2,351/2,351 frames, 90.882 s; both decoder-error logs empty. Inspected before **40-42 s** and after **43-45 s** at 12 fps, plus corrected **35-50 s** overview through Speaking. Completed checks no longer reset before greeting synthesis. No broader layout/large-text/background claim.
- User explicitly answered **“Yes, both iPhone replies in both runs”** to the new full-run listening question (11:53 pm and 11:56 pm starts, before cancellation). Saved separate `human-acceptance.json` in both runs. This is human-confirmed output, not automated acoustic-output analysis, and adds no unasked heat/late-speech/teaching-quality claim.
- Clarified the Settings optimization after user questioned whether it was applied: it is implemented in `meaningSetting(..., preservingOriginal: true)` and exercised by both full runs. Repeat native log shows one initial Settings entry at **1.49 s**, Vietnamese selection at **4.17 s**, Done at **5.91 s**, then Prepare. Later entries at **129.02 / 135.17 s** are restore and independent readback during teardown, not redundant setup. Retained this evidence in `followup-20260927/settings-visits.txt`.
- Updated AGENTS, verification skill, physical lessons and native animation instructions. Existing thin Make entrypoint was reused successfully throughout; no extra Makefile, services, dependencies or inline Python workflow. All owned host/phone playback, console and test processes stopped; saved cleanup PASS. Original Traditional Chinese preference restored; main bundle, assets, caches, history and user-controlled volume retained. Unrelated/staged work preserved; no commit or push.
- Final evidence: `.build/verification/physical-iphone-e2e/followup-20260927/result.md`, with comparison JSON, tests-first receipts, UI videos and links to each native result. All four approved priorities are implemented and qualified. Investigating remaining native first-load latency or safely avoiding installation is future work, not an incomplete part of these four changes.

## References

- [Simulator lifecycle and SimSlim plan](simulator-verification-lifecycle-plan.md)
- [Mural verification skill](../.agents/skills/verify-mural/SKILL.md)
- [Current paired-phone build and local-conversation instructions](../.agents/skills/verify-mural/features/local-conversation.md)
- [Core AI backend and normal Talk checkpoint](coreai/gpu-talk-checkpoint.md)
- [First-turn readiness/prewarm boundaries](coreai/first-turn-readiness-prewarm-plan.md)
- [Apple: native UI automation](https://developer.apple.com/videos/play/wwdc2025/344/)
- [Apple: iPhone Mirroring microphone restriction](https://support.apple.com/en-us/120421)
- [Apple: Device Hub physical microphone conflicts](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub)
