# Mural handoff: Phase 4 accepted; Phase 5 next on request

## Phase 4 DONE: human-accepted for MVP; backup verification deferred

The user reports doing most checks and accepts Phase 4 for the MVP. **Export/reimport was not performed and is explicitly deferred**, including genuine new-record round-trip and legacy-import verification. Do not treat these as passed or require them before subsequent MVP work. The user did not identify every individual completed check; this is overall human acceptance, not agent-observed UI/audio or a credentialed premium regression pass.

### Empty preparation draft correction

- Human-reported defect: Talk > Prepare & start > End before the first greeting leaves an empty Transcript button and an empty Past conversations entry. Source tracing reproduced the cause: `startLocal` creates an unsaved empty draft; `endLocal` unconditionally saved it; Talk exposed Transcript whenever that draft was non-nil. No duplicate agent UI/audio automation was run under the paired workflow.
- Fixed the shared local teardown path: if there is no non-whitespace finalized fragment text, discard the in-memory draft rather than saving it. This covers End, background, interruption and preparation failure. Nonempty completed text, including a greeting interrupted during playback, remains saved. Existing previously saved empty records are not deleted; personal data is untouched.
- Follow-up Release 0.1.0 (1), `com.kevintruong.mural.dev`, executable SHA-256 `acf5c483591d20219802f986fd4212ed1ceee9d19d3e20cd1b9bbc4b9b8483a8`, built successfully, installed in place and launched on rediscovered Kevq iPhone 17/iPhone18,3, iOS 27.0 (24A435), UDID `00008150-000D25942278401C`. Running process confirmed at PID 28315. Same derived-data path and signing override; existing working changes preserved, no commits.
- Retained `phowhisper-cs-fp16-v1`, manifest `7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52`, prior verified runtime bytes 3,101,573,848. No model/tokenizer/decode/compute/pin changes, transfers, cache deletion or project regeneration.
- Agent checked build/install/launch/process evidence and diff whitespace. Existing interruption deprecation and missing-AppIntents metadata warnings remain. Five-second Mural-only syslog returned only `[connected]`; no functional or privacy conclusion from that incomplete capture. Owned capture stopped; Device Hub quit requested, no ongoing capture or broad device archive.
- Evidence: `.build/verification/local-mvp-phase-4/empty-draft-fix/`. The user confirms the deployed empty-draft fix is working and “all good now.” **PASS, human-confirmed.** No new agent UI/audio observation or deployment was performed for this confirmation.

**Retained regression checklist (fix now human-confirmed):** On-device > Prepare & start > End while Preparing, before any greeting text is finalized. Expect no Transcript button and no **new** Past conversations entry, also after force-close/relaunch. Old empty entries from the earlier build may remain. If the greeting was already finalized, retaining that text is intentional. No full-suite or backup replay requested.

**Next scope:** Phase 5 is next when explicitly requested: local Vietnamese Meaning (sentence tap or clear Meaning action, interaction still to decide), lookup, Help, typed replies, conservative last-user-passage assessment after End. Do not implement it merely because Phase 4 is accepted. Tutor repetition, silence/VAD, hosting, compression/ANE tuning, backup compatibility testing and Phase 6 soak remain deferred. Existing silence hallucination and evidence limits are unchanged. Wait for the next explicit implementation request.

This acceptance supersedes all earlier Phase 4 PENDING HUMAN/next/not-started headings below, including the empty-draft correction replay. Historical deployment evidence is retained.


## Phase 4 checkpoint: installed and launched, PENDING HUMAN

Phase 4 only plus the requested timing cleanup is implemented and deployed. **Stop and wait for the user's checklist feedback.** This checkpoint supersedes all “Phase 4 next/not started” instructions below. Phase 3 remains human-accepted; no Phase 5 or Phase 6 work is authorized by this checkpoint.

- Release 0.1.0 (1), `com.kevintruong.mural.dev`, executable SHA-256 `591211a88f16f6fc1855c9d774db6c87be832af22e02c8bb0b742f6ab883ff08`. Source base `1e78e5ccdf31e2e802ec254e1071072ffade5c0f` plus this uncommitted Phase 4 diff. Initial inspection saw staged Phase 3 changes; before editing, an external commit `1e78e5c` (“finish phase 3”) made the checkout clean. The agent made no commit and preserved that baseline.
- Built with `.build/local-mvp-phase-1-device-derived-data` and the bundle override, installed in place and launched on rediscovered Kevq, iPhone 17/iPhone18,3, iOS 27.0 (24A435), UDID `00008150-000D25942278401C`. Running app confirmed at PID 26857 in its newly installed bundle path. No signing, dependency, generator, model, tokenizer or decode changes; no asset transfer, cache deletion, uninstall or learning-data reset.
- Retained `phowhisper-cs-fp16-v1`, 3,101,573,848 runtime-file bytes from prior verification, manifest `7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52`. No new asset hash sweep on phone; Prepare still verifies installed files. Encoder CPU_AND_NE permitted, actual placement unverified. No download/hosting source exists.
- Finalized turns use optional `Fragment.turnID` and the existing store/archive-v2 path. Unmarked legacy/premium grouping is unchanged. User text is saved before generation; retry reuses it; only completed assistant text is appended. Separate optional playback start/end/completion fields preserve fragment identity and conservatively mark unfinished playback. End saves once, without cloud assessment or the premium close wait. History and Transcript are available; no vocabulary/competence evidence is produced.
- Talk, Settings and onboarding reuse the same mode preference. Local validates English/Vietnamese without changing history, and needs neither OpenAI consent nor a key. Ordinary onboarding now says Continue and never grants cloud consent; GPT-Live still has separate consent/key guards. Local ancillary features remain unavailable, including after End. Mode switching cancels old requests and clears stale conversation/meaning/topic UI. Cloud assessment and meaning closures reject marked local records; history views are read/edit-only and invoke no provider.
- Preparation and response timing numbers moved into **On-device details & diagnostics**. Normal Talk keeps state feedback and End while busy. Local paid-usage fields remain zero; Settings labels voice usage as GPT-Live time.
- Agent observed two successful Release builds, install, launch, running process and a bounded Mural-only launch syslog (298 lines). No OpenAI-attempt or app persistence-error events were found in that launch sample, but no local actions were exercised: this does **not** prove zero cloud attempts during conversation. Process filtering by URL with CONTAINS failed in devicectl; a normal process listing filtered locally confirmed Mural. Both outputs retained.
- No agent UI/microphone/listening automation, new tests/fixtures/frameworks, subagents, profiling, commits or publication. Device Hub was not running and quit was requested again. The owned scoped syslog process is stopped (`capture-cleanup.txt`); no ongoing capture or broad device archive. Do not signal historical PIDs.
- Evidence: `.build/verification/local-mvp-phase-4/` (`build.log`, `build-final.log`, `install.log`, `launch.log`, `device.txt`, `process-confirmed.log`, `device-events.log`, `executable.sha256`, `implementation.diff`, `result.md`). Build warnings are the pre-existing interruption API deprecation and no-AppIntents metadata warning; the initial rebuild also included the existing LiveTransport async-alternative warning.
- All changed UI, persistence/backup, local lifecycle and privacy behavior is **PENDING HUMAN**. Fresh onboarding/no-prior-consent and a genuine imported-new-ID/old-format archive replay remain unverified if the existing phone cannot expose them safely. Reimporting the same backup checks deduplication only, not new-record round-trip fidelity. Do not reset personal data to force those cases. Credentialed premium responses remain unverified.
- Known limitations unchanged: silence can invent `Để mình check lại thông tin trước khi thi.` and trigger an unsolicited reply; repetitive supermarket/store/carrot tutoring is deferred. Prior user-reported preparation about 208 s first / 6 s after relaunch and fast offline conversation belong to Phase 3, not this build's measurements. No new latency distribution, ANE placement, 20-minute soak, learning evidence or premium response pass.

### Exact next action: human phone checklist

1. **Settings:** Learning language English, Meaning language Vietnamese, Conversation mode On-device. **Talk > Prepare & start**. Expect preparation, fixed greeting, then Ready without an OpenAI consent/key prompt. If onboarding appears naturally, choose the same pair/mode and Continue; do not reset the phone to force it. Briefly choose an unsupported pair only while idle: start should explain the required pair without changing history; restore English/Vietnamese.
2. **Two exchanges:** Record `Yesterday I went to the supermarket.` > Send; wait for reply and Ready. Record `I bought apples.` > Send (try a quick second tap). End > Transcript. Expect greeting plus two separate user and two assistant turns, no duplicates/joined words. Force-close/reopen normally; **Words > Past conversations > newest On-device conversation** must contain the same five turns. No new words/competence or GPT-Live voice usage should be awarded.
3. **Lifecycle:** Prepare & start again; End once during Thinking and once during Speaking in separate short attempts. Background once during a recording. Reopen: finalized text must remain, unfinished recording must not appear, interrupted assistant playback must say Playback not completed, and no late speech/phantom recording should begin. After workers stop, switch GPT-Live then On-device: old captions/meanings/topics must clear. Language/mode changes must be disabled during local work.
4. **Premium boundary:** End, choose GPT-Live and tap the microphone. With no previous consent, expect the separate disclosure; Not now must not start. After consent, with no key, expect Settings, not a provider response. Do not remove an existing key or reset prior consent just for this check; report those cases unavailable if already configured. Return to On-device. Themes/search, Meaning, lookup, Help and typing remain unavailable locally, including after End.
5. **Safe backup/legacy check:** Settings > Export learning backup, save privately On My iPhone; then Import learning backup using that file. Existing conversations must stay unchanged with no duplicates. Reopen the new practice conversation and an existing older premium conversation. Do not delete conversations or edit IDs in a personal backup. If no safe old-format/practice-only backup exists, report the genuine new-record/legacy-import portion untested; a separate disposable installation can cover that gap later without touching personal data.
6. **Readability:** normal Talk has no timing numbers. Expand On-device details & diagnostics to find them. Confirm Preparing/Ready/Recording/Thinking/Speaking/Ended feedback and reachable End with no clipping; report exact failing action, transcript/error and screenshot where useful.

Do not repeat Phase 3's accepted ten-turn/offline suite or silence tests. Wait for feedback before further engineering or phase advancement.

## Prior plan and handoff context (superseded where noted above)

Read `mvp_plan.md` completely, repository instructions and the actual dirty checkout before editing. **Phase 3 is DONE and human-accepted. Implement Phase 4 only**, plus the timing-display cleanup specified below. This handoff supersedes old Phase 3 pending/wait instructions in historical evidence. Do not restart Phase 2 or repeat Phase 3 acceptance.

Preserve existing staged/unstaged changes, user data, cached models and evidence. No subagents, commits, pushes, publication, new hosting/services, signing changes, new test suites/frameworks, mocks or profiling infrastructure. The current session updated documentation only; Phase 4 has not started.

## Accepted baseline and known limitations

- User reports everything in the supplied Phase 3 checklist passed: mixed English/Vietnamese recognition, local tutor/TTS, readiness, offline use with Wi-Fi and cellular off, and the requested End-during-thinking/speaking checks. Attribute this to the user, not agent microphone observation. Exact transcripts, individual lifecycle traces and per-turn response gaps were not supplied.
- User describes response speed as quite fast. Initial preparation was approximately **208 seconds**, then approximately **6 seconds** after force-quit/reopen. Consistent with earlier cached preparation, not proof of the cache mechanism or guaranteed lifetime. First-use cost may recur.
- **Deferred tutor issue:** repetitive supermarket/store/carrot conversation and repeated practice of similar sentences rather than natural progression. User explicitly says not to focus on this now. No prompt/model tuning in Phase 4.
- **Phase 2 remains accepted with a known silence failure:** three seconds of silence produced `Để mình check lại thông tin trước khi thi.` A mostly silent 30-second capped turn produced the same invented text. The cap passed; silence did not. A hallucinated nonempty transcript may cause an unsolicited tutor reply. Preserve genuinely-empty-ASR handling: no user turn or tutor request. No phrase rejection, word replacements, forced language, quiet/short-speech dropping or VAD remediation.
- Earlier siêu thị, borrow/lend and occasional mixed-language losses remain historical limitations. Acceptance is for this MVP, not universal accuracy or production reliability.
- Precise latency distribution, actual per-op ANE placement, sustained 20-minute stability and credentialed premium regression remain unestablished. Do not infer them from the human feasibility acceptance.

## Installed identity and assets

- Release **0.1.0 (1)**, bundle **`com.kevintruong.mural.dev`**.
- Executable SHA-256: `bf0c54925e1edad9c0ebd742631df9fc9dcf78f3eaf90b618ae2f05ecdadac22`.
- Phase 3 source base: `ddfb703af15ec166793e3d0672374c001423ba81` plus the working-tree changes at deployment. Inspect current Git state; do not assume it is still identical.
- Last verified phone: Kevq, iPhone 17/iPhone18,3, iOS 27.0 (24A435). Rediscover its current identifier before deployment.
- Retain **`phowhisper-cs-fp16-v1`** at `Library/Application Support/PhoWhisperCS/phowhisper-cs-fp16-v1`: 3,101,573,848 runtime-file bytes excluding manifest/Core ML caches.
- Manifest SHA-256: `7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52`.
- Encoder `.cpuAndNeuralEngine`, decoder CPU_AND_NE permitted. Actual ANE execution is unverified. Keep weights, export, tokenizer and decode settings unchanged; retain other recognizer caches and load only one recognizer at a time.
- Base `vinai/PhoWhisper-large` revision `b9136a44b5f2ca664bd0b8f74baecf1715f6eeeb`; LoRA `rinhoooo/phowhisper-large-vien-cs-asr` revision `a98f55e0f42b2c4f1e71b3348a2b917fac0a7328`.
- WhisperKit 1.1.0 revision `1e2a163736dfa5a198e637ae44c114e1c6d5cc2d`; WhisperKitTools `84f77a83c8f530022ae55fbb1a64b3351ef63c7a`.
- Preserve `App/PhoWhisperTokenizer.swift`: matching local-only BPE and large-v2 control-token contract, not lexical corrections. No stock v3 tokenizer substitution.
- **No model hosting/download source exists.** Keep weights out of Git/app bundle. In-place installs should preserve assets; transfer only for a real missing/corrupt-asset blocker. External asset provenance/commands/notices: `/Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/README.md`.

## Actual Phase 3 implementation to reuse

Inspect `App/ConversationCoordinator.swift`, `App/LocalConversationEngine.swift`, `App/LocalTutorModel.swift`, `App/RootView.swift`, `App/LibraryViews.swift`, onboarding, `Core/Models.swift`, store/import/export, MeaningController and FinalAssessmentQueue callers.

- Talk has an explicit GPT-Live / On-device menu, persisted mode preference and per-session mode latch. Absent preference preserves premium. Local requires English learning language and Vietnamese support; Vietnamese already exists in `MeaningLanguages`.
- Prepare & start reuses the existing ASR owner, then speaks fixed `Hi! What did you do today?`. Record/Send captures bounded RAM-only 16 kHz mono audio, finalizes PhoWhisper, requests the bounded Apple tutor and speaks only the completed English reply. No capture during model/TTS; no VAD/barge-in.
- Existing task ownership waits for ASR cleanup before TTS and prevents new starts/mode changes/probes until cancelled workers drain. End/background stops local work immediately, with no premium five-second teardown wait.
- **Local SessionRecord is currently in memory only.** `save()` skips local records. Latest local passages are derived from individual fragments to avoid legacy grouping. No durable local turn marker exists yet. Implement Phase 4 persistence deliberately, not merely by removing the save guard.
- Local Meaning, lookup, Help, typing, themes/search and cloud assessment hooks are guarded off. Keep supporting features and all local assessment disabled during Phase 4. Do not let new persistence/finish/history hooks route local content to premium helpers.
- Preparation, Send-to-reply and Send-to-audio numbers currently remain visible throughout Talk. Component details exist in a diagnostic disclosure. Keep useful content-free logs but remove persistent timing clutter.

## Phase 4 scope

Follow plan section 4 Phase 4 and the relevant record/routing/privacy contracts in sections 7 and 8, without implementing Phase 5.

1. **Durable finalized turns and history.** Use the existing SessionRecord/Fragment/store path. Add a minimal optional explicit local-turn boundary, such as `Fragment.turnID`, and respect it when grouping. Legacy/premium fragments without the marker must retain existing behavior. Decode old archives without the field; preserve optional markers through export/import without introducing Archive v3. Do not misuse `typed` or fabricate timestamp gaps.
2. Save each finalized user turn before generation and one completed assistant reply, never streamed partials. Use consistent session-relative timestamps and preserve completed text on errors, End and background. Retry must not duplicate the user turn; stale callbacks must not append to a replaced/ended session. Track playback timing truthfully, including interruption, without duplicate assistant fragments. No vocabulary/competence evidence yet.
3. **Complete mode selection and truthful consent/privacy.** Reuse the mode enum/latch and existing language selectors/settings rather than another coordinator/provider framework. Local start/onboarding must not grant or require OpenAI consent or a key. Premium retains separate consent/key guards. Validate English/Vietnamese without overwriting learning history or allowing pair changes during an active local conversation. Use truthful preparation copy for separately installed local speech assets, not a nonexistent download service.
4. Audit all start/reply/meaning/lookup/Help/typed/topic/search/assessment/finish/background/failure call paths, including after End and cached topic entry points. Persisted local sessions must never reach a cloud closure through history, automatic translation or final assessment. Cancel old-mode jobs and clear stale UI when switching. Keep premium LiveTransport behavior intact and local paid-usage fields at zero; elapsed time is not billed voice time.
5. **Small requested UX cleanup:** remove preparation, Send-to-reply and Send-to-audio numbers from normal Talk. Keep them accessible in optional diagnostics, and keep clear Preparing/Ready/Recording/Thinking/Speaking/Ended feedback with End available while busy. No unrelated redesign.
6. Read `scripts/generate_project.py` before project changes. It owns generated Xcode files; regenerate only if needed and never hand-edit generated files. Preserve deployment target iOS 27, dependency pins, signing and notices.

### Explicitly deferred

- Phase 5: local sentence-level Vietnamese Meaning, contextual lookup, Help, typed replies and conservative last-user-passage assessment after End. Record the user's preferred UX: tap the completed English sentence or use a clear Meaning action to reveal Vietnamese without asking aloud. Decide the precise interaction later; avoid conflict with word-tap lookup. Never enable premium translation as a shortcut.
- Repetitive tutor dialogue/prompt improvements, silence/VAD, compression/ANE tuning, model distribution/hosting.
- Phase 6: full 20-turn/20-minute soak and final integrated acceptance. Do not claim these passed.

## Paired verification and stopping point

Read `.agents/skills/verify-mural/SKILL.md` and `features/local-conversation.md`. Their historical pending notes are superseded by the current plan/handoff.

**User's explicit workflow:** agent implements, builds, installs, launches and inspects build/deployment/scoped logs; user performs UI, microphone and listening tests. Do not run duplicate agent UI/audio automation, spawn testers or ask the user to run build commands. No new test suite, mocks or broad reruns. Use the existing documented replay checklist as the regression check.

- Build **Release**, reusing `.build/local-mvp-phase-1-device-derived-data`, with override `PRODUCT_BUNDLE_IDENTIFIER=com.kevintruong.mural.dev`.
- Discover phone, install in place, launch, inspect evidence. Never uninstall, erase, overwrite learning data or change signing credentials. Missing OpenAI credentials do not block local verification.
- Fully quit Device Hub before handing over. Provide a short exact checklist for the changed app, then **stop and wait**, marking Phase 4 **PENDING HUMAN**.
- Human checklist should cover local English/Vietnamese selection/start without cloud consent/key, premium consent/key boundary, two short local exchanges followed by End/Transcript and force-close/relaunch/Past conversations, separate turns without merging/duplication, safe practice backup round-trip/legacy compatibility, End/background while busy and safe mode switching, and timing cleanup/readability.
- Use safe new practice data for archive checks. Do not erase or edit the user's existing conversations. If a special compatibility fixture/disposable simulator is necessary, explain the concrete gap and keep it separate from personal data; do not create a test framework.
- Do not repeat the accepted Phase 3 ten-turn suite, model comparisons or silence checks unless a concrete relevant regression requires a focused replay. Report unverified credentialed premium checks honestly.

## Evidence, cleanup and next handoff

- New evidence: `.build/verification/local-mvp-phase-4/`. Retain `.build/verification/local-mvp-phase-3/result.md` and all earlier Phase 2 history, failed compression artifacts and GPU rollback app.
- **No active captures.** Do not signal historical PIDs. Prior Mural-only syslog returned only `[connected]`, so it did not prove zero OpenAI attempts. Existing `APIClient.post` logs attempts before the credential check; retain content-free diagnostics and never log keys, raw audio or personal transcript text.
- Apple ignores `log collect --predicate` for attached-device collection: it creates a broader device archive. Do not silently collect another. Explain scope and obtain authorization first. Logger subsystem `no.william.mural` intentionally differs from installed bundle ID.
- After deployment, update the plan, this prompt and relevant verification notes with build/model identity, actual observations versus human-pending checks, known limitations, stopped/owned capture status and the exact next action. Do not mark Phase 4 passed before human feedback. No commit/push/publication without authorization.
