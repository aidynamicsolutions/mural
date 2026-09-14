# Mural handoff: Phase 3 manual-turn local conversation MVP

Implement **Phase 3: connect the testable audio loop** in `/Users/tiger/Dev/ios/mural/mvp_plan.md` in the next session. Read repository instructions and the plan completely before editing. Inspect actual code and the dirty checkout; preserve unrelated staged/unstaged changes, user data, cached models and evidence. **Do not spawn subagents.** Do not commit, push, publish weights/audio, add hosting/services or change signing identity.

The preceding session was documentation-only at the user's request: **no Phase 3 work has started**. Phase 2 is now **ACCEPTED FOR MVP WITH A KNOWN SILENCE FAILURE**, by explicit user decision. This supersedes old Phase 2 UNPASSED/PENDING HUMAN and Phase 3 on-hold notes in historical evidence. Do not restart optimization, request another ASR acceptance suite, or make silence remediation a prerequisite for this phase.

## User acceptance and unresolved behavior

- Phase 0 baseline done; Phase 1 Apple tutor/TTS provisionally accepted with documented teaching limitations. Prompt correction for simpler explanations and avoiding spoken Vietnamese quotations still needs a focused integrated replay.
- User accepts the retained FP16 PhoWhisper CS with ANE-capable encoder for MVP recognition/performance. Actual per-op placement is unverified; compute settings permit ANE, not prove it.
- User reports passed: separate Yes/No, two-second word-search pause, fresh unrelated turn, Stop during finalization/reprepare, background during recording/reopen, and cached offline relaunch/preparation/mixed recognition with Wi-Fi/cellular off. Exact final transcripts/timings for this batch were not supplied. Attribute these to the user, not agent microphone observation.
- **Silence FAILED:** three seconds of silence produced `Để mình check lại thông tin trước khi thi.`
- **Cap PASSED:** user clarified the 30-second test was mostly silence, stopped automatically around 30 seconds, and produced the same invented text. This is another silence hallucination, not evidence of speech being lost or successful continuous 30-second speech recognition.
- **Explicit waiver:** user accepts the silence behavior for MVP and asks to move on. Preserve the exact failure in reporting. Do not mark it fixed/passed, hardcode a phrase rejection, add word replacements, force a language or indiscriminately discard quiet/short speech. VAD/silence remediation is deferred, not part of this task.
- In the integrated loop, a hallucinated nonempty transcript can cause an unsolicited tutor reply. Explain this limitation; do not claim the app detects silence. Keep existing genuinely-empty-ASR handling: no user turn or tutor request.
- Earlier siêu thị and borrow/lend mistakes and occasional mixed-language losses remain. A correct rerecording is not proof of model nondeterminism or universal accuracy. Acceptance is for this MVP, not production reliability.

## Retained installed build/model

- Release 0.1.0 (1), bundle **`com.kevintruong.mural.dev`**. Executable SHA-256 `50fbf078e0d4f41c0f3063562f513e180269f66c7602f0cf828ce01c73cb64b4`.
- Last verified phone: Kevq, iPhone 17/iPhone18,3, iOS 27.0 (24A435). **Rediscover its current ID**; do not blindly reuse historical identifiers.
- Model **`phowhisper-cs-fp16-v1`**, development-only local path `Library/Application Support/PhoWhisperCS/phowhisper-cs-fp16-v1`. 3,101,573,848 runtime-file bytes excluding manifest/Core ML caches. Manifest SHA-256 `7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52`.
- Encoder `.cpuAndNeuralEngine`, decoder CPU_AND_NE permitted. Keep assets, attention/export, tokenizer and decode settings unchanged. Other recognizers/caches remain available, only one loaded at a time. Retained GPU rollback app: `.build/verification/local-mvp-phase-2/phowhisper/fp16-gpu-profile-v1/Mural.app`.
- Base `vinai/PhoWhisper-large` revision `b9136a44b5f2ca664bd0b8f74baecf1715f6eeeb`; LoRA `rinhoooo/phowhisper-large-vien-cs-asr` revision `a98f55e0f42b2c4f1e71b3348a2b917fac0a7328`.
- WhisperKit 1.1.0 revision `1e2a163736dfa5a198e637ae44c114e1c6d5cc2d`; WhisperKitTools `84f77a83c8f530022ae55fbb1a64b3351ef63c7a`.
- Architecture large-v2: 80 mel bins, 1280 embedding, 32 decoder layers, 51865 vocabulary, 480000 audio samples/30 seconds, 448 decoder cache positions. No smaller-model substitution.
- Preserve `App/PhoWhisperTokenizer.swift`: old tokenizer lacks timestamp strings and names no-speech `nocaptions`; stock unknown-ID handling previously caused blank output. The helper fixes the control-token contract, not lexical content, and loads BPE locally without network fallback. App checks loaded dimensions and explicitly sets multilingual mode; the runtime's default variant label is not authoritative.
- No model hosting/download source exists. Keep weights out of Git/app bundle. Existing local assets should survive in-place installs; no transfer needed unless a real missing/corrupt-asset error occurs. External original assets/commands/notices: `/Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/README.md`.

### Timing evidence and limits

Human ANE-capable first preparation: 215.2 s (verification 2.85 s, prewarm 205.98 s, load/tokenizer 6.33 s). Send-to-final: 4.44 s first supermarket, **3.19 s for the FAILED mixed-phở first attempt**, 1.57 s last supermarket. First mixed output was entirely Vietnamese, exact string not supplied; successful retry time unknown. Do not present 3.19 s as a successful bilingual benchmark.

After force-close/reopen, user reports preparation **6.3 s** (verification 2.3 s, prewarm 3 s, load/tokenizer 0.97 s); the same transcriptions then all correct and fast, without exact per-turn times. Likely consistent with Core ML's disk specialization cache surviving app termination, not proof of its mechanism or guaranteed cache lifetime. First-use cost may return after cache eviction/model/OS/configuration changes.

Recovered GPU comparator: preparation 70.262 s, Send-to-final 9.77/4.44/3.74 s; encoder 8.52/1.84/1.82 s. SDK decodingLoop overlaps encoding/full-window work, so it is not decoder-only. Decoder prediction timing includes language detection; no separate language-detection total is exposed. GPU footprint after inference about 2.54-2.60 GB, process-lifetime RSS peak 4.00 GB, sampled thermal nominal. These are **not ANE memory measurements**. ASR plus Apple tutor coexistence, full response gap and later sustained stability remain integration gates.

4/6/8-bit grouped-channel candidates failed saved-corpus fidelity and were not deployed. Preserve their versioned artifacts; do not rerun them. Eight-bit per-tensor, further profiling, ANE export tuning and VAD are deferred.

## Phase 3 implementation scope

Implement the smallest real manual-turn loop from plan section 4 Phase 3:

```text
fixed English greeting -> ready
user Record -> bounded RAM-only microphone turn -> Send
-> finalized local PhoWhisper ASR -> Apple SystemLanguageModel
-> completed short English reply -> AVSpeechSynthesizer -> ready
```

1. Inspect the current coordinator, audio owner, tutor helper, Talk/probe UI, cancellation, mode/consent, meaning and assessment call paths. Start with `App/ConversationCoordinator.swift`, `App/LocalConversationEngine.swift`, `App/LocalTutorModel.swift`, `App/PhoWhisperTokenizer.swift`, `App/RootView.swift` and related actual callers. Reuse existing implementation; no provider framework, extra coordinator or benchmark infrastructure.
2. Use fixed greeting **`Hi! What did you do today?`**, no model-generated greeting request. Reuse Talk/orb and make local Record/Send/End/readiness states clear. Explicitly choose local behavior; absent mode preference preserves premium. Bring forward only section 8's minimum mode latch, local entry/selection and teardown/cloud-call guards required for this loop. Full onboarding/settings/persistence integration belongs to Phase 4.
3. Reuse native AVAudioEngine/AVAudioConverter 16 kHz mono bounded capture, 30-second cap, finalized-turn transcription, one loaded recognizer reused across turns, no forced language/expected text/cross-turn ASR prompt. Do not record while tutor/TTS runs. Preserve Stop/Close/background cancellation and no stale callbacks/in-flight unload. Keep manual Send; VAD/barge-in absent.
4. Connect the actual `LocalTutorModel` and English system TTS. Use compact bounded context, English/Vietnamese support, short English replies, and existing availability/error handling. Wait for completed reply before TTS. Model work must not block the audio callback/main actor. End remains available while busy and prevents late audio/recording starts. Keep unfinished local actions unavailable.
5. Keep normal/premium GPT-Live routing intact. Audit start, reply, Help, Meaning, lookup, typed replies, finish/assessment and teardown: local operations must not silently call OpenAI even when UI actions are hidden. For this conversation-only milestone, meanings and assessment stay off; no new learning evidence, local supporting-feature suite or Phase 4/5 persistence migration. Reuse existing records/UI where needed without expanding scope. Missing OpenAI credentials do not block local verification.
6. Preserve genuinely empty result handling and the explicit silence waiver above. Do not invent transcript corrections or tutor compensation to claim ASR success. Disclose the known possibility of silence-triggered replies in the feasibility handoff.
7. Read `scripts/generate_project.py` before project changes. It is the source of generated Xcode files; regenerate if needed, never hand-edit generated project files. Preserve deployment target iOS 27, dependency pins, signing and existing notices.

No new tests/test framework, mocks, profiler/control plane or broad rerun. Use the existing verification skill and actual app paths, plus focused content-free timing/error diagnostics. No raw microphone content or personal transcript logging/persistence added for diagnostics. No further optimization in this phase without a concrete integrated-loop blocker.

## Paired verification and stopping point

Read `.agents/skills/verify-mural/SKILL.md` and its `features/local-conversation.md`. Their earlier Phase 2 pending notes are historical; the current decision in `mvp_plan.md` controls. No tester/scout/worker agents. Implementation agent builds/installs/launches and inspects evidence; user operates phone microphone/UI and listens.

- Reuse `.build/local-mvp-phase-1-device-derived-data`, **Release**, and build override `PRODUCT_BUNDLE_IDENTIFIER=com.kevintruong.mural.dev`. Discover phone, install in place, launch, inspect logs. Never uninstall/erase or overwrite learning data. Do not modify signing credentials or ask user to run build commands.
- Inspect changed UI for correct states/readability/accessibility. Fix small clear defects in the affected flow, without redesigning unrelated UI.
- Once actually installed/launched, fully quit Device Hub and hand over promptly with exact local entry point, buttons and a short actionable Phase 3 checklist. **Stop and wait for human feedback**, mark PENDING HUMAN, not passed.
- Plan's Phase 3 acceptance: offline after preparation and relaunch, ten real back-and-forth exchanges including mixed supermarket speech, useful short English tutoring/TTS, no recording during playback, readiness afterward. Test End while thinking and speaking; no late audio or recording. Measure the whole Send-to-reply/audio gap, not just ASR/model time. Include a focused check of Phase 1's simpler explanation/English-only spoken wording in this real loop.
- Do not repeat the whole historical ASR model suite. Known silence defect is accepted/deferred, not a new Phase 3 prerequisite or a passed silence test. New substantial integrated-loop failures still require diagnosis or an explicit scope decision. Apple model coexistence/latency cannot be assumed from isolated ASR success.
- Phase 4 records/routing/privacy integration, Phase 5 supporting features/evidence, and Phase 6/full 20-turn/20-minute soak remain later phases; do not mark them complete or implement them wholesale now.

## Logs, evidence and handoff maintenance

Keep Phase 3 evidence under `.build/verification/local-mvp-phase-3/`. Preserve Phase 2 history under `.build/verification/local-mvp-phase-2/phowhisper/`, including `fp16-ane-compare-v1/`, `fp16-gpu-profile-v1/` and failed `pal4/6/8-g16-v1/` reports. Final human acceptance/silence waiver is recorded in the plan; some historical reports still say pending.

There are **no active captures**. Do not signal old PIDs. Instruments listed the connected phone offline despite successful devicectl deployment; no actual ANE placement trace obtained. idevicesyslog missed events; GPU timings were recovered using administrator-approved device log collection. **Apple ignores `log collect --predicate` for attached-device collection**, creating a broader device archive. The prior broader archive was deleted after filtering. Do not silently collect another or represent collection as narrowly scoped; explain scope and obtain authorization first. App bundle is `com.kevintruong.mural.dev`; logger subsystem remains `no.william.mural`, which is intentionally distinct.

After the Phase 3 checkpoint, update the plan and this prompt with installed build/model identity, real observations, exact next action, retained known failures, user acceptance versus agent evidence, and stopped/owned capture status. Do not commit/push/publish without authorization. Deliver the conversation-only feasibility milestone before pursuing further features or compression.
