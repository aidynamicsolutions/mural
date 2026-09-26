# Resumable speech setup: implementation status

## Current status: 2026-09-26

Application integration is applied (including `07e5e85`). **Do not reapply the old handoff patch or regenerate the project for it.** The section below is historical, not current instructions.

The corrective working tree on `7d0818d95c6d3524401f93d6e157dd4c0a147e02` fixes live-setup thermal routing, preserves system-interruption Resume intent, and reserves global speech validation progress for decoder/frontend checks. Existing validation operations, models, receipts and compute settings are unchanged. Thermal recovery now has one Resume action, not duplicate buttons.

- Four new simulator E2E scenarios drive approved setup through thermal, audio-session, route and memory interruptions. Their held child is released explicitly by a preview-only control; Resume stays disabled until that return. Foreground/cooling alone does not restart; explicit Resume returns to conversation controls without another download approval.
- The 12-test arm64 UI batch passed, including the previously interrupted seven-test batch. After removing duplicate thermal recovery UI and replacing a flaky timed fixture hold, all four affected E2E scenarios passed again. Existing Core checks passed: 71 Swift Testing cases plus 26 XCTest cases, including installer/receipt checks. No new unit tests were retained.
- Corrected-source iOS Release build passed with `MURAL_COREAI_TALK` confirmed in the actual compiler invocation. This was an **unsigned generic-device build**, not installation, runtime-backend proof or signed-device qualification. Verification ran before committing: exact input is the base SHA above plus `source-final.diff` (SHA-256 `82443241dc920adbe9c13cf463bf992d6b7f17bd1e4af0ad4674eabcb94e571b`).
- Repeatable local evidence: `.build/verification/review-corrections/result.md`, result bundles, commands, source diff and exported screenshots. The encoder-local progress correction is source-reviewed and Release-compiled; the simulator checklist is synthetic and does not execute Core AI validation.
- Still unqualified: actual native drain under warning, physical Vietnamese stage ordering, continued-processing failed-submission/stale-delivery/expiration/completion-once scenarios, and signed-device continued processing. No thermal or memory stress was induced on the phone. The [memory investigation](speech-setup-memory-warning-investigation.md) remains open and separate from simulator recovery-UX evidence.

## Historical foundation-only handoff: 2026-09-24

**At this historical checkpoint the branch contained only reviewed Core foundations. The application integration described as pending below has since been applied.**

Repository: `aidynamicsolutions/mural`.
Base: `mvp` at `c67e3d302428fe79b2ecbe6664bc2cafe9c45ae0`.
Feature branch: `codex/resumable-speech-setup`.
Reviewed plan commit: `bf4e0f400697d5363b3bd36e3ebb80f938494eb6`.
Latest implementation commit before this status document: `3ab88e7721bc3529219878a7c02183f6e6c6bc4f`.

## Committed

* A bounded, versioned, atomically written `SpeechSetupJob` record, independent of conversation drafts. Identity and approval are hints; native readiness is never persisted as authority.
* `SpeechSetupControl` and a cancellation-safe foreground gate. Foreground notification only wakes an existing owner; it cannot assert that native work drained or start a second owner.
* Granular progress, download-only fractions, completed/current/pending presentation data, conservative away policy, and typed native admission/progress hooks.
* 31 focused tests across five suites for durable metadata, restoration, compatibility, storage failure, progress truthfulness, cancellation-safe wakeups, and admission boundaries.

## Evidence and limits

The 31 tests passed under Linux Swift 6.2.1 in an isolated package containing the exact new Core files, `LocalSpeechPair`, and the two new test files. This is not a full-repository test run, an iOS build, or a native-owner/device qualification. Observation remains enabled on Darwin; the Linux-only package uses the source's conditional non-Observation path because the available Linux runtime has an Observation linker problem.

The accompanying local-agent handoff supplies `mural-speech-setup-integration.patch` for the existing coordinator, engine boundaries, Talk UI, managed progress observation, continued-processing wrapper, Info.plist and UI tests. That application integration is **not applied on this GitHub branch**. Connector reads/writes worked, but source materialization was unavailable and no Mac/Xcode/device was available. Large partially fetched App files were not replaced wholesale.

Apply the supplied patch to its pinned handoff commit in a new worktree, run `python3 scripts/generate_project.py` to register the new App source, inspect the generated diff, then perform the full Mac build/unit/UI/device checks. Preserve unrelated local work and the installed app container. Do not reset, clean, uninstall, remove models, clear receipts or delete caches.

Keep every native stage foreground-only until the actual signed device/build is independently qualified. No GPU/Inference entitlement or model/backend/precision/decoding change is part of this implementation. Existing package security and native receipt/load validation remain authoritative. Model distribution remains the separate release blocker described in `app-store-model-provisioning-release-blocker.md`.
