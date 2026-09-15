# Local conversation feasibility probes

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

## Phase 3 accepted: human feedback and next scope

The user reports **everything in the supplied Phase 3 checklist passed** and accepts the conversation-only feasibility milestone. This is human-confirmed behavior, not agent-observed speech or a new measured benchmark. No further testing or implementation was performed in response to this feedback.

- English/Vietnamese mixed speech was recognized correctly in the user's replay; exact transcripts were not supplied. No universal recognition-accuracy claim.
- Actual local conversation worked with both Wi-Fi and cellular/4G disconnected. The user describes response speed as quite fast; exact per-turn response gaps were not supplied.
- Initial preparation was approximately **208 seconds**; after force-quitting and reopening, approximately **6 seconds**. These are user-reported totals, not component measurements. Consistent with the earlier cached-preparation pattern; cache mechanism/lifetime is not proven and first-use cost can recur.
- The user's overall checklist pass includes the requested English TTS/readiness and End-during-thinking/speaking checks; no separate detailed traces or outputs were supplied.
- **Known tutor-quality limitation, explicitly deferred:** repetitive supermarket/store/carrot conversation and repeated requests to practise very similar sentences, instead of naturally progressing or varying topics. Improve conversation progression and avoid unnecessary repetition later; do not tune prompts/models now.
- **UX TODO for Phase 4:** remove preparation, Send-to-reply and Send-to-audio timings from the ordinary Talk surface. Retain content-free diagnostics in an optional diagnostic disclosure/probe, not permanently in the conversation. Keep a clear Preparing/Ready status.
- **UX TODO for Phase 5:** provide a discoverable way to reveal Vietnamese meaning for the completed English sentence without asking the tutor aloud. Reuse the planned on-device Meaning feature; consider sentence tap or a labeled Meaning action. Preserve word-tap lookup as a distinct interaction and ensure accessibility. Translation must stay local; do not enable the existing premium translation closure. Final interaction design remains to be decided.
- Phase 2's accepted silence failure remains unchanged: `Để mình check lại thông tin trước khi thi.` was invented from silence, including the mostly silent capped turn. In the integrated loop it can trigger an unsolicited reply. Silence is not fixed or passed.
- Installed build remains Release 0.1.0 (1), `com.kevintruong.mural.dev`, SHA-256 `bf0c54925e1edad9c0ebd742631df9fc9dcf78f3eaf90b618ae2f05ecdadac22`, with retained `phowhisper-cs-fp16-v1` and ANE-capable encoder. No new deployment, capture, model change, data change or subagents.
- Evidence limits remain: no exact latency distribution, hardware placement, sustained 20-minute soak, or live premium regression established here. Prior incomplete syslog is not proof of zero network attempts. These do not change the recorded human acceptance of this milestone.

**Recommendation: Phase 4 next**, covering durable separate turns/history, mode/consent/privacy integration and safe transitions, plus the small timing-display cleanup above. Phase 5 remains local Meaning/lookup/Help/typed replies and conservative assessment. Phase 6 remains final sustained acceptance. Do not reopen Phase 3 for these additions. Await an explicit next implementation request; the current response records feedback and recommends scope only. Continue paired testing: agent builds/installs/launches, user tests, no duplicate agent UI/audio automation.

This acceptance supersedes the PENDING HUMAN/wait-for-feedback labels in the historical deployment checkpoint below.

## Phase 3 checkpoint: installed and launched, PENDING HUMAN

Phase 3 implementation is now present. The user requested stopping agent UI checks and handing over immediately for their own testing. Do not run further microphone/UI automation or advance phases while waiting for feedback.

- Release 0.1.0 (1), `com.kevintruong.mural.dev`, executable SHA-256 `bf0c54925e1edad9c0ebd742631df9fc9dcf78f3eaf90b618ae2f05ecdadac22`; source base `ddfb703af15ec166793e3d0672374c001423ba81` plus uncommitted Phase 3 changes. Starting checkout was clean; prior implementation/history preserved.
- Built using `.build/local-mvp-phase-1-device-derived-data`, installed in place and launched on rediscovered Kevq, iPhone 17/iPhone18,3, iOS 27.0 (24A435), UDID `00008150-000D25942278401C`. Agent process inspection confirmed PID 24859 after launch.
- Retained `phowhisper-cs-fp16-v1`, manifest `7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52`, 3,101,573,848 runtime bytes, ANE-capable encoder configuration unchanged. No asset transfer, model/tokenizer/decode changes, signing changes or cache deletion. Actual ANE placement remains unverified.
- Talk has explicit GPT-Live / On-device selection; missing preference remains premium. Local start validates English + Vietnamese settings. Prepare & start awaits the existing ASR owner, then speaks the fixed greeting. Record/Send invokes finalized ASR, a bounded Apple tutor request and completed-reply TTS. End/background cancel work and prevent restart until old workers drain. New Send-to-reply and TTS-delegate Send-to-audio timings are shown on Talk.
- Conversation-only: local records remain in memory, latest finalized turns remain visible until reset/restart, no durable history or learning evidence. Meaning/lookup/Help/typing/themes/search and premium finish/assessment paths are guarded off for local mode. Vietnamese was added to the existing language selector only to enable this required pair; broader Phase 4 onboarding/privacy/persistence and Phase 5 features remain deferred.
- Agent observed successful Release build/install/launch, running process, premium-default Talk and its mode menu through Device Hub. Agent did NOT select local/start preparation, record speech, invoke tutor, listen to TTS or pass the integrated gate. The user interrupted visual inspection and requested immediate handoff. Local layout, readiness and busy states remain PENDING HUMAN.
- Build warnings: existing AVAudioSession interruption API deprecation, existing LiveTransport async-alternative warning, and no-AppIntents metadata warning. Build succeeded; no new framework/test suite or project regeneration was needed.
- A bounded eight-second Mural-only syslog attempt returned only `[connected]`; it was stopped. No app timing/error events recovered, so this is not proof of zero network attempts. No broad device log archive collected. Device Hub quit requested before handoff; no owned capture remains active. Do not signal historical PIDs.
- Phase 2 remains ACCEPTED FOR MVP WITH KNOWN SILENCE FAILURE: three seconds of silence produced `Để mình check lại thông tin trước khi thi.` The mostly silent capped turn produced the same text; the 30-second cap passed, silence did not. A nonempty hallucination may now cause an unsolicited tutor reply. No silence filtering/remediation added.
- Evidence: `.build/verification/local-mvp-phase-3/` (build-final.log, install.log, launch.log, process.log, device.txt, executable.sha256, device-events.log, Talk/menu screenshots, result.md). No commits, pushes, publication, subagents, or active profiling.

**Next action: wait for human feedback.** On phone: Settings > Learning language: English, Meaning language: Vietnamese; Talk > mode menu (currently GPT-Live) > On-device > Prepare & start. Wait for the fixed greeting and Ready. After preparation, End, disable Wi-Fi/cellular, relaunch, Prepare & start again. Complete ten Record/Send exchanges including `Today I went to... siêu thị. I don't know that word in English.`, a modeled English repetition, and `Tôi không hiểu câu đó.` Check useful simpler English without spoken Vietnamese quotations, no Record during thinking/playback, readiness afterward. End during thinking and speaking, checking no late speech or recording. Report exact ASR/reply/errors, preparation and displayed Send-to-reply/Send-to-audio seconds, heat/crash issues. No repeated Phase 2 suite or silence prerequisite. Offline coexistence/latency/teaching and cancellation remain PENDING HUMAN; Phase 6 soak and premium response checks have not been run.

## Current workflow

The user replaced subagent verification with paired testing on September 14, 2026. The implementation agent builds/installs/launches and diagnoses logs directly; the user operates the physical phone and confirms speech/listening. See `mvp_plan.md`'s current-workflow override. No new test suites or canned inference. Keep evidence under `.build/verification/local-mvp-phase-N/`.

## Device build and identity (confirmed Phase 0/1)

Discover the connected iPhone each run. The user's existing Mural installation is `com.kevintruong.mural.dev`, not the public default. Preserve this identity with `PRODUCT_BUNDLE_IDENTIFIER=com.kevintruong.mural.dev` on xcodebuild; signing comes from ignored `Config/Local.xcconfig`. Do not uninstall or change credentials/data. Build Release for optimized local timing. Reuse `.build/local-mvp-phase-1-device-derived-data`.

The flask toolbar button opens the local probe without starting GPT-Live. No key is required. The main Talk microphone still starts premium until Phase 3 integration. Never use premium `--verify-audio`/`--verify-meaning` to prove local behavior.

## Apple tutor (human-confirmed Phase 1)

In the Phase 2 build select Apple tutor in the probe picker. Enter and Send each text:

1. Yesterday I went to the supermarket.
2. Tôi không hiểu câu đó.
3. Today I went to siêu thị. How do I say that in English?

Inspect real availability and English/Vietnamese locale support; read the actual response and listen to English TTS. Screenshot model first/full timing and TTS startup/duration. Stop during thinking, Stop during speech, then retry. The user confirmed these work in the Phase 1 build. Their screenshot also exposed an unhelpful repeated-sentence explanation and they reported English TTS spelling quoted Vietnamese. Prompt correction needs a focused replay; do not claim that correction verified yet.

## Speech recognition (Phase 2 mixed-language gate FAILED)

Fully quit Device Hub before capture. Open flask > Speech recognition > Prepare speech models on Wi-Fi. Wait through downloading/checking and warming for Ready to record. This uses FluidAudio 0.15.7, full multilingual/1120ms, language auto, about 664 MB assets. Repair download reconciles only this variant's cached files without erasing learning data.

Record and Send recording one turn at a time. Inspect Finalized recognition before invoking any tutor. This probe makes no tutor request and does not speak, persist transcripts, or award learning evidence. Include English, Vietnamese, missing-word, reverse-switch speech, silence, Yes/No, and a second distinct turn to catch stale text. Normal turns reuse loaded weights. Stop/Close/background unloads the manager; prepare again to reload cached weights. A recording finalizes at 30 seconds.

See plan sections 4 Phase 2 and 11 for exact corpus. Capture the displayed text, captured-audio duration, and Send-to-final timing. Do not interpret a recording status as proof of actual audio. Ask only for human actions required for this gate; stop if bilingual recognition is unusable.

### Focused blocker investigation replay

Preparation, single-language sentences, recording, and recovery were human-confirmed; mixed turns lost `siêu thị`, `cái từ này`, and `appointment`. Do not advance to Phase 3. See `.build/verification/local-mvp-phase-2/investigation/result.md` for the diagnostic build, cache comparison, launch blocker, and six numbered isolated-versus-mixed phrases. Wait for Recording and one additional second before those diagnostic turns to control early onset. Report each exact result. This timing instruction is not a relaxed acceptance criterion.

The focused replay has now also failed: isolated `siêu thị` was empty, isolated `cái từ này` worked but became `night` inside English, and reverse switches lost `appointment`. All 10 logged sample/chunk counts matched; 13 heuristic blank spans had zero recoveries. User relaunch resolved the earlier phone-lock blocker. The replay's syslog capture was stopped. Do not request another identical Nemotron replay without a concrete new hypothesis/change; the user has now approved the WhisperKit comparison below, retaining Nemotron.

The diagnostic patch changes no ASR settings or UI. Correlate results with `asr_configuration`, `asr_input`, and `asr_decode` before reset: loaded configuration, source/converted sample counts, first language tag, and blank-span/recovery counts. A first language tag is not evidence that all words share that language or that a switch succeeded. Counts alone do not prove audio fidelity. No raw audio is retained.

## Logs

A scoped `idevicesyslog -u "$DEVICE_UDID" --no-colors -x -p Mural` capture can run detached while the user tests. Keep its PID/evidence file, and stop only that process afterward. New local timing events use notice level with content-free numbers. Inspect `asr_ready`, `capture_started`, `asr_send`, `asr_final`, model/TTS events, and `OpenAI request attempted`. System logs may redact or omit events; absence in an incomplete log is not proof of zero requests. Never log keys, raw microphone audio, or personal transcript text intentionally.

## Approved WhisperKit comparison (human gate pending)

The probe defaults to **Whisper**. **Speech model** selects Whisper or Nemotron only when idle, unloads the previous recognizer, and clears its displayed results/timing without deleting cached assets. Both original Nemotron code and cache remain available. No automatic fallback, tutor connection, Qwen, or Phase 3 work.

WhisperKit 1.1.0 uses the fixed `openai_whisper-large-v3-v20240930_626MB` asset (about 627 MB plus tokenizer/Core ML caches), pinned asset revision `0f63a7800b00dd0226abd051b906c246e1907482`. Assets are under Application Support/WhisperKit, excluded from backup. Prepare may download missing assets/tokenizer; cached preparation should work offline and must be checked. Repair reconciles only this recognizer's model snapshot. Normal turns reuse in-memory weights and tokenizer. The microphone still uses the same bounded 16 kHz mono conversion; Whisper consumes the completed RAM-only turn after Send. No expected-word prompts or transcript correction. Auto language detection is explicit. The native one-second end-window skip is disabled so sub-second Yes/No recordings are not silently skipped. Silence hallucinations remain a test requirement, not solved by that setting.

Phone checklist, with Device Hub fully closed:

1. Flask > Speech recognition > Speech model: Whisper > Prepare speech models on Wi-Fi. Keep foreground; first Core ML preparation can take minutes. Report any error or termination, not repeated blind retries.
2. Record/Send the six numbered phrases in `investigation/result.md`, one turn at a time. Report exact final text plus Send-to-final seconds. Include one unseen mixed phrase, isolated Yes, isolated No, and 3 seconds of silence. Important words must survive without translation or invented content.
3. Stop during finalizing, then Prepare and a fresh distinct turn. Check no stale result arrives. Stop/Close/background should discard unfinished audio; check a background/reopen recovery for Whisper.
4. After successful preparation, disable Wi-Fi and cellular, relaunch Mural, Prepare Whisper from cache and repeat one mixed turn. Offline capability is not established by source inspection alone.
5. When convenient, select Nemotron and Prepare from its retained cache, then switch back. Only one model should be resident. No need to repeat the already-failed Nemotron corpus now.

Do not advance to Phase 3 based on successful installation. Keep results under `.build/verification/local-mvp-phase-2/whisperkit/`. Qwen is conditional on a failed Whisper human checkpoint; the monolingual compromise requires a deliberate scope decision and evidence for both languages.

## Parakeet VI-EN comparison (latest approved experiment)

The probe now defaults to **Parakeet VI–EN**. Whisper quality was provisionally accepted by the user, with word loss, retries/slower speech, and one extra `Gracias`. This is not an offline/silence/stability acceptance. Parakeet, not Qwen, is the next authorized experiment. Nemotron and Whisper remain selectable while idle; their caches are retained. No Phase 3 or VAD.

Prepare on Wi-Fi with the app foreground. The pinned split community conversion needs about **1.19 GB plus Core ML caches**, with a **15-second** limit for each Parakeet turn. Whisper/Nemotron remain 30 seconds. Compare the same three mixed phrases from the last user checkpoint at natural pace, one Record/Send each; capture exact output and Send-to-final seconds. Report failures without masking them with slower speech or repetitions; those can be separately labeled retries. Then test silence, Yes/No, Stop while finalizing and retry, background recovery, and offline cached preparation. A full matched-waveform comparison is not claimed: no raw audio was retained or replayed across models.

The preparation display now separates total preparation from model download/cache and loading. For Whisper, it also separates prewarm from load/tokenizer. To investigate its original 125.35-second preparation, select Whisper > Prepare once from its retained cache and report these numbers; no repeated corpus replay needed for this timing check. Do not assume that its first-install total is recurring warm load cost.

Parakeet logs include valid frames, sampled process footprint, process-lifetime RSS peak (not isolated model peak), and thermal state at load/finalization. No 20-minute stability, battery cost, or memory coexistence with the Apple tutor is established by this isolated probe. Use `.build/verification/local-mvp-phase-2/parakeet/result.md` for current build/evidence and capture PID.

### Parakeet checkpoint result

Human mixed-language quality failed: Vietnamese phrases survived but English was badly corrupted. Download/cache 116.62 s; load 20.52 s. Four actual finalizations were fast (0.096-0.532 s) but unusable for the goal. Phone vocabulary/config match the pinned assets; sample/valid-frame counts agree. No app-source change or model switch made after this result. Stop repeating the same Parakeet corpus without a concrete change/hypothesis. Whisper remains the best observed candidate, not yet a full offline/stability acceptance. Capture PID 74017 is stopped. See the Parakeet report for exact outputs and source-versus-conversion/decoder uncertainty.


## PhoWhisper CS checkpoint (Phase 2C PENDING HUMAN)

September 14: Phase 2A merge/Core ML parity passed on the same 21 scored scripted WAVs. Phase 2B Release is installed and launched on the connected iPhone 17/iOS 27 under com.kevintruong.mural.dev. See `.build/verification/local-mvp-phase-2/phowhisper/result.md` for exact executable hash, device, install logs, asset manifest, raw parity links and owned capture PID. No phone preparation or speech acceptance claimed yet.

The probe now defaults to **PhoWhisper CS**; other recognizers/caches remain. Open flask > **Speech recognition** > **Speech model: PhoWhisper CS** > **Prepare speech models**. The development-only 3.10 GB FP16 large-v2/LoRA asset is installed separately in `Library/Application Support/PhoWhisperCS/phowhisper-cs-fp16-v1`; no hosting or download path exists. Prepare checks exact file hashes, then warms the GPU encoder and decoder. The displayed cache-verification and prewarm/load timings are separate. Missing/corrupt files need the documented Mac transfer, not repeated Repair download attempts.

Agent verified build/install/launch/logs and that Device Hub is not running. User next waits for **Ready to record**, then uses **Record** and **Send recording** separately for the five phrases in the checkpoint report, preserving the known siêu thị challenge. Report each exact **Finalized recognition · PhoWhisper CS** text and **Send to final** seconds, plus preparation numbers or exact errors. Stop on errors instead of blind retries. No new recordings are needed on Mac.

After feedback/log inspection, request pure Vietnamese, isolated Yes/No, silence, word-search pause, unrelated next turn, Stop/reprepare, background recovery, cached offline relaunch and the explicit 30-second cap. Silence hallucination is unresolved; no quiet-speech rejection heuristic or tutor compensation was added. Mac times do not establish phone latency, memory or thermal behavior. Keep Phase 3 on hold until explicit human gate acceptance.


### Latest optimization checkpoint: 4-bit quality blocked, no phone replacement

See `.build/verification/local-mvp-phase-2/phowhisper/pal4-g16-v1/result.md`. The 891.74 MB group-16 4-bit candidate failed saved-corpus parity on 006/011/021. Component FP16 exceptions did not repair all differences; it was not installed. Keep the original FP16 app/assets and do not request another phone replay of the rejected candidate. Initial FP16 five-phrase accuracy was human-accepted (residual siêu thị error), but performance and remaining Phase 2 checks are unaccepted. No log capture is active; old PID 40170 was stopped. Optional ANE has not been attempted. Next is a justified focused precision correction and renewed parity before instrumentation/deployment, not Phase 3.

### Later 6-bit/8-bit checkpoint: both quality blocked

User-authorized 6-bit then 8-bit completed. 6-bit (1.266 GB) retained an incorrect `I went through`; 8-bit (1.656 GB) reintroduced `Em complete từ này`. Both changed the already-wrong seal tea to seoul tea. Neither was deployed; no new microphone checklist or active capture. Evidence: `.build/verification/local-mvp-phase-2/phowhisper/pal6-g16-v1/result.md` and `pal8-g16-v1/result.md`. Retain FP16, stop the completed bit-depth ladder, and review focused precision diagnosis before another candidate. ANE not attempted; Phase 2 remains unpassed.

### Active FP16/GPU timing checkpoint: PENDING HUMAN

User reordered work: profile retained FP16, then bounded ANE encoder, then consider 8-bit per-tensor. Instrumented FP16/GPU build installed/launched; no model/backend change yet. See `.build/verification/local-mvp-phase-2/phowhisper/fp16-gpu-profile-v1/result.md` for identity and exact three-turn matched replay (supermarket, mixed phở, supermarket). Capture PID74650 is retained for asr_ logs; inspect liveness/ownership before cleanup. Core AI trace could not start because Instruments sees phone offline; trace PID74651 exited, do not signal it. Prepare/recognition/component timings still PENDING HUMAN. No ANE placement/speedup or Phase2 acceptance claimed.

## Active comparison: FP16 ANE-capable encoder installed, PENDING HUMAN

Release0.1.0 (1), com.kevintruong.mural.dev, executable SHA-256 `50fbf078e0d4f41c0f3063562f513e180269f66c7602f0cf828ce01c73cb64b4` installed/launched on rediscovered Kevq iPhone17. Only change from GPU timing build is encoder CPU_AND_NE permission instead of CPU_AND_GPU plus truthful configuration log. Same FP16 weights/manifest/pins, tokenizer, decoder and decode options. No actual ANE placement or preparation success established. GPU signed rollback bundle retained at `fp16-gpu-profile-v1/Mural.app`, hash454aac591edb6e8a5a2f9fb37c27bee761dea7d7817db64c154c89c619505c6e.

Next human action: Prepare PhoWhisper CS once with Device Hub closed; keep foreground, wait at most3minutes, then Stop/report if not Ready, no blind retries. If Ready, Record/Send supermarket, mixed phở, supermarket (same exact three phrases in evidence). Report preparation breakdown, exact outputs and all Send-to-final times; stop/report a finalization over60s. Compare GPU70.262s preparation and9.77/4.44/3.74s Send-to-final. ANE memory/thermal/quality/latency PENDING HUMAN; no live capture or working Instruments trace, content-free unified timing logs retained in app. Never silently collect broad device logs (predicate ignored on attached-device collection).

Evidence: `.build/verification/local-mvp-phase-2/phowhisper/fp16-ane-compare-v1/result.md`, build/install/launch/process logs. No compression/export change, subagents or publication. Phase2 UNPASSED, Phase3 on hold; 8-bit per-tensor NOT STARTED.
