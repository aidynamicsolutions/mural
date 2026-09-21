# Mural: on-device TTS implementation and comparison plan

**Implementation order:** Supertonic-3 ANE-bucketed int4 → Kokoro-82M → optional Kokoro-7M-Distill
**Target:** the user's real iPhone 17; local, offline English tutor speech
**Prepared:** September 20, 2026
**Repository:** `aidynamicsolutions/mural`, branch `mvp`
**Reviewed snapshot:** `185696849b35fd6b70474f8929232b3a88cb2ec1`
**Suggested repository location:** `docs/tts/implementation-plan.md`

> This is an implementation handoff, not a record of completed work. No TTS integration, compilation, phone deployment, or listening test has been performed as part of preparing this document. All implementation checkboxes start unchecked.

## 1. Goal and boundaries

Replace the local Apple speech output with a higher-quality local voice, without destabilizing the existing speech-recognition pipeline or making the conversation feel slower. Start with Supertonic-3 int4. Then make Kokoro-82M available for a controlled comparison of quality, latency, memory, and sustained behavior. Keep Kokoro-7M as an explicitly optional final experiment.

Keep **ASR plus one selected TTS backend** available during an active conversation when measurements permit. Do not keep Supertonic and Kokoro loaded together. Do not change ASR's existing staged loading into permanent full-model residency: that is a separate project, and existing code deliberately releases substantial ASR resources between stages/turns. [R1][R4]

The scope is English speech in the On-device conversation mode, including the greeting, ordinary replies, and spoken Help. Vietnamese meaning/subtitle behavior remains unchanged. No new languages, cloud speech, voice cloning, custom training, model conversion project, generalized provider framework, or changes to premium voice are needed.

### Important correction to the earlier recommendation

Supertonic remains the first implementation candidate. However, **Kokoro-82M through FluidAudio's CoreML/ANE backend must not be treated as a production-safe iOS 27 choice.** The exact FluidAudio revision already pinned by Mural includes an advisory that neither tested CoreML route is known safe on that OS line. Upstream issue #889 remains open and reports native crashes that cannot be handled by a Swift `catch`. The reported devices/builds are not a direct measurement of this user's base iPhone 17, but the warning is materially relevant. [R2][F5][F8]

Stage 4 therefore contains a compatibility gate. It preserves the requested Kokoro comparison, but does not authorize pretending that a short successful test resolves the warning. An ONNX CPU contingency is described if a usable phone comparison is wanted while the CoreML issue remains unresolved.

## 2. Progress board - update this first

Status values: `NOT STARTED`, `IN PROGRESS`, `PENDING HUMAN`, `PASS`, `BLOCKED`, `SKIPPED`.

Use `PASS` only when that stage's checks and required human confirmation are complete. A successful build is not a listening or device-performance pass. Keep evidence paths and the next action current so another agent can resume without repeating completed work.

| Stage | Deliverable | Status | Evidence / blocker |
|---|---|---|---|
| 0 | Confirm checkout, device, ASR baseline, and existing verification workflow | PASS | User confirmed Apple conversation; runtime FP8/PAL8 prepared/ready and TTS events captured. See `results.md`. |
| 1 | Minimal TTS seam, shared PCM playback, comparison screen, measurements | PASS | Human replied done; both phone PCM rates completed, Apple phrase 29 cancelled, normal Talk human-confirmed. See `results.md`. |
| 2 | Supertonic-3 int4 working standalone on the phone | PASS | User accepts voice/Stop/offline and explicitly waives repeat smoke listening. Batch bug fixed with passing five-phrase simulator regression; phone five-phrase batch remains incomplete. See results. |
| 3 | Supertonic integrated into Talk; ASR coexistence and lifecycle checks | PASS | Human accepts checkpoint; seven spoken turns, retained-manager synthesis and cleanup captured, max sampled process footprint 1.481 GB. Offline/exact transcript metadata and same-session resume limits remain in results.md. |
| 4 | Kokoro-82M compatibility decision and selected runtime implementation | BLOCKED | Issue #889 remains open; no verified safe CoreML route. Explicit ONNX CPU or bounded-risk diagnostic choice required before implementation. |
| 5 | Matched comparison and sustained phone verification | NOT STARTED | - |
| 6 | User choice, narrow default change, rollback verification | NOT STARTED | - |
| 7 | OPTIONAL: Kokoro-7M-Distill | NOT STARTED | Requires separate go-ahead |

### Current handoff

```text
Working branch / HEAD: existing mvp / 74df98b8865b98c115d53dd257e1c13072a59342 + Stage 1/2 changes
Existing uncommitted work preserved: external FireRed commit and staged TTS docs preserved
Last completed stage: 3 (human acceptance; qualification limits in results.md)
Current stage: 4, BLOCKED pending runtime choice
Actual installed build / executable hash: Release 0.1.0 (1), com.kevintruong.mural.dev / b36a5737257a8e16cfcac1ba72a61334d637c1e08cbf776f41e42f5c9eaa8f69
Actual phone model / OS build: iPhone 17 / iPhone18,3 / iOS 27.2 (24B5084k)
Actual ASR backend / model identity: staged launch event confirmed; unchanged FP8 packed-v3 + PAL8, prewarm=always; Stage 0 preparation passed
Actual TTS backend / model identity: Apple default, existing regional/pinned English resolver; Stage 0 Karen Premium en-AU
Latest evidence directory: .build/verification/tts/stage3-resume-20260920-203841/
Human feedback received: Stages 0–3 accepted; Stage 2 repeat smoke explicitly waived, Stage 3 user says all good/done
Current blocker: Kokoro iOS 27 CoreML warning unresolved; additional runtime or risky diagnostic requires explicit selection
Prepared Stage 2 executable SHA-256: 7b1c9b485df56cc565766405b0af42cad8a01d8e3ce67d4fac8f6e93624c2b8c
Exact next action: choose whether to defer Kokoro or implement the ONNX CPU contingency. Do not run native Kokoro automatically. Stage 3 accepted; capture stopped. Repair acquired-inventory relative-path metadata before final comparison reporting.
```

### Agent execution rule

Implement and verify one stage at a time. Continue through machine-only checks without repeatedly requesting approval. At a listening/device checkpoint, install the intended build, start the agreed scoped logging, provide one short phone checklist, mark `PENDING HUMAN`, and stop that checkpoint until feedback arrives. Do not spawn tester subagents or compete with another agent for the phone. Do not proceed to optional Stage 7 automatically.

## 3. Repository context that must survive the change

Read the current checkout before editing. The snapshot above is a reference, not an instruction to reset newer work.

| Existing location | Why it matters |
|---|---|
| `App/LocalConversationEngine.swift` | Owns local Apple TTS, microphone/audio session, ASR, cancellation, readiness, and playback metrics. `speak(_:) async throws` is the integration boundary. |
| `App/ConversationCoordinator.swift` | `speakLocal(...)` connects playback callbacks to saved fragments and returns Talk to Ready only after speech finishes. |
| `App/LocalTutorModel.swift` | Keep tutor generation unchanged. The comparison must not confuse tutor variability with TTS speed. |
| `App/MuralApp.swift` and existing settings/diagnostics views | Add only a small experimental entry point; avoid expanding the existing probe machinery unnecessarily. |
| `App/VietnameseEnglishRecognizer.swift` | Existing `logMemory` helper is a starting point for compatible footprint instrumentation. |
| `Mural.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | Pins FluidAudio `0.15.7` / `41540ea237350afe5117a082b5c28eda642d0612` and Argmax/WhisperKit `1.1.0`. |
| `.agents/skills/verify-mural/SKILL.md` | Build/install, simulator UI checks, device evidence, and paired-verification rules. |
| `.agents/skills/verify-mural/features/local-conversation.md` | Local Release recipe, bundle identity, phone logging, microphone cautions, and historical checkpoints. |
| `docs/coreai/gpu-talk-checkpoint.md`, `docs/coreai/first-turn-readiness-prewarm-plan.md`, current `mvp_plan.md` | Read the latest applicable ASR constraints; historical sections can be superseded. |

Confirmed behavior at the reviewed snapshot:

- Apple voice selection already prefers installed Premium/Enhanced `en-US` voices, unless a saved eligible voice is selected. Preserve that baseline rather than comparing against an arbitrarily worse Apple voice. [R1]
- `speak(_:)` currently starts speculative staged decoder prewarming before calling the Apple synthesizer. Neural synthesis must not blindly inherit that compute overlap. [R1]
- `onPlayback(start, end, completed)` affects stored playback metadata. Finalized assistant text is saved before speech; do not delete or duplicate that text when synthesis fails or is canceled. [R3]
- ASR has additional probes, including Breeze and FireRed, in newer work. They are unrelated to this TTS change. Do not enable or tune them during comparisons. [R1]
- Existing phone instructions and code may disagree about historical Core AI opt-in/default behavior. Resolve this using current source, the actual compiler invocation, and runtime backend logs-not an old document heading alone. [R1][R5]

### Memory evidence is a warning, not a fixed allocation allowance

The repository records a historical staged corpus footprint sample near **2.096 GB**, and an older hybrid run killed with a logged **3376 MB ActiveHard** limit. Those are observations of particular runs, not a guaranteed current ceiling or an available-memory entitlement. Re-measure the actual current build. Do not subtract a desktop TTS RSS figure from that old limit and declare coexistence safe. [R4][R6]

The previously cited FluidAudio TTS performance figures are desktop reference measurements. They are not iPhone 17 results. This plan deliberately measures phone preparation, generation, playback, and combined process footprint instead. [F9]

## 4. Minimal design

### Keep the public conversation boundary

Preserve `LocalConversationEngine.speak(_:) async throws`, `onPlayback`, the existing recorded metrics, and `ConversationCoordinator`'s session checks. Let `speak(_:)` dispatch internally to Apple or the selected neural backend.

Do **not** require Apple speech to generate PCM merely to satisfy an abstraction. Leave its delegate-based path in place. Both neural backends should return a small internal value equivalent to:

```swift
// Proposed Mural type, not a FluidAudio API.
struct LocalTTSAudio: Sendable {
    let samples: [Float]
    let sampleRate: Double
}
```

One internal enum and one owning service with a switch are sufficient. A protocol is optional if a test genuinely needs it; no registry, dependency-injection container, or multi-provider scheduling framework.

### Suggested file budget

Start with roughly four small new Swift files, combining them if clearer:

- `App/LocalNeuralTTS.swift`: backend identity, one selected manager, prepare/synthesize/unload, validated configuration.
- `App/LocalPCMPlayback.swift`: one neural audio playback path.
- `App/TTSComparisonView.swift`: experimental controls and compact results.
- `App/TTSComparisonRunner.swift`: fixed corpus, sequential execution, basic measurements/export.

Use a single checked-in corpus JSON resource, a small results document, and focused tests. Register app files/resources in the existing Xcode project using the repository's normal approach. Do not regenerate the whole project just to add a handful of files. Do not assume the root `MuralCore` package includes app-target code. Keep pure validation/statistics tests in its existing testable boundary where practical; verify app-only audio/session behavior through the existing app/UI or explicit probe path. Do not claim `swift test` exercised the new player unless the relevant code is actually in that target.

### Model ownership

Only the selected neural manager may be loaded. Initialize once per active conversation/comparison block, reuse it, and release per-request audio after playback. Unload when the session ends, the app backgrounds under the existing pause policy, the user switches backend, or a memory warning stops the experiment.

`cleanup()` is a request to release owned resources, not proof that native allocations immediately disappear. Await ongoing work first; then clean up and measure. Kokoro also uses a shared G2P singleton, so releasing its seven synthesis graphs may leave auxiliary allocations. Separate-process benchmark blocks prevent this contaminating later measurements. [F5]

### Playback

Prefer a small `AVAudioEngine`/`AVAudioPlayerNode` wrapper owned by `LocalConversationEngine`. It must not manage a second competing `AVAudioSession`. Keep microphone capture and speech playback half-duplex.

Use the returned model sample rate: Supertonic is 44,100 Hz; Kokoro is 24,000 Hz. Do not relabel samples as another rate. Use an appropriate mixer/converter when the hardware route differs. Feed generated PCM directly; writing WAV files is optional evidence export, not a mandatory production round trip. [F1][F6]

For normal completion, wait for audio to be played, not merely generated or queued. Use the appropriate playback-completion mechanism, such as a player-node `.dataPlayedBack` completion, with request identity checks. A timing event near playback/render start is an estimate of audible start, not an acoustic measurement. [A1]

### Concurrency and stop behavior

Reserve the speech operation **before the first `await`**, including preparation/audio-session activation, so a second tap cannot enter through actor reentrancy. Keep one request ID and a busy/draining state until all native work returns.

On Stop/End/background/interruption: stop audible playback immediately, cancel cooperative work, reject late buffers/callbacks, and finish the awaiting speech call exactly once. If native inference does not cancel immediately, keep new ASR/TTS admission blocked until it drains. Do not call manager cleanup concurrently with an in-flight prediction, or launch an unowned detached task that survives session teardown.

A completed utterance must not call the existing whole-session `stop()` merely to reset the player; that would also release ASR. Keep playback cleanup separate from conversation teardown. Test both paths.

### Error behavior

During comparisons, fail visibly and record the selected backend's failure; **no automatic Apple substitution**. A fallback would invalidate both listening labels and performance results. Keep an explicit “Use Apple voice” action outside an active measurement. Never switch to cloud speech.

For normal Talk, initially use the same visible failure plus explicit fallback action. Any automatic fallback can be a later, separately tested product decision. Native SIGSEGV/SIGABRT failures cannot be recovered by this policy.

## Stage 0 - Confirm the baseline and working environment

**Outcome:** a known-good baseline and a safe, reproducible phone workflow.

- [x] Read the current handoff, verification skill and local-conversation feature guide, plus repository instructions applicable to edited files.
- [x] Record `git status --short --branch`, HEAD, relevant local changes, toolchain versions, and resolved dependencies. Preserve all unrelated work; no reset/clean/stash or automatic pull over a dirty checkout.
- [x] Record whether the work continues on the user's existing branch or a narrow branch from current `mvp`. No push/merge is required by this plan.
- [x] Discover the actual paired iPhone and installed OS build. Do not copy historical UDIDs from docs.
- [x] Preserve the existing paired bundle identity, currently documented as `com.kevintruong.mural.dev`, and signing configuration. Verify it before installation; do not create a second app or uninstall the current one.
- [x] Verify the actual local ASR backend/model and its build flags. Capture runtime backend/prepared/ready events. Do not change weights, tokenizer, precision, assets, specialization caches, or decoding policy.
- [x] Run existing relevant core/build checks and one short existing Apple-TTS conversation with the user's help. Record known problems separately from TTS regressions.
- [x] Inventory existing memory/latency logs before asking the user to repeat measurements.
- [x] Confirm the pinned FluidAudio checkout contains Supertonic and Kokoro APIs below. Start with the current pin; do not upgrade unrelated dependencies.
- [x] Record license files for exact intended model/voice revisions. Supertonic's upstream license and converted model card use OpenRAIL labels, while the desktop benchmark table labels its row Apache; do not use the benchmark label as distribution clearance. Preserve actual notices and resolve requirements before shipping. [F10]

**Gate:** baseline builds, correct phone/backend identified, existing local speech works or its blocker is explicitly documented. No TTS performance claim yet.

**Stage note:** `Status: ___ | Evidence: ___ | Human result: ___ | Next: ___`

## Stage 1 - Shared seam and a small comparison surface

**Outcome:** Apple baseline and synthetic PCM work through the intended lifecycle before any neural model is introduced.

- [x] Add experimental backend selection and a compact comparison screen in the existing diagnostics/settings area.
- [x] Gate experimental UI and any automation behind `MURAL_TTS_EXPERIMENT`, including the Release phone build.
- [x] Keep Apple the default, preserve regional/pinned voice selection, and freeze backend selection while busy or ASR is prepared. Normal Release compiles without experiment UI.
- [x] Add one PCM playback wrapper and the shared validated result type; no second audio-session owner.
- [x] Confirm explicitly played quiet 24 kHz and 44.1 kHz signals on the physical speaker. Human passed; both phone report records completed.
- [x] Reserve before awaits; implement cancellation, draining, stale-callback protection and exactly-once completion.
- [x] Include shared speech admission in Record/Prepare/mode/backend readiness. Native neural work will use this seam in Stage 2.
- [x] Preserve playback callbacks and saved-fragment behavior; coordinator changes only add busy guards. Phone Talk regression human-confirmed; subsequent Record/Send/reply was not in the scoped log.
- [x] Add the exact 30-phrase corpus, sequential execution, durable per-utterance JSONL and summary export. Apple has no waveform/synthesis timing; no neural timing is fabricated.
- [x] Exercise input validation, double admission, cancellation before start, held noncooperative drain, stale request IDs, failed preparation and backend-switch rejection. Simulator checks include Apple/PCM Stop during playback.
- [x] Verify Settings navigation, explicit synthetic controls and disabled-state appearance on simulator. No neural inference run.

Keep the screen small: backend, supported voice, Prepare, Play selected phrase, Run corpus, Stop, and last-run summary/export. Show loading/busy/error states. Avoid a voice marketplace or elaborate persistent benchmark database.

**Gate:** Apple behavior unchanged, synthetic PCM lifecycle correct, UI machine checks pass. Actual speaker behavior remains a physical-device check.

**Stage note:** `Status: ___ | Evidence: ___ | Human result: ___ | Next: ___`

## Stage 2 - Supertonic-3 int4, standalone first

**Outcome:** a prepared, reusable Supertonic manager producing audible English on iPhone 17, without ASR/tutor interference.

### Verified API and exact variant

At the pinned FluidAudio revision, the public API is `Supertonic3Manager`, not the older `Supertonic3Models` example in the Hugging Face card. The model option is explicitly `.aneBucketed(.int4)`. This is 4-bit weight compression of the **VectorEstimator stage**, not a claim that every tensor in the entire pipeline is int4. [F1][F2]

Illustrative calls, to be placed inside Mural's owned lifecycle rather than pasted as an unstructured task:

```swift
import CoreML
import FluidAudio

let speechModel = Supertonic3Manager(
    computeUnits: .cpuAndNeuralEngine,
    vectorEstimator: .aneBucketed(.int4)
)
try await speechModel.initialize()
let speakerStyle = try await Supertonic3ResourceDownloader.loadVoiceStyle(.m1)
let rendered = try await speechModel.synthesize(
    text: utteranceText,
    language: "en",
    style: speakerStyle,
    totalSteps: 8,
    speed: 1.05,
    silenceDuration: 0.05
)
// Adapt rendered.samples to LocalTTSAudio(sampleRate: 44_100).
// After outstanding native work has returned, at session teardown:
await speechModel.cleanup()
```

Verify these calls against the resolved checkout while implementing. Source comments and model cards have some stale defaults; use actual declarations and explicit configuration. [F1][F2][F3]

### Implementation

- [x] Use `.aneBucketed(.int4)` explicitly. Do not silently fall back to FP16/dynamic models or call another precision “int4.” Record requested routing; actual ANE placement remains unverified unless independently profiled.
- [x] Use the existing downloader/cache. Download only the chosen variant and selected voice assets; do not clone every precision/bucket/voice repository or re-export models.
- [x] Add visible one-time preparation/download status and retry for an explicit user action. Keep preparation outside measured warm synthesis.
- [x] Start with `M1`; optionally audition `F1` on the same five short phrases. Freeze one selected voice before the main comparison and record it.
- [x] Use eight denoising steps and speed 1.05 initially. No precision, thread, or step sweeps. Only tune one setting later if a measured problem warrants it.
- [x] Pass full bounded tutor text to the manager's built-in chunker. Do not add a second Supertonic chunker or duplicate inter-chunk silence.
- [x] Inspect the pinned chunker and test phrases around its boundaries. The shorter Latin chunk policy is relevant to quality; do not increase its limit just to improve a speed number. [F4]
- [x] Reject nonfinite/empty audio and invalid sample rates. Flag unexpected clipping or implausible duration rather than hiding defects with arbitrary normalization.
- [x] Keep text/audio buffers bounded. For this MVP, use a documented high-level input ceiling such as 1,000 Unicode characters; reject over-limit input visibly instead of silently truncating a tutor reply. Record any backend-specific token limit separately.
- [ ] Record asset paths, exact files/bytes and checksums once after acquisition, voice/config identity, and package revision. Preserve that asset set for the comparison; warm synthesis must not redownload or rehash models every turn.
- [ ] Test five synthetic phrases in a TTS-only Release phone run. Do not prepare ASR or the tutor for this first smoke test.
- [ ] After preparation, relaunch offline and synthesize a phrase not used for warmup. No network request should be needed for inference.

Model downloads may occur during explicit setup; learner/tutor text must never be sent to a server. Do not modify existing ASR cache directories. If a custom cache root is used, confirm FluidAudio's expected root-versus-repository nesting rather than inventing a path. [F3]

**Implementation note (current pin):** actual `Supertonic3Constants.maxChunkLengthLatin` is **70**, not the stale 110-character chunker comment. The encoder takes a 128-scalar prefix after normalization. Mural preserves the upstream chunker and rejects overlong individual words or excessive normalization expansion conservatively before synthesis. Tests cover 69/70/71 boundaries, all 30 corpus phrases after actual pinned preprocessing, and a reproduced long-word truncation case. See `results.md`.

**Human batch:** listen to one acknowledgment, one question, one correction, one number/date example, and one longer sentence; then tap Stop during a long utterance. Report audible quality, missing words, pauses, clipping, and whether Stop is immediate.

**Gate:** actual int4 variant verified, valid audio, offline reuse, no recorded warning/crash in the smoke test, and human confirms speech/playback. This is not yet ASR coexistence or sustained reliability.

**Stage note:** `Status: ___ | Evidence: ___ | Human result: ___ | Next: ___`

## Stage 3 - Integrate Supertonic into Talk without changing ASR

**Outcome:** the selected TTS is reused across turns while the existing ASR ownership policy remains intact.

- [ ] Prepare Supertonic once during explicit conversation preparation, before the first spoken greeting. Keep its ready manager for subsequent turns.
- [ ] Serialize expensive model preparation/inference with ASR loading/transcription. Account for `stagedDecoderWarmup` as well as `asrTask`; checking only `asrTask` is insufficient.
- [ ] For the neural path, move the existing greeting decoder-prewarm trigger to **after speech synthesis returns**, preferably at playback start. This lets prewarm overlap lightweight playback, not neural generation. Preserve the existing warmup task's ownership/drain behavior. [R1]
- [ ] If even playback-plus-prewarm exceeds the measured budget, make prewarm sequential and record the latency tradeoff. Do not change decoder policy, precision, or ASR residency to conceal the cost.
- [ ] Keep Apple behavior unchanged where practical. Record the prewarm scheduling policy with every end-to-end comparison; a scheduling change is not solely a model-speed improvement.
- [ ] Route greeting, normal response, and spoken Help through the selected backend. Keep tutor text, saved fragments, meaning/lookup, and assessments unchanged.
- [ ] Verify preparation, synthesize, playback, and total Send-to-audio events separately. Preserve the current public metric meaning; do not label synthesis completion as playback start.
- [ ] On End/background, stop playback promptly, drain native work, unload TTS, and follow the existing pause/resume/session rules. No late speech after reopening or entering another conversation.
- [ ] Extend memory-warning handling to neural TTS even in a TTS-only comparison. Stop the batch, save already-collected evidence, and do not immediately retry/reload.
- [ ] Check 3–5 real spoken turns and a typed reply with the user. Also test Help, End while speaking, background/foreground, and offline use.
- [ ] Confirm that an interrupted assistant fragment remains saved with `playbackCompleted == false`; a fully played one becomes complete. No duplicate transcript text.
- [ ] Record whether the selected TTS manager stayed loaded across turns and whether the existing ASR stages still load/release as before. Do not claim “both full models permanently resident” from manager object existence alone.

**Human batch:** prepare a new local conversation, speak two short replies, type one reply, request Help, interrupt speech with End, then start again and background/return. The agent supplies the actual UI steps for the installed build.

**Gate:** paired functional checks pass and measured coexistence does not trip the stop rules. If warm resident TTS cannot fit, record that failure; unloading every turn is a separate measured fallback, not a pass for the residency goal.

**Stage note:** `Status: ___ | Evidence: ___ | Human result: ___ | Next: ___`

## Stage 4 - Kokoro-82M: compatibility gate, then one runtime

**Outcome:** a clearly identified Kokoro-82M comparison route, or an honest platform blocker. Do not let this delay a working Supertonic checkpoint.

### 4A. Decide before phone inference

- [ ] Record the actual iPhone OS build and read pinned `KokoroAneManager`'s `osAdvisory` plus current upstream #889 and any linked verified fix. A closed older #843 is not evidence that the later problem is resolved. [F5][F8]
- [ ] Keep Kokoro CoreML disabled by default on a warned OS. Do not begin an automatic corpus/soak there or run risky synthesis in an unsaved real conversation.
- [ ] Record one choice below before implementing a runtime:

| Choice | Action |
|---|---|
| Native route has relevant verified upstream fix | Use a narrowly justified pinned revision and the adapter in 4B; re-run Supertonic/baseline regression checks if the dependency changed. |
| Warning unresolved; user accepts a bounded diagnostic | Implement 4B behind an explicit, nonpersistent experimental switch. Run only the agreed synthetic test. Label results `EXPERIMENTAL-KNOWN OS RISK`; do not promote to normal Talk or treat a short pass as clearance. |
| Warning unresolved; user wants a usable on-phone comparison | Use the ONNX CPU contingency in 4C. It is a different runtime with new performance measurements, not the desktop ANE result. |
| User does not choose an additional runtime or risky diagnostic | Mark native Kokoro `BLOCKED`; retain Supertonic and complete its remaining gates. Do not substitute Mac numbers for phone results. |

A diagnostic crash must not cause a launch loop: never persistently auto-start Kokoro, and consume/disarm any run-once test authorization before invoking native synthesis. On an interrupted prior run, show the failure and remain on Apple/Supertonic. Do not sweep compute routes or repeatedly reproduce a native crash.

### 4B. Native FluidAudio adapter, only under the decision above

At the existing pin:

```swift
let kokoroModel = KokoroAneManager(
    variant: .english,
    defaultVoice: "af_heart",
    computeUnits: .default
)
try await kokoroModel.initialize(preloadVoices: ["af_heart"])
let rendered = try await kokoroModel.synthesizeDetailed(
    text: utteranceText,
    voice: "af_heart",
    speed: 1.0
)
// rendered.samples + rendered.sampleRate feed the shared PCM player.
// After outstanding work drains:
await kokoroModel.cleanup()
```

- [ ] Use `synthesizeDetailed` for samples rather than encoding then decoding the WAV returned by `synthesize`. [F5][F6]
- [ ] Keep only English assets and one selected voice loaded. Add one other voice only if the first is unacceptable to the user.
- [ ] Include English G2P assets, vocabulary, lexicon, and voice data in preparation/offline checks. The English G2P singleton uses a shared default cache even when a custom chain directory is supplied. A missing lexicon can produce a degraded frontend, so record and resolve this before a quality comparison. [F5]
- [ ] Verify corrected stage assets expected by the pin, including `KokoroNoise_v2` and `KokoroTail_v2`. Do not combine old/new stage bundles from different downloads. [F6]
- [ ] Respect the phoneme/token limit. At the reviewed pin the detailed path is one-shot; inspect behavior rather than assuming long-text chunking exists. Split long text at sentence/word boundaries only as needed, preserve all text, and validate token counts. Never silently truncate the model input. [F5]
- [ ] Log actual per-stage routing/configuration. `.default` is OS-dependent and is not proof of safe or exclusive ANE execution.
- [ ] Use the same shared lifecycle/PCM/metrics code as Supertonic. No second player or conversation coordinator.
- [ ] Run only tests permitted by 4A; preserve native crash evidence and distinguish crashes from catchable inference errors.

### 4C. Contingency: Kokoro-82M ONNX CPU

This is a bounded alternative, not permission for an open-ended port. Use it only if selected at 4A.

1. Add a pinned, supported ONNX Runtime iOS distribution using its official integration guidance. Microsoft provides an official Swift Package Manager repository; prefer that route over CocoaPods/workspace restructuring or a custom runtime build. Verify its selected version and device/simulator slices, then record added app/framework size. [O1][O3]
2. Start with `onnx-community/Kokoro-82M-v1.0-ONNX`, `model_quantized.onnx`, the matching config/vocabulary, and `af_heart` voice data. Inspect graph input/output types from the actual pinned file; do not infer them from the filename. [O2]
3. Use CPU execution initially, without the CoreML execution provider. Start with a small explicit thread budget, such as two intra-op threads and sequential execution; measure before tuning. This avoids intentionally using the known Kokoro CoreML chain, but is **not** a guarantee of stability or speed.
4. First prove the acoustic model with a small offline-generated phoneme/token fixture for Appendix A. Include generation tool/version and exact text-to-token mapping. Mark this `ACOUSTIC-ONLY`: its timing excludes live text normalization/G2P and does not qualify normal Talk.
5. For live text, use a maintained, compatible English frontend or a small verified reuse of existing frontend components. Do not call `KokoroAneManager.phonemes(for:)` just for convenience: at this pin its English setup can load the seven CoreML graphs, defeating isolation and memory accounting. [F7]
6. Match the chosen ONNX export's contract: phoneme vocabulary, boundary IDs, length-indexed style vector, speed input, and full output waveform. Validate a short/long token case against its reference implementation. Include preprocessing latency/memory in the end-to-end results. [O2]
7. If live G2P requires a substantial new dependency or incompatible license, stop at the documented acoustic-only checkpoint and present that specific blocker. Do not label pretokenized fixtures an implemented general TTS replacement.
8. Once live text works, reuse Stage 3's Talk/lifecycle checks and Stage 5's comparison. Backend identity must say `kokoro82-onnx-cpu`; never mix its results with `kokoro82-coreml`.

**Gate:** chosen route, artifact/config identity, scope, and phone evidence recorded. `BLOCKED` is correct while an unresolved compatibility issue prevents the requested production use. Proceed to a full two-model comparison only with two appropriately usable routes.

**Stage note:** `Status: ___ | Route: ___ | Evidence: ___ | Human decision: ___ | Next: ___`

## Stage 5 - Matched phone comparison and sustained verification

**Outcome:** comparable evidence rather than a benchmark assembled from unrelated devices, voices, or cache states.

### Use two complementary tests

**A. Fixed-text TTS test:** no tutor generation or microphone recognition. Same corpus and shared playback path for Apple, Supertonic, and the chosen usable Kokoro route. This isolates speech behavior.

**B. Full conversation test:** existing ASR plus real tutor plus selected TTS. Measure total Send-to-audio and stage timings; do not call a faster tutor response a faster TTS model. Use the existing accepted synthetic ASR fixture path for repeatable automated replays where feasible, without changing decoding or retaining additional models. Real microphone checks remain paired with the user.

### Test procedure

- [ ] Record device/OS/build, route, voice, model/asset hashes, power state, Low Power Mode, audio output route, volume, thermal state, and debugger attachment.
- [ ] Prefer Release launched without an attached debugger for timed blocks. Use the same capture method across candidates; Instruments runs can be separate diagnostic runs.
- [ ] Begin with a cool/nominal phone. Keep speaker route and volume consistent. Record charging versus unplugged use; do not compare an AC desktop number to an unplugged phone number.
- [ ] Record first-ever TTS setup separately when naturally encountered. Do not erase ASR/model caches, reinstall, or reboot solely to manufacture a cold run.
- [ ] Measure fresh-process initialization with cached assets, first synthesis after initialization, and warm repeated synthesis as separate categories.
- [ ] Use one warmup phrase outside the measured corpus. For usable backends, run the 30-phrase corpus three times sequentially, preserving per-phrase results; report sample counts and failures.
- [ ] Keep only one neural backend loaded in each process. Run a fresh process for the next backend, and reverse the order in a second block to expose thermal/order effects. Switching a UI label is not evidence that all native memory was released.
- [ ] Repeat key phrases after several ASR turns with TTS still retained. Capture before/after ASR, tutor, synthesis, playback, and cleanup footprint.
- [ ] For a usable candidate, progress from 5 to 20 to 100 sequential cycles, stopping at any safety signal. Include a representative playback/conversation session of at least 20 minutes, not only a fast synthesis loop. The agent can automate synthetic cycles; the user need not manually speak 100 turns.
- [ ] Test End during initialization/synthesis/playback, rapid repeated Play, background during work, foreground recovery, and one route/interruption case supported by the available devices.
- [ ] Verify offline reuse and switching back to Apple. Do not touch real history to seed a benchmark.
- [ ] Export timing/memory records and a small selected WAV set. Only synthetic corpus speech is exported; normal private conversation text/audio stays out of reports.

A short or 20-minute successful Kokoro CoreML run does not clear the iOS 27 warning; upstream reports include a later failure. Keep that route experimental until there is relevant fix evidence and further qualification. [F8]

### Human quality comparison

Use 10 selected phrases with acknowledgments, questions, corrections, numbers, pronunciation contrasts, and one longer answer. Play matching A/B clips sequentially from saved synthetic outputs if useful; this avoids holding two managers. Keep natural model speed settings logged, and use a broadly comparable perceived speaking rate rather than assuming the numeric speed scales are equivalent.

Randomize which backend is A/B and keep the mapping in agent evidence. The user records `A`, `B`, or `tie`, plus any omitted word, wrong stress, awkward pause, hiss, or clipping. Do not ask the user to measure milliseconds already in logs. Native-listening preference is a practical product decision, not a formal population MOS study.

Preserve native-level WAVs. If loudness-adjusted listening copies are made, label them, use the same nonclipping method, and keep them separate from originals and performance measurement.

### Proposed engineering targets - not hardware guarantees

| Measure | Initial target / action |
|---|---|
| Crashes, Jetsam, memory warnings | Zero for a passing batch. Stop immediately on an observed event; do not retry unchanged. |
| Added TTS process footprint | Aim for ≤400 MB sampled increment over a matched current baseline, including auxiliary frontend and playback overhead. Treat larger values as review-required, not automatically impossible. |
| Combined process footprint | Initial conservative target ≤2.7 GB decimal; halt further test work if samples approach/exceed 3.0 GB. These are project test guards, not iOS limits or guarantees against unsampled spikes. |
| Warm request-to-playback-start estimate, short tutor phrases | Aim for p50 ≤300 ms and p95 ≤700 ms; report by phrase category. Measure first synthesis separately. |
| Warm synthesis RTF | Aim below 0.2 for ordinary sentence-length speech; also report absolute latency because one-word audio makes RTF unstable. |
| Stop responsiveness | Aim for audible stop within about 200 ms; measure native drain time separately. Never hide a long drain by reopening admission early. |
| Retained-memory trend | After initial warmup/cache growth, look for a plateau. Investigate continued growth across later cycles; no arbitrary byte-perfect return-to-baseline requirement. |
| Thermal behavior | Stop/allow cooldown at serious/critical thermal state; record fair state and latency drift. A cool short test is not a sustained pass. |
| Speech quality | No repeatable omissions or unintelligible critical phrases; user accepts the voice for teaching. |

Revisit targets only with recorded evidence and user agreement. Do not move a threshold simply to turn a failing run green. Memory sampling cannot guarantee catching the true instantaneous peak; preserve that limitation in the report.

**Gate:** functional, quality, latency, memory, and sustained results clearly distinguished. A blocked Kokoro route means the two-model comparison remains incomplete, even if Supertonic passes.

**Stage note:** `Status: ___ | Evidence: ___ | User preference: ___ | Remaining limits: ___`

## Stage 6 - Choose and promote narrowly

**Outcome:** a selected local voice with a simple rollback, not an expanding experiment framework.

- [ ] Fill the decision table below from phone measurements; use `NOT MEASURED` or `BLOCKED`, never estimates as results.
- [ ] Let the user choose after listening. Prefer Supertonic if quality is acceptable and it meets coexistence targets; choose Kokoro only if its actual runtime/OS reliability and resource costs are acceptable.
- [ ] Promote only the agreed backend for the intended local test build. Any broader public/default release is a separate explicit release decision.
- [ ] Keep an explicit Apple fallback/rollback path and preserve the existing Apple voice preference. Do not preload the nonselected neural candidate.
- [ ] Ensure preparation status and failure messages are understandable. Model files are downloadable caches/assets, not checked-in binaries.
- [ ] Include the exact applicable model/voice/runtime notices before distribution. Do not interpret this plan as legal clearance.
- [ ] Re-run a short selected-backend conversation and Apple rollback on the phone. Confirm restart, offline reuse, End, and saved-fragment behavior.
- [ ] Update this plan and `docs/tts/results.md`, including build identity, route, known limits, and next action. Commit only if the user's workflow authorizes it; no automatic push or merge.

| Result | Apple baseline | Supertonic-3 int4 | Kokoro-82M, route: ___ |
|---|---|---|---|
| Voice / speed / steps | NOT MEASURED | NOT MEASURED | NOT MEASURED |
| Actual phone / OS build | NOT MEASURED | NOT MEASURED | NOT MEASURED |
| Cached initialization / first synth | NOT MEASURED | NOT MEASURED | NOT MEASURED |
| Warm synthesis p50 / p95 | NOT MEASURED | NOT MEASURED | NOT MEASURED |
| Playback-start estimate p50 / p95 | NOT MEASURED | NOT MEASURED | NOT MEASURED |
| Aggregate RTF / generated duration | NOT MEASURED | NOT MEASURED | NOT MEASURED |
| Ready idle / max sampled footprint | NOT MEASURED | NOT MEASURED | NOT MEASURED |
| Combined ASR + tutor + TTS max sample | NOT MEASURED | NOT MEASURED | NOT MEASURED |
| End-to-end Send-to-audio | NOT MEASURED | NOT MEASURED | NOT MEASURED |
| Native drain / audible stop | NOT MEASURED | NOT MEASURED | NOT MEASURED |
| Warning / crash / thermal result | NOT MEASURED | NOT MEASURED | NOT MEASURED |
| Human quality preference / defects | NOT MEASURED | NOT MEASURED | NOT MEASURED |
| Accepted use / unresolved restriction | NOT MEASURED | NOT MEASURED | NOT MEASURED |

## Stage 7 - OPTIONAL: Kokoro-7M-Distill

**Do not start without an explicit go-ahead after the first comparison checkpoint.** This stage must not block Supertonic delivery or hide the Kokoro-82M compatibility decision.

The candidate is `oddadmix/Kokoro-7M-Distill`, with a community ONNX export at `Shadow0482/Kokoro-7M-ONNX`. The export provides FP32 and INT8 graphs plus the conditioned `af_msa` voice model. The tiny graph size does not include all runtime/frontend/activation memory, and there is no phone performance guarantee. [K1][K2]

- [ ] Recheck the model/export state and pin exact revisions, config, license, and hashes.
- [ ] First audition the model on the same conversational phrases. If quality clearly fails the user's needs, stop before adding an iOS runtime.
- [ ] Reuse the Stage 4C ONNX runtime/frontend only if it was actually implemented and compatible; otherwise record the new dependency cost before proceeding.
- [ ] Start with the provided INT8 graph and `af_msa.onnx`, not the 82M `af_heart` voice. Treat FP32 as a reference for a small parity check, not a second permanently loaded model.
- [ ] Inspect both ONNX graph interfaces. Match text normalization, vocabulary, boundary tokens, supported lengths, style-index convention, speed, and 24 kHz output. Do not assume the 82M and 7M style-index contracts are identical.
- [ ] Compare a few Swift frontend/token outputs with the pinned reference. The export's example still relies on a Python Kokoro/Misaki frontend for text processing; an acoustic ONNX graph alone is not a complete iPhone text-to-speech pipeline. [K2]
- [ ] Use the same PCM player, lifecycle, experimental selector, and measurements. No new conversation architecture or independent benchmark app.
- [ ] Repeat the staged smoke → live Talk → matched comparison gates, prioritizing one-word replies, questions, corrections, and expressiveness.
- [ ] Report total added runtime/frontend/model footprint and package size, not just model bytes. Add a result column only when there are actual results.
- [ ] Keep the already-selected backend as default unless the user explicitly chooses the 7M model after testing.

**Gate:** full live-text phone pipeline and human acceptance, or a documented scoped rejection/blocker. No custom distillation or CoreML conversion is required by this plan.

## Appendix A - Fixed, synthetic English corpus

Create one JSON resource with `id`, `category`, and `text`. Preserve IDs/text across all runs. These are authored test sentences, not private conversations or a downloaded benchmark.

| ID | Category | Text |
|---|---|---|
| 01 | acknowledgment | Yes. |
| 02 | acknowledgment | No. |
| 03 | question | Really? |
| 04 | acknowledgment | Exactly! |
| 05 | instruction | Try again. |
| 06 | question | What did you buy? |
| 07 | question | Where did you go yesterday? |
| 08 | question | Did you walk, or did you take the bus? |
| 09 | question | Can you say that in the past tense? |
| 10 | question | Why do you think that happened? |
| 11 | correction | Almost. Say, “I went,” not “I goed.” |
| 12 | correction | Use “an apple,” because “apple” starts with a vowel sound. |
| 13 | correction | That's a good start. Now try the whole sentence. |
| 14 | contrast | I said thirteen, not thirty. |
| 15 | contrast | Listen carefully: ship, sheep, ship, sheep. |
| 16 | number | It costs twelve dollars and fifty cents. |
| 17 | number | The total is $12.50. |
| 18 | time | Let's meet at 3:45 p.m. on Friday. |
| 19 | date | My appointment is on September 20, 2026. |
| 20 | number | The temperature fell from twenty degrees to minus five. |
| 21 | contraction | I don't know, but I'll ask her when she arrives. |
| 22 | prosody | You bought all of that? That's impressive! |
| 23 | pronunciation | Please record a short message about your favorite record. |
| 24 | proper name | My friend Maya lives in San Francisco. |
| 25 | punctuation | “Wait,” she said. “Are you sure?” |
| 26 | tutor reply | Yesterday you went to the supermarket and bought apples. What else did you buy? |
| 27 | tutor reply | You can say, “I usually cook at home, but yesterday I ate at a restaurant.” |
| 28 | tutor reply | Good job using the past tense. Tell me one more thing you did after work. |
| 29 | long answer | First, tell me where you went. Then describe what you saw and who you met. Finally, explain how you felt about the experience. Take your time; one short sentence for each part is enough. |
| 30 | long answer | Imagine that you're ordering lunch at a small café. Ask what the waiter recommends, choose a dish, and request a glass of water. If you don't understand the answer, ask the waiter to repeat it more slowly. |

Use 01, 06, 11, 17, and 29 for the first smoke batch. Use 03, 04, 06, 11, 14, 15, 17, 22, 26, and 29 for the human A/B batch. Add empty input, whitespace, Unicode punctuation, an unusually long sentence, and over-limit text as **validation cases**, not timed successful utterances.

Keep Vietnamese/mixed text out of the primary English ranking. An optional edge-case check can expose a graceful unsupported-input result, but it does not expand product language support.

## Appendix B - Measurements and evidence format

Use one monotonic clock. Keep elapsed intervals separate from wall-clock dates. Reuse existing OSLog events where possible and append a small JSONL record per completed/failed utterance so earlier evidence survives a crash. Flush at safe batch boundaries; do not log samples or private tutor text.

### Required definitions

- `prepare_ms`: manager initialization, including any compile/load work; first download time separately when identifiable.
- `first_synth_ms`: first generation after initialization; not mixed into warm percentiles.
- `synth_ms`: full text-to-waveform wall time, including frontend/chunking for a live-text pipeline; excludes playback and evidence export.
- `audio_ms`: sample count divided by the actual model sample rate.
- `rtf`: `synth_ms / audio_ms`; lower is better. Aggregate as sum of synth time divided by sum of audio duration, not average of per-phrase ratios.
- `request_to_playback_start_estimated_ms`: request admission to first output-render/start estimate. Record `timing_method`; do not call `player.play()` itself proof of sound reaching the user's ear.
- `playback_elapsed_ms`: actual playback interval; completion must not fire when audio is merely queued.
- `send_to_audio_ms`: existing user Send boundary to playback-start estimate for full conversations, separate from TTS-only latency.
- `stop_to_silence_estimated_ms` and `native_drain_ms`: separate user-visible stop and underlying work completion.
- Memory: store raw byte values for `phys_footprint`, any separately measured RSS, and available process memory when obtainable. Do not mix RSS and footprint into the same series or call an event sample a continuous peak. [A2]

For measurement builds, add periodic footprint sampling around 100 ms plus important stage boundaries, if the local tooling supports it without substantial overhead. Label the maximum as `max_sampled_phys_footprint_bytes`. Supplement with an Instruments/available high-water view when investigating unexplained peaks; keep instrumented timings separate.

A small record can look like this; null means not measured, not zero:

```json
{
  "schema_version": 1,
  "run_id": "replace-with-run-id",
  "phrase_id": "06",
  "mode": "tts-only",
  "backend": "supertonic3-coreml-ane-int4",
  "voice": "M1",
  "cache_state": "warm",
  "frontend_mode": "live-text",
  "sample_rate_hz": 44100,
  "synth_ms": null,
  "audio_ms": null,
  "request_to_playback_start_estimated_ms": null,
  "timing_method": "record-actual-method",
  "phys_footprint_before_bytes": null,
  "max_sampled_phys_footprint_bytes": null,
  "phys_footprint_after_bytes": null,
  "thermal_before": "not-measured",
  "thermal_after": "not-measured",
  "status": "not-run",
  "error_category": null
}
```

Store shared build, OS, asset, routing, speed/steps, power, and corpus-hash metadata once in a run manifest rather than duplicating everything in each line. Add failure and cancellation counts to summaries; do not calculate attractive percentiles after silently discarding failures.

Suggested local-only evidence layout:

```text
.build/verification/tts/<run-id>/
  environment.txt
  git-status.txt
  build.log
  install-launch.log
  scoped-device.log
  run-manifest.json
  utterances.jsonl
  summary.json
  human-notes.md
  selected-wavs/          # Synthetic clips only; optional.
  result.md
```

Keep large/raw evidence and model files uncommitted. Commit only concise sanitized summaries/config identities if authorized. Use existing scoped Mural-only logging procedures; no device-wide archives or automatic export of personal data.

## Appendix C - Local verification commands and human division of work

These are starting commands, not a substitute for the current verification skill. Confirm current Xcode help and project settings before use. The plan intentionally does not hard-code a device ID.

```sh
git status --short --branch
git rev-parse HEAD
xcodebuild -version
swift --version
xcrun devicectl list devices
xcrun simctl list devices available
swift test
```

Physical Release build pattern, preserving the paired bundle and the documented existing Core AI flag where still applicable:

```sh
: "${DEVICE_UDID:?Set the freshly discovered paired iPhone 17 UDID}"
export APP_BUNDLE_ID=com.kevintruong.mural.dev
export DEVICE_DERIVED_DATA="$PWD/.build/tts-device-derived-data"
export EVIDENCE="$PWD/.build/verification/tts/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE"
set -o pipefail

xcodebuild \
  -project Mural.xcodeproj -scheme Mural -configuration Release \
  -destination "platform=iOS,id=$DEVICE_UDID" \
  -derivedDataPath "$DEVICE_DERIVED_DATA" \
  PRODUCT_BUNDLE_IDENTIFIER="$APP_BUNDLE_ID" \
  OTHER_SWIFT_FLAGS='$(inherited) -D MURAL_COREAI_TALK -D MURAL_TTS_EXPERIMENT' \
  build 2>&1 | tee "$EVIDENCE/build.log"

export DEVICE_APP="$DEVICE_DERIVED_DATA/Build/Products/Release-iphoneos/Mural.app"
test -d "$DEVICE_APP"
xcrun devicectl device install app --device "$DEVICE_UDID" "$DEVICE_APP"
xcrun devicectl device process launch \
  --device "$DEVICE_UDID" --terminate-existing "$APP_BUNDLE_ID"
```

`MURAL_TTS_EXPERIMENT` is **proposed by this plan** and must be implemented before it has any effect. Preserve any additional current required flags rather than overwriting them. If source/build settings supersede the historical `MURAL_COREAI_TALK` recipe, document the correction and verify runtime identity. Do not enable phone-specific ASR probes in simulator builds. Verify the compiled app's identifier and compiler invocation before installation. [R5]

The local agent should build, install in place, launch, collect scoped evidence, automate synthetic synthesis, compute summaries, and update this document. The user should unlock/authorize the phone as necessary, listen to voice quality, perform real microphone/route interactions, and choose the preferred voice.

Use simulator for selection UI, disabled/busy/error states, navigation, and mock lifecycle tests. Simulator success is not proof of iPhone acceleration, memory, thermals, microphone routing, or listening quality. A CoreML simulator limitation need not block an otherwise buildable physical-device test.

For real microphone checks, fully quit Device Hub as directed by the existing skill; a recording timer alone does not prove input audio was captured. Before asking for a batch, start or reuse the scoped capture and record its ownership/offset. Ask for a simple “done” or approximate failure time; retrieve logs yourself. Do not use the premium-only `--verify-audio` or `--verify-meaning` helpers as proof of local TTS. [R5]

Stop/clean up only logging processes the agent owns. When hardware is unavailable, finish applicable machine checks and mark phone checks `BLOCKED` or `PENDING HUMAN`, not `PASS`.

## Appendix D - Per-stage completion note

Append one entry for every checkpoint, including failed ones. Update the progress board and current handoff at the same time.

```text
Date / stage / status:
Source HEAD + local diff:
Changed files:
Dependency/model/voice identities:
Actual installed build and phone OS:
Machine checks run and results:
Physical checks actually run:
Human report, distinguished from agent observation:
Latency / memory / lifecycle result:
Warnings, crashes, skipped checks, known limitations:
Evidence paths:
Decision / exact next action:
```

**Suggested first instruction to the implementing agent:**

> Read this plan and the current verify-mural local-conversation workflow. Start at Stage 0 on the current MVP checkout, preserve unrelated work and the existing ASR backend, then implement the minimal seam and Supertonic stages. Update the checkboxes/evidence as you go. Stop at each required paired listening checkpoint. Do not run warned Kokoro CoreML inference automatically, change public defaults, or begin the optional 7M stage.

## References

Repository links below are pinned to the reviewed snapshot. Follow the current checkout for implementation and note any differences. Upstream links marked `main` are discovery references; pin actual model bytes/revisions for test reproducibility.

[R1]: https://github.com/aidynamicsolutions/mural/blob/185696849b35fd6b70474f8929232b3a88cb2ec1/App/LocalConversationEngine.swift
[R2]: https://github.com/aidynamicsolutions/mural/blob/185696849b35fd6b70474f8929232b3a88cb2ec1/Mural.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
[R3]: https://github.com/aidynamicsolutions/mural/blob/185696849b35fd6b70474f8929232b3a88cb2ec1/App/ConversationCoordinator.swift
[R4]: https://github.com/aidynamicsolutions/mural/blob/185696849b35fd6b70474f8929232b3a88cb2ec1/docs/coreai/hybrid-memory-checkpoint.md
[R6]: https://github.com/aidynamicsolutions/mural/blob/185696849b35fd6b70474f8929232b3a88cb2ec1/docs/coreai/staged-product-gate-checkpoint.md
[R5]: https://github.com/aidynamicsolutions/mural/blob/185696849b35fd6b70474f8929232b3a88cb2ec1/.agents/skills/verify-mural/features/local-conversation.md
[F1]: https://github.com/FluidInference/FluidAudio/blob/41540ea237350afe5117a082b5c28eda642d0612/Sources/FluidAudio/TTS/Supertonic3/Supertonic3Manager.swift
[F2]: https://github.com/FluidInference/FluidAudio/blob/41540ea237350afe5117a082b5c28eda642d0612/Sources/FluidAudio/TTS/Supertonic3/Supertonic3Types.swift
[F3]: https://github.com/FluidInference/FluidAudio/blob/41540ea237350afe5117a082b5c28eda642d0612/Sources/FluidAudio/TTS/Supertonic3/Assets/Supertonic3ResourceDownloader.swift
[F4]: https://github.com/FluidInference/FluidAudio/blob/41540ea237350afe5117a082b5c28eda642d0612/Sources/FluidAudio/TTS/Supertonic3/Pipeline/Preprocess/Supertonic3TextChunker.swift
[F5]: https://github.com/FluidInference/FluidAudio/blob/41540ea237350afe5117a082b5c28eda642d0612/Sources/FluidAudio/TTS/KokoroAne/KokoroAneManager.swift
[F6]: https://github.com/FluidInference/FluidAudio/blob/41540ea237350afe5117a082b5c28eda642d0612/Sources/FluidAudio/TTS/KokoroAne/Pipeline/KokoroAneSynthesizer%2BTypes.swift
[F7]: https://github.com/FluidInference/FluidAudio/blob/41540ea237350afe5117a082b5c28eda642d0612/Sources/FluidAudio/TTS/KokoroAne/KokoroAneManager.swift#L330-L405
[F8]: https://github.com/FluidInference/FluidAudio/issues/889
[F9]: https://github.com/FluidInference/FluidAudio/blob/main/Documentation/TTS/Benchmarks.md
[F10]: https://huggingface.co/Supertone/supertonic-3/blob/main/LICENSE
[K1]: https://huggingface.co/oddadmix/Kokoro-7M-Distill
[K2]: https://huggingface.co/Shadow0482/Kokoro-7M-ONNX
[O1]: https://onnxruntime.ai/docs/get-started/with-mobile.html
[O2]: https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX
[O3]: https://github.com/microsoft/onnxruntime-swift-package-manager
[A1]: https://developer.apple.com/documentation/avfaudio/avaudioplayernodecompletioncallbacktype/dataplayedback
[A2]: https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use

## Checkpoint: September 20, 2026 / Stage 0 / PENDING HUMAN

- Source: current `mvp` at `f81d6654399191d2aa2f9bac46fc0176b8a71964`; no app changes. Added this plan and `results.md`.
- Machine checks: 91 core tests passed; ordinary Release build/install/launch passed. Exact executable, phone, dependencies, notices and commands in `results.md` and `.build/verification/tts/stage0-20260920/`.
- Current-source correction: packed-v3 FP8 encoder/PAL8 decoder is the default without opt-in flags, unlike historical verification instructions. ASR/tutor/voice settings and caches unchanged.
- Physical checks: install and launch observed, staged backend launch event captured. No agent listening, microphone or performance acceptance. Human result pending.
- Remaining evidence: prepared/ready/runtime model events and one successful Apple-spoken exchange. Scoped Mural-only capture bounded to 15 minutes; ownership file records cleanup.
- No neural implementation, model acquisition, Kokoro native inference, optional Stage 7, commit or push. Exact next action is the baseline phone checklist in `results.md`.

## Checkpoint: September 20, 2026 / Stage 0 / PASS

Human confirmed the entire short Apple baseline checklist. Captured prepared/ready events identify current FP8/PAL8, with completed Apple greeting and reply. Actual Apple resolver selects regional Karen Premium en-AU, not the obsolete top-level en-US helper. See `results.md` for exact timing/memory definitions and the external HEAD change preserved during this stage. Scoped capture stopped. Next: Stage 1; no neural model loading yet.

## Checkpoint: September 20, 2026 / Stage 1 / PASS

User replied done to the complete Apple/PCM/Stop/Talk checklist. Both phone PCM rates completed and Apple phrase 29 was cancelled in retained synthetic reports. Native simulator lifecycle tests and 92 core tests passed. Talk regression is human-confirmed; captured logs prove its preparation/greeting but do not contain a later Record/Send/reply. Scoped logging stopped. Stage 1 remains the installed phone build.

## Checkpoint: September 20, 2026 / Stage 2 / BLOCKED

Standalone Supertonic int4/M1 adapter implemented and signed Release built; Talk remains Apple. No model download or neural inference has occurred. Core tests (92), actual pinned chunker/token-window checks and focused simulator PCM/lifecycle test pass. Initial simulator result-finalization timeout was resolved by a bounded final check with verbose diagnostic collection disabled and the helper stopped; complete result bundle retained.

The paired iPhone became unavailable before Stage 2 installation. Build `7b1c9b485df56cc565766405b0af42cad8a01d8e3ce67d4fac8f6e93624c2b8c` is saved at `.build/verification/tts/stage2-20260920/Mural.app`. No phone capture remains active; owned simulator resources cleaned up. Reconnect/unlock, install that build, start a new scoped capture, launch `--tts-comparison`, then request explicit Supertonic Prepare and Run smoke check (5 phrases). After successful preparation, also verify Stop and fresh-process offline phrase 28. Inspect acquired inventory and reports before marking PASS. No Stage 3, Kokoro inference, optional Stage 7, commit or push yet.
