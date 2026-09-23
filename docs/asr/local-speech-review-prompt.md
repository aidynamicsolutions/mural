# Next-agent prompt: independently review and resolve local speech findings

Copy the prompt below into a new agent working with the **current working candidate**, not only the Git branch's committed HEAD. The findings document is sanitized; private device/audio/model artifacts must not be uploaded with it.

---

You are reviewing `aidynamicsolutions/mural` on branch `mvp`. Independently verify the previous agent's changes and findings, reproduce the important problems, and implement the smallest safe fixes supported by evidence. Automate as much as possible. The owner has already spent time on preliminary speech checks; involve them only for a brief unlock or genuinely missing speech/listening/Traditional Chinese judgment.

## Read first

1. Repository `AGENTS.md` and applicable instructions.
2. `docs/asr/local-speech-findings-handoff.md` - consolidated facts, evidence levels, code-change ledger, source/executable identities, cancellation UX and open questions.
3. `docs/asr/speech-setup-ux.md` - later implemented Start/consent/progress flow, cancellation feedback, source/build identities and automated-test boundaries. Also read `docs/asr/local-speech-qa.md` - existing QA runner, physical results, exact build/launch/copy commands and limitations.
4. `docs/asr/taiwan-talk-implementation-plan.md`, `docs/asr/model-distribution-release-plan.md`, `docs/asr/app-store-model-provisioning-release-blocker.md`.
5. `.agents/skills/verify-mural/SKILL.md`, its `features/local-conversation.md` and `features/ui-animation.md`, plus `docs/coreai/gpu-talk-checkpoint.md`. Apply Swift concurrency/SwiftUI guidance when reviewing those paths. Older notes describing the default backend are historical: inspect current source and runtime selection.
6. If available locally, original `.build/handover/mural-taiwan-delivery/REVIEW_AND_STATUS.md` and `VERIFICATION.md`. Read existing scoped evidence before requesting a replay.

Start with `git status --short`, `git branch --show-current`, `git rev-parse HEAD`. Recorded base is `3bae86c34072c088454afe5b235802a76b6e2c3b`; candidate and follow-ups are still uncommitted, including new files. Read **all** resolved changes and new source/tests/tools, including staged changes with `git diff HEAD` and any remaining untracked files. Leave existing staging intact. Do not reset, overwrite dirty work, reapply the original bundle, regenerate the project or treat a different/newer HEAD as permission to discard it.

If you are an online agent without this working tree or the Mac/phone evidence, identify the exact missing inputs. Review supplied sanitized source and reported measurements as such; do not claim to have reproduced native behavior. Request a source-only transfer, not personal audio, broad device logs, model binaries or credentials.

## Accepted work and remaining investigations

**Next work:** local installer fault/recovery (D) and safety-monitor/coordinator replay (C) are complete. The owner explicitly deferred language-quality work (E); preserve the known finding but do not investigate it or request audio under the current scope. TestFlight/App Store clean-install qualification is parked because the owner is not ready to enroll in the paid Apple Developer Program. Do not request enrollment or begin distribution qualification until the owner says they are ready. Hosting is separately deferred; when the release gate resumes, use owner-approved hosting inputs and complete the required artifact, license, storage and clean-install checks. Do not restart accepted cancellation-latency tuning.

### A. Cancellation follow-up: complete and owner-accepted

Read `docs/asr/speech-setup-ux.md#accepted-cancellation-follow-up` before interpreting the older 195-second result. The owner accepts the observed roughly **15-19 second cancellation drain after development reinstall** and asks to move on.

Latest physical ASR-owner runs all passed:

- Breeze decoder prewarm: **19.315 s** drain; **141.030 s** retry to Ready, including the skipped encoder preparation.
- PhoWhisper decoder prewarm: **15.403 s** drain; **4.282 s** retry.
- Cached fresh-process decoder loads: Breeze **1.538 s** drain / **3.559 s** retry; PhoWhisper **1.278 s** / **3.336 s**.

`SpeechPreparationStep` and `CancellableWhisperModel` check cancellation around individual native component loads. Cancel does not start following work after the current call returns. Talk shows **Setup cancelled** without a stopping spinner; Words, Settings and next-pair selection remain usable. Pair selection does not launch a model. Start, mode changes and the diagnostic probe remain gated until real drain. Eight simulator UI checks and inspected recordings complement the four native reports. The daily Release was installed in place and launched with the expected staged backend.

Preserve these changes rather than reimplementing the previous proposal. The accepted observations are not a maximum wait or complete first-use setup time, and the two verification surfaces do not establish full native phone UI/VoiceOver or every coordinator/audio phase. Address a concrete new regression or remaining coverage gap, not speculative extra latency optimization. No further phone checklist is needed merely to close this task.

Never unlock a busy owner on a timer, drop ownership early, detach untracked native work, start a second recognizer, force-exit the shipping app or skip model validation.

### B. Receipt identity and reinstall behavior

Current receipt code/tests match HEAD: absolute standardized model path, policy version 1. A previously authorized relative-path/policy-2 experiment was reverted. It yielded a receipt hit after development reinstall, yet normal Core ML loading still ran for **177.693 s before cancellation**, then retry reached Ready in **4.628 s**. This establishes that a receipt hit alone does not eliminate native work, not the exact internal cause.

Warm engine preparation without another reinstall measured Breeze **4.411 / 3.470 s** and PhoWhisper **4.576 / 3.029 s**, fresh-process then same-process. Do not promise setup only once for the app lifetime. Reinstalls, OS/artifact/policy changes and native-cache loss may require work again.

No receipt change is needed for the accepted cancellation closeout. Earlier authorization for justified corrections is not a reason to repeat the rejected experiment or reopen latency tuning without a concrete regression/new requirement. Preserve actual compute-unit identity, full asset verification, authoritative normal load/shape/type validation, decoder-only staged receipt scope, and explicit trial always/once/no-auto-rebuild policy. A receipt never vouches for Core AI cache existence. If investigating a new failure, measure complete time to Ready, not just prewarm count.

### C. Responsiveness/safety-monitor and lifecycle review complete

`startTTSConversationMonitor` was moved off MainActor and slowed from 100 ms to 1 s sampling; the owner reports smoother UI. The post-sample cancellation guard was independently reviewed and replayed with a deliberately suspended over-threshold sample across Stop/restart. The stale result did not stop the replacement monitor; a fresh injected memory footprint and current serious-thermal state still invoked safety stops. The app remains with one ASR/TTS owner; a canceled read-only detached sample may finish after Stop.

Simulator coordinator checks passed for setup drain/admission, navigation/pair selection, background/retry, thermal pause/explicit Resume, and accessibility-sized cancel/consent controls. Exact commands and evidence are in `docs/asr/local-speech-qa.md#safety-monitor-delayed-sample-and-lifecycle-replay-2026-09-23`. Do not call this a physical native teardown test. Real memory pressure/thermal qualification, phone scrolling profile and VoiceOver spoken announcements remain unverified. One-second sampling is not a hard memory ceiling. Never deliberately overheat or exhaust the owner's phone.

### D. Local installer fault-test tranche complete; keep distribution dependencies honest

The empty production catalog and missing primary/backup failover remain. On 2026-09-23, `Tests/SpeechInstallerTests.swift` exercised the shared installer transaction core with `URLProtocol` and disposable directories: exact range resume after network loss/cancellation and a fresh invocation, full-object `200`, invalid manifest pin/file hash, denied storage, read-only file-open failure, injected failure before pointer publication, recovery from an already-moved immutable directory, and retention of the old active package. HTTP tests also reject unreviewed redirects; package tests cover canonical metadata, paths, ranges and independent pins. Full `swift test` passed 62 checks; related Python checks passed 6 package and 16 Core AI checks. The focused unavailable-catalog simulator UI test passed.

Evidence: `.build/verification/speech-installer/20260923T025140Z/` and the detailed limits in `docs/asr/local-speech-qa.md`. These tests share the production transaction core but pass synthetic file plans after the production wrapper's full metadata validation. They do not simulate an actual OS process kill, real ENOSPC, failure inside the atomic pointer write/rename, real CDN behavior, backup failover or a customer clean install. No package was hosted and no release catalog was populated. Keep those P0 gates open; don't clear valid installed versions, learning data or Apple private caches.

Hosting and paid Apple Developer enrollment are deliberately deferred by the owner. Do available local work now; do not ask for those details merely to proceed with unrelated tests. No invented production URL, whole-package hash or storage reserve. No spending/publication/signing-team changes. Keep the P0 document open until real hosted, selected-mode-only downloads, independently reviewed pins, native reserves and intended distributed clean-install evidence exist.

### E. Owner-deferred: preserve Taiwan language-quality limits

The owner explicitly said not to investigate the mixed Mandarin-English model recognition failure in this work. Keep the known failure documented, do not generate/replay audio or change recognition behavior, and do not turn prior pure-language/support checks into universal bilingual or Traditional Chinese qualification. Revisit only on a future explicit request.

If reauthorized later, use reusable consented inputs and assess raw-ASR fidelity separately from Traditional Chinese teaching/script. Keep one Breeze turn, exact raw provenance, typed-input provenance absent, English practice speech, on-screen Chinese Help and disabled Taiwan automatic learning credit. No post-ASR translation/script correction or word-level model routing to disguise recognition errors.

## Execution constraints and existing tools

- Preserve daily **`com.kevintruong.mural.dev`**. Use **`com.kevintruong.mural.qa` / Mural QA** for fault injection and native diagnostics. Existing QA has Mac-staged models, so it is not a clean customer install.
- Discover device/OS again. Last tested iPhone 17 / `iPhone18,3`, iOS 27.2 (`24B5084k`). Do not assume an old UDID/PID is current.
- Follow `local-speech-qa.md` for build/run instructions. Physical QA requires `MURAL_LOCAL_QA`, exact QA bundle and `--local-speech-qa`; supported actions are `missing`, `prepare`, `cancel`, `memory`, for `pho` or `breeze`. Do not run the missing-assets assertion against the currently staged QA container and call the resulting failure a product bug.
- Current `.build/local-mvp-phase-1-device-derived-data/Build/Products/Release-iphoneos/Mural.app` is **QA**, not a daily build. Verify bundle, compiler invocation and executable hash before installing. Leave tracked Info.plist/signing unchanged.
- The runner uses the real ASR owner, not the coordinator, microphone, tutor or learning store; its explicit Apple-voice setting isolates ASR. It replaces `Documents/local-speech-qa.json` each launch. Copy reports immediately and check action/model/run ID plus terminal status, not just successful launch. Its watchdog cannot forcibly stop non-cooperative native work.
- Mac Apple Events input was blocked by permission `-1743`. Use available simulator/native checks and the existing runner first. Do not silently grant permissions or consume another signed-app slot. No tester subagents.
- The setup-only phone logging blocker was resolved in the cancellation follow-up. Saved scoped logs contain all four native runs and the final daily launch's staged-backend event. Captures/recorders are stopped; start or reuse a freshly verified scoped capture only when a new phone check is actually needed.
- Capture only scoped Mural evidence with ownership/start offset and bounded duration. Quit Device Hub fully before microphone checks. Stop only your capture/processes. Keep raw evidence private under `.build/verification/`.
- Local checks after relevant corrections, then full supporting batch before handback:

```sh
swift test
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tools/ASR -p 'test_speech_package_tool.py'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest Tools.CoreAI.test_asr_final_review
git diff --check
```

For new app-code changes, build the ordinary app without the QA flag as well as any needed isolated device candidate. Do not weaken tests to hide failures. Latest cancellation batch: 147 Swift, 6 package and 16 Core AI checks, 8 simulator UI cases and 4 physical cancellation/retry runs passed. Documentation closeout reran 27 focused cancellation/progress/receipt checks without an unnecessary reinstall. The 2026-09-23 installer tranche then passed the full 62-test Swift suite, 6 package and 16 Core AI Python checks, and one focused unavailable-catalog simulator UI test. It exercises synthetic file plans through the transaction core, not hosted artifacts, an actual OS process kill, real disk exhaustion or customer provisioning. Retain earlier confirmation-tap and simulator idle/subtitle failures and their successful replays as historical evidence, not a claim of universal flake freedom.

## Completion criteria and handback

For each issue, report **reproduced / fixed and verified / not reproduced / blocked**, with exact evidence and remaining risk. Review previous-agent changes independently; passing tests are not a blanket safety endorsement. Keep UI acknowledgement latency, native drain, preparation, receipt/prewarm, normal load and cache state separate in timing tables. Include source/diff and executable identities, actual backend/pins, sampled versus lifetime memory, warnings/thermal state and post-stop admission/release observations where measured.

Update the findings/release documents with what changed and why, tests performed and unresolved limitations. Keep receipt behavior, owner-deferred Taiwan language quality, and clean-install provisioning/distribution separate. Do not investigate language quality under the current authorization. No P0 Done while external dependencies or qualification are missing. Do not stage private artifacts, `git add .`, amend receipt commits or force-push. Prepare a scoped diff for review; commit/push only under applicable user authorization and after the required checks, not just because this prompt exists.

End with a short owner-facing explanation of what is better, what can still make the app wait or fail, and the smallest next action needed from the owner. If a platform limitation prevents faster cancellation, provide evidence and the best safe UX instead of claiming the delay is solved.
