# Breeze for Simplified Chinese: implementation and acceptance

Date: 2026-09-28. Base: aidynamicsolutions/mural `mvp` at
`a73d8163355fb2137d552196677c1b722840d9df`.
Source candidate, not native acoustic acceptance or release qualification.
See the local qualification checkpoint below for the signed build and remaining gates.
This replaces the direction of the previous FireRed/SenseVoice patch proposals; do not stack them.

## User contract

With On-device mode and English learning, Meaning language is the only user selection:

| Meaning language | Recognizer | New spoken-turn presentation |
|---|---|---|
| Simplified Chinese | The existing verified Breeze PAL8 | Derived Simplified Han glyphs, English unchanged |
| Traditional Chinese | The SAME Breeze model/assets | Existing raw/canonical presentation unchanged |
| Vietnamese | Existing PhoWhisper/Core AI phone configuration | Unchanged |

Breeze recognizes Mandarin and English, not an acoustic “Simplified script.” The added layer renders characters after recognition. No training, new ASR weights, language forcing, ASR quantization or transcript repair. Existing 16 kHz conversion, 30-second cap, VAD, decode options, tutor and English voice remain.
The user's report of extensive warning-free Breeze use is positive human experience, not a new measured resource guarantee. This project does NOT restart the FireRed memory investigation.

## Library and reason for selecting it

Use `ddddxxx/SwiftyOpenCC`, exact revision
`1d8105a0f7199c90af722bff62728050c858e777`, SwiftPM product `OpenCC`.
This is an older (2021) community wrapper, NOT the latest upstream OpenCC.
Its manifest builds its C++14 `copencc` target and bundles dictionaries. The OpenCC submodule is
`be3af873de7d9ca28c274b4a917d9fcd953345cf`.
Its actual source API is `ChineseConverter(options: [.simplify, .twStandard])`.
Do not copy the older documentation's singular `option:`/uppercase option spelling.

Pinned source review:
- https://github.com/ddddxxx/SwiftyOpenCC/blob/1d8105a0f7199c90af722bff62728050c858e777/Package.swift
- https://github.com/ddddxxx/SwiftyOpenCC/blob/1d8105a0f7199c90af722bff62728050c858e777/Sources/OpenCC/ChineseConverter.swift
- https://github.com/ddddxxx/SwiftyOpenCC/blob/1d8105a0f7199c90af722bff62728050c858e777/Sources/OpenCC/DictionaryLoader.swift
- https://github.com/ddddxxx/SwiftyOpenCC/blob/1d8105a0f7199c90af722bff62728050c858e777/Sources/OpenCC/DictionaryName.swift
- https://github.com/BYVoid/OpenCC/tree/be3af873de7d9ca28c274b4a917d9fcd953345cf

The chain is `TWVariantsRevPhrases` + `TWVariantsRev`, then `TSPhrases` + `TSCharacters`; segmentation uses TSPhrases. It converts Taiwan glyph variants and Traditional-to-Simplified spelling. Deliberately omit `.twIdiom` (the regional-vocabulary route). For example, 軟體 becomes 软体, NOT 软件; 滑鼠 stays 滑鼠, NOT 鼠标. No learned model or network service is involved.

Mural's boundary passes only single-scalar Han-grapheme runs to the library. It copies English, numbers, punctuation, whitespace, emoji, NUL and all other graphemes byte-for-byte. A Han+variation-selector grapheme is intentionally preserved whole; exotic variants may therefore remain unsimplified. This is safer than breaking a rare name/glyph sequence. Dictionary-based script conversion can still be contextually imperfect; it does not establish lexical ASR correctness.

Licenses: wrapper MIT; OpenCC Apache-2.0; marisa and darts-clone BSD-2-Clause routes. Full selected notices are bundled in MuralCore and appended to the existing Settings notices screen. The marisa BSD alternative is selected. Pinned OpenCC's darts header lacks a separate COPYING file; the bundle includes the original project's inspected COPYING.md notice with its Git blob identity. Verify dependency checkout/source notices before distribution. No ASR model license is replaced by these licenses.

## Separation of data and roles

1. `rawASRText` remains the EXACT native result, including its existing whitespace.
2. `Fragment.text` and `Passage.text` remain the existing canonical text (including prior app whitespace handling). Tutor/history prompts, learning evidence and revision keys continue to use them.
3. A new optional `scriptPresentation` stores canonical source text, derived display text, and `tw2s-han-1d8105a0-v1` policy identity. Only new finalized spoken USER turns in a frozen Simplified session receive it. Typed messages, assistant messages, premium/legacy streaming fragments and old history do not.
4. UI uses `displayText`, while transcript/history exposes exact original recognition in a disclosure. The snapshot is saved once, never regenerated on every SwiftUI render or from current Settings.
5. Backups round-trip the optional snapshot; old schema-2 records need no migration. Import validation checks source/role/pair/bounds and non-Han run preservation. This is structural validation, not cryptographic authentication of an imported transcript or independent dictionary proof.
6. An explicit user edit clears the stale projection, retains `rawASRText`, and uses existing revision/learning invalidation. Edit starts with the displayed wording. Later preference/library changes do not rewrite history.

The native result is persisted BEFORE awaiting conversion. End/background/cancellation while converting cannot retroactively erase that saved turn. Session, foreground, source and admission checks prevent a late projection from crossing into another session. Conversion failure is an error, not a silent fallback to another model or a rewritten transcript.

## Efficiency and unchanged native resources

One actor owns one process-lifetime converter. The wrapper has no explicit Swift teardown for its converter in the reviewed source; do not create one per turn or per view. It is constructed lazily only for Simplified setup, reused serially, and is not repeatedly recreated on End/Resume. Whole-text and output bounds match existing archive-scale limits. Only short bounded text conversion is added, not a second resident recognizer. No numeric latency/footprint reduction is claimed.

BreezeEnglishRecognizer.swift and its pin remain byte-for-byte untouched. Both writing modes resolve `.taiwanMandarinEnglish` asset ownership through the same managed-or-retained Breeze path. The CN conversation/support locale remains `zh-Hans-CN`; it is NOT changed to `zh-Hant-TW` just to find the model. Initial and paused-session preparation receive the explicit frozen pair.

Historical FireRed catalog entries and `active-zh-CN-en.json` are retained. New setup maps asset requests to Breeze; CN managed-delete is refused with a shared-assets explanation, so it cannot accidentally delete FireRed or shared Breeze content. Existing Traditional Chinese management remains the explicit shared-asset action.

Important scope: at this base the reviewed catalog does NOT publish Breeze for new downloads. Existing verified Breeze on this phone is reused, with full hashing still required before native load. Missing/corrupt Breeze fails; it must NOT offer FireRed, invent hosting, copy unverified weights, or delete caches. This delivery does not solve whole-app first-install Breeze distribution.

## Change tracks (apply in order; not competing alternatives)

- 01: Core snapshot/policy/actor, pinned package dependency, notices, asset-pair and setup-contract identity, optional persistence field and invalidation.
- 02: Shared Breeze routing, initial/resume admission and selected-pair diagnostics, post-ASR projection attachment, Talk/history display, raw disclosure and notices UI. Includes a simulator-only fixture in the existing preview path.
- 03: Focused test-first Core checks, two existing-suite UI additions, updated meaning-language mapping regression, and this implementation record.

Keep them as separately reviewed source commits locally if helpful. No force push/rebase/reset/stash or automatic release.

## Required host/simulator checks before installation

Resolve the pinned SwiftPM dependency and its submodule on the Mac; the online environment could not build that native dependency. Verify exact revisions, unmodified checkout, all required dictionary resources and notices. Record root and Xcode Package.resolved changes; preserve every pre-existing dependency revision. Do not upgrade FluidAudio/WhisperKit or swap OpenCC to a moving branch to make a build pass.

Run `swift test --filter ChineseScriptPresentationTests` and the existing `LocalSpeechPairPersistenceTests`. Actual OpenCC goldens are mandatory: synthetic maps do not validate native dictionary output. A failed golden needs investigation/reviewer input, not changing expected text to whatever the implementation produced.

Generate the ordinary project (no FireRed or compact-candidate flags). Use existing simulator ownership/bounds with these relevant test methods:
- `testBreezeSimplifiedDisplayPreservesRawRolesAndEnglish`
- `testSimplifiedBreezeMissingAssetsDoesNotOfferFireRed`
- `testMeaningLanguageSelectsOnDeviceRecognizerAndUnsupportedCombinationsFailClosed`
- `testSpeechSetupCancelKeepsAdmissionClosedUntilDrain`

The first uses actual OpenCC, actual archive codec and actual transcript UI with synthetic text in the existing in-memory `--preview` store. It does not load Breeze, play sound or simulate acoustic success. Preserve screen recording, compact test results and cleanup/Shutdown evidence.

## Focused physical acceptance — paired workflow, not the old FireRed runner

The user has requested local build/install/E2E. Prepare first, then obtain current idle/unlocked/cool and listening readiness under the existing ownership rules. Reuse installed bundle/signing and preserve the explicit Vietnamese Core AI Release flag. Use the qualified PAIRED workflow in verify-mural: build/install/current-PID scoped capture by agent, normal UI and speech/listening by the human. Native XCTest is optional; do not invent a new phone harness.

DO NOT run the existing `DEVICE_PAIR=zh-CN-en` preparation/resource/acoustic stages unchanged: they encode FireRed build/identity/stop assumptions at this base. Default `DEVICE_STAGE=prepare` is build-only and may be reused for the ordinary Core AI artifact after pinned dependency resolution; its vi-en label is NOT a request to run Vietnamese speech. Runtime acceptance here follows the paired workflow, not a relabeled FireRed test result.

One short session should cover:
- Settings English + Simplified Chinese, normal Prepare, real Breeze-ready/inference markers. No FireRed/compact model creation or duplicate Breeze load.
- Mixed speech with both switch directions, English technical terms/name/number, and an English-only or short reply. Preserve observed raw text separately from derived display and human word-quality feedback. Do not score prompt text against an unsaved recording.
- Actual English tutor/voice and Simplified meaning/lookup/Help. Chinese assessment stays disabled; no Chinese Help playback.
- End, normal relaunch, only the new test conversation in history: display and original recognition remain distinct. Edit a test-only passage; projection invalidates and original remains. No personal history modification or whole-store export merely for this check.
- Select Traditional Chinese for a new conversation; same asset identity and unchanged raw display. Confirm Vietnamese still maps to its preserved backend. Use extra acoustic regression only where changed shared contracts require it.

Stop at first memory warning, crash, serious thermal state, model/asset failure or unresponsive native work. Never free native handles during synchronous work, raise limits, change VAD/provider/weights, retry blindly or delete models. Record measured preparation/Send-to-final and observed warning/thermal state; the result is bounded acceptance, not a sustained-use guarantee. No compulsory six-minute FireRed investigation or new allocator profiling is part of this script-only feature.

## Local qualification checkpoint: September 30

Applied all three delivery patches on `mvp` at `f0ed90259af11741a3d3860efefc879b0249b4c0`.
The base verifier refused the newer committed `AGENTS.md`; every other base blob
matched and the complete checkout passed the three-patch context/whitespace check.
The updated instructions were preserved, and the applied delivery verifier passed.

- Host: 28 injected-map production boundary/persistence assertions passed. The real
  pinned OpenCC suite passed all eight methods, with eight dictionary/presentation
  goldens including added variation-sequence and mixed Han/English/decomposed accent,
  whitespace, emoji and NUL cases. Existing LocalSpeechPairPersistenceTests: five passed.
- Dependency: exact clean wrapper and OpenCC submodule in both actual build checkouts.
  All 16 dictionaries and the MuralCore notice are byte-equal in the simulator and signed
  phone app. Real C converter symbols are linked. Existing Xcode pins are unchanged;
  only the requested SwiftyOpenCC revision was added. Root Package.resolved is retained.
- Model-free UI: all four requested checks passed across bounded runs. The first run
  exposed an old embedded MuralCore bundle missing the new notice. Preserve that failure;
  moving only the stale copied build-product bundle under its DerivedData lock forced
  normal Xcode embedding. No installed app, model, or model cache was removed.
  The next combined run passed three checks but hit its work budget during cancellation;
  it remains a failed run. The remaining cancellation/drain check passed alone in 230.44 s.
  Every owned simulator cleanup passed and confirmed Shutdown. All four completed-test
  recordings passed strict source decoding; display/disclosure frames were inspected.
- Small integration corrections: the existing generator retains native screen recordings
  on success/failure, and the new fixture test returns immediately after setup failure
  instead of continuing gestures. No assertion, timeout, recognizer, VAD or resource limit
  was weakened. Original golden expectations were preserved.
- Signed phone artifact: ordinary default build-only `DEVICE_STAGE=prepare`, explicit
  Core AI Release, existing app/runner identities. Total preparation including cleanup:
  56.77 s; signed build: 54.78 s. Actual app compiler evidence includes MURAL_COREAI_TALK
  and no FireRed/compact/CTC candidate flags. Signing and bundled OpenCC are verified.
  This build did not install, launch, or run models.
- Paired handoff: user confirmed an initial idle/unlocked/cool window and selected the
  short scripted batch, with final preference On-device / English / Simplified Chinese.
  Only the freshly bundle-verified idle PID was stopped. A new matching Mural process
  appeared before installation; preflight preserved it and refused install/launch.
  Fresh idle confirmation then timed out. Owned host work is stopped; phone settings,
  installed binary, model/pointer/cache files and history were not changed by this run.
- Native word accuracy, Simplified rendering, English reply/voice, meanings/lookup/Help,
  Traditional shared-model behavior, persistence/explicit edit, and memory/thermal
  observations are **NOT RUN**. Actual final phone preferences were not read; they remain
  unchanged, not proved to match the requested final preference.

Private evidence: `.build/verification/breeze-simplified-20260930-122221/`.
Before resuming, obtain fresh idle readiness, discover and verify current ownership,
then install the exact qualified artifact normally. Compare the supplementary source
manifest, both package locks, resources and executable identity too: the existing device
preparation receipt hashes tracked source files only, so it does not independently cover
new untracked delivery files. Do not reuse its receipt alone after editing those files.
Do not run the old zh-CN-en FireRed runtime stages or claim native acceptance from the
synthetic checks. No source commit, push, model transfer or binary rollback was performed.

## September 30 native continuation: paused, not production-qualified

This checkpoint supersedes the initial NOT RUN status above without changing its
historical failures. Source remains uncommitted on mvp at f0ed9025; no push occurred.

- The user confirmed using the existing MuralUITests-Runner against
  com.kevintruong.mural.dev, preserving data and touching only new conversations.
  Mac-speaker input was explicitly authorized. No extra app/runner identity, room
  capture, model transfer, cache reset, backend fallback or VAD/limit change occurred.
- Real converter/persistence/host checks and focused synthetic UI evidence above remain
  passing. Device receipts now hash untracked delivery sources too. Default Core AI
  Release and an isolated diagnostic build both passed actual compiler/signature,
  linked OpenCC, exact pin/submodule, 16-dictionary and notice-bundle checks.
- Initial native readiness used a borrowed 90-second VI wait; Breeze actually loaded in
  about 168 seconds despite a receipt hit. That run failed and cleanup was unconfirmed.
  Separate ownership/settings recovery passed. Cancel-setup/ready-End selectors were
  qualified model-free on the retained simulator: two tests PASS, cleanup PASS, Shutdown.
  A measured 200-second Breeze readiness wait retains the 300/420-second test budgets.
- Normal-policy acoustic run automation-acoustic-02 decoded the clip and emitted the
  display marker, then received an actual iOS memory warning before the reply completed.
  Native abort/drain/settings restoration/termination passed. This is a failed run,
  not permission for an automatic replay or a successful acoustic qualification.
- The user separately authorized a bounded memory-warning diagnostic. Only with
  DEVICE_BREEZE_MEMORY_POC=YES, the isolated signed build adds MURAL_BREEZE_MEMORY_POC
  and logs active Breeze warnings without pausing. Normal builds retain their guard.
  Thermal stops, the existing memory ceiling, model-error stops and time budgets remain;
  no OS thermal/memory protections were overridden. Host checks retain those failures.
- memory-poc-acoustic: one native XCTest passed, a real spoken turn and English reply
  completed through a memory warning, and the user heard the full English reply clearly.
  Peak recorded process footprint: 2,039,777,864 bytes; thermal states nominal/fair only;
  no observed OS termination. ASR readiness: 167.08 seconds, actual load: 166.08 seconds,
  despite a receipt hit. Whole runtime including cleanup: 286.56 seconds; build separate.
- Recognition was not accepted: the reviewed M00A-switch Mandarin words were returned
  in English. Raw and displayed text were identical English; this does NOT prove native
  Han simplification. The scoped transcript screenshot shows distinct original-recognition
  disclosure and Simplified meanings. Do not repair the ASR words with the script layer.
- The full host result failed: an application-level downward scroll was followed by an
  unrelated-app interruption, pause/return and a second preparation selection. Failure
  remains saved, not relabeled as a full pass. The recording fully decodes (7,691 frames,
  265.83 seconds); unrelated-app frames were not inspected. Content-bounded gestures,
  a foreground guard and a model-free scrolling regression are compiled, not yet run.
- Next reviewed one-clip input is F00A-switch. Corrected ordinary and diagnostic runner
  receipts are ready. User selected WAIT, then the read-only phone request was unavailable.
  Do not install/launch/play while unavailable. All owned host playback/capture/test work
  exited; the last native cleanup and empty-phone inventory passed. Simulator is Shutdown.
- IMPORTANT: the diagnostic is still installed and terminated. Restore the ordinary
  feature build under fresh readiness before daily use. Last independently read-back
  preference was On-device / English / Traditional Chinese. The requested final
  Simplified preference is still pending, not silently asserted or changed afterward.
- Native Han rendering, Mandarin accuracy, lookup/Help, durable reopen/explicit edit,
  a new Traditional shared-model session and technical-name/number coverage remain open.
  No broad qualification, lifetime safety proof or quantization improvement is claimed.

Private evidence stays under `.build/verification/breeze-simplified-20260930-122221/`,
including `memory-poc-paused-closeout.json`, `memory-poc-artifacts.json`, the failed
`memory-poc-acoustic` host result, its human-acceptance record and scoped screenshot.
`memory-poc-normal-prepare-02/prepared.json` is the ordinary restoration artifact;
`memory-poc-prepare-02/prepared.json` is the corrected diagnostic runner, not daily use.

## September 30 resumed native checkpoint: display PoC passed, acoustic qualification incomplete

This supersedes the paused/installed-diagnostic state above, preserving all earlier
failures. No ASR model, pin, provider, VAD, limit, voice, model/pointer/cache file or
personal conversation was replaced. No commit or push occurred.

- Source/dependency: the three delivered patches remain applied. The pinned wrapper's
  TWVariantsRev maps literal Simplified 么 to 幺. A real native support assertion exposed
  this violation of already-Simplified stability. Three additional real goldens failed
  first; the renderer now preserves this ambiguous input without repairing wording.
  Traditional 麼 still simplifies, and legitimate 幺 remains unchanged. Pins/options
  remain unchanged; saved projections are never recalculated. All eight Core methods /
  eleven real goldens, five persistence tests and 28 injected-map boundary assertions pass.
- Model-free UI: centered, content-bounded scrolling passed before model work. The
  expanded script fixture, including existing Simplified text, passed real converter /
  archive / disclosure / edit checks in 146.7 s through cleanup and simulator Shutdown.
  Its screenshot was inspected and source recording fully decoded. Native Mandarin
  recording samples were separately inspected at 20-second intervals, not full motion.
- Native Mandarin: resume-mandarin-acoustic passed both host and one native XCTest,
  with one actual Breeze load/inference/selection, frozen zh-CN-en and distinct raw /
  Simplified display; English case/spacing stayed exact. The reviewed Mandarin reference
  matched after writing-script/whitespace equivalence, not transcript repair. Actual
  English reply and speech completion occurred, but the user could not confirm listening
  to this turn. Simplified meanings are visible in the scoped transcript screenshot.
  Whole runtime including cleanup: 260.27 s; ASR readiness 169.56 s / load 168.50 s;
  peak recorded footprint 2,035,239,568 bytes; thermal nominal/fair. A logged active
  Breeze memory warning continued only under the explicitly authorized diagnostic.
- Native persistence/edit: native-breeze-history-02 passed in 111.64 s through cleanup
  on the ordinary build, with no ASR model reload. Only the successful new test UUID was
  opened. Its exact display/raw survived a future Traditional preference and relaunch.
  The editor began with display wording; explicit save removed the stale projection,
  and a second relaunch retained edited canonical text plus the exact original ASR.
- Native support failures: native-breeze-support produced incorrect English-only words
  and stopped on the converter stability assertion before lookup/Help. After the
  concrete converter fix, native-breeze-support-corrected completed real inference but
  returned no words; the actual UI said No speech recognized. There was no turn reply.
  Both remain failed runs with cleanup PASS, not acoustic acceptance. The latter's
  recording attachment was a pending-attachment error, not playable movie evidence;
  its scoped native hierarchy and app logs are retained. No further acoustic replay,
  automatic retry, transcript repair or backend/VAD change followed.
- Harness corrections: a pre-termination intent resolves console/stdout teardown races
  without weakening final test/settings/cleanup assertions. The original false-positive
  host failure stays saved. Missing recognition now fails promptly with a scoped screen
  and the actual notice instead of repeated raw-disclosure gestures. Lookup uses the
  actual native Link role. These latter branches compiled but remain runtime-unqualified.
  Protected automation-mode startup failures and separate ownership recovery are retained.
- Signed final state: ordinary Core AI Release is installed in place under the existing
  main/runner identities, with no diagnostic define. Actual compiler/executable proof,
  strict signatures, linked OpenCC and dictionary/notice evidence are retained. The final
  prepared main executable is byte-identical to the corrected ordinary artifact.
  final-native-dictionary passed one native test, including real pinned converter goldens
  on iPhone without ASR models, final settings readback and cleanup, in 51.92 s.
  Final preference: On-device / English / Simplified Chinese. Owned playback/capture/test
  work ended; the phone was not shut down. The retained simulator is Shutdown.

This proves a bounded native Simplified-display/persistence PoC, not broad recognition
accuracy, sustained resource safety or quantization benefit. Normal memory-warning
pausing remains enabled in the installed app; serious/critical thermal stops were never
bypassed. English-only and earlier mixed-language accuracy failures remain. Native
lookup/Help, Chinese Help non-playback after an actual Help action, fresh reply listening,
technical-name/number accuracy and a new Traditional acoustic session are unqualified.
Vietnamese diagnostics and the actual Core AI configuration were preserved; no new
Vietnamese acoustic claim is made. Private closeout and exact identities are under
`.build/verification/breeze-simplified-20260930-122221/native-continuation-closeout.json`.

## September 30 warning UX follow-up: ordinary phone update installed

The user reports accurate live English transcription with the most recent ordinary
Simplified Chinese build, then repeated Resume after about the second turn. This is
human feedback for that voice, not a frozen-reference accuracy benchmark or proof that
accent caused the earlier prerecorded failures. No personal recording/history was accessed.

Retained native evidence shows the ordinary `asr_memory_warning stopped=true` event
followed by `local_paused` about 20 ms later. The shared normal Talk observer now logs
`asr_memory_warning stopped=false continuing=true` without calling `stop()` or the
coordinator safety callback. It does not interrupt preparation, capture, inference or
reply merely because UIKit sent a warning. The Resume control is not cosmetically hidden:
the existing sampled 3,000,000,000-byte ceiling, serious/critical thermal guards, actual
model failures and drain/explicit-recovery behavior remain unchanged. iOS may still
terminate the app; this is not a sustained-memory safety guarantee or memory optimization.

Focused model-free evidence:
- Repeated notifications during approved Simplified setup and after synthetic turns:
  2 PASS / 0 failed / 0 skipped in the corrected focused run.
- Sampled-ceiling setup interruption, ceiling pause/drain/explicit resume with retained
  turns, and thermal alert/recovery: 3 PASS in the preceding run on the same production
  implementation.
- Host classification: only the explicit non-stopping notification is advisory; old
  warning stops, probe warnings and genuine faults still fail. Host checks PASS.
- Initial tests incorrectly required an enabled microphone without loaded models.
  Scoped screenshots/hierarchy proved Ready with no Resume and an intentionally disabled
  Record control. Corrected measurements assert actual warning handling, not acoustic
  readiness; all failed attempts remain retained.

Each simulator run used the retained owned device and SimSlim 0.11.0, saved screen
recordings/compact results and cleanup PASS with confirmed Shutdown. Corrected two-check
runtime including build/cleanup: 212.7 s. Signed ordinary Core AI Release preparation:
30.00 s including cleanup, build-only. Actual compiler flag, absence of diagnostic/FireRed
flags, linked converter, all 16 dictionaries/notices and strict main/runner signatures
were checked. Existing pins, signing, models/caches, voices and personal data are unchanged.

The initial refreshed phone handoff timed out and remains recorded. The user subsequently
provided a fresh exclusive idle/unlocked/cool handoff. A newly verified matching idle PID
was stopped, and the exact ordinary signed artifact was installed in place. The existing
runner's model-free `breeze-finish` passed 1 test / 0 failures / 0 skips in 98.54 s through
cleanup PASS. Real native dictionary regression and final On-device / English / Simplified
Chinese readback passed. Main executable SHA-256:
`a0370d72cb0d6c4e15d8dbbbda495752f2dcd1fb4c7ed7f437053c784b2e9e1d`.
No ASR model, microphone or Mac speech playback was requested by this deployment check.
Actual warning continuation in this updated ordinary binary remains unverified acoustically;
prior diagnostic continuation and the user's earlier smoke feedback are separate evidence.
Private evidence: `.build/verification/breeze-memory-warning-nonblocking-20260930/`,
including `deploy-finish/`.

### Receipt diagnosis

The receipt fix is active: all three inspected Breeze runs logged `status=hit` and
`prewarm_skipped status=receipt`. Full asset verification took 1.019-1.074 s, while
receipt-backed loading/validation took 161.432-172.361 s; total ASR readiness was
163.128-174.067 s. The stable sandbox-relative receipt prevents false invalidation after
installation, but still invokes actual `loadModels()` and model/admission validation.
It is prior-success evidence, not ownership of Core ML caches or resident model objects.
The separate component analysis below establishes the load boundary responsible for this
delay, not its internal cache state. No receipt/validation/backend change was made to
disguise the delay.

## September 30 Breeze load profile: encoder bottleneck confirmed, cache cause unconfirmed

Existing production `SpeechPreparationStep` instrumentation already surrounds the actual
pinned dependency's `MLModel.load`. The new host report pairs same-PID load fences and
component IDs, preserves incomplete/failed profiles and rejects invalid durations. It
writes content-free `model-load-profile.json`; it does not change model loading.

| Retained native run | Mel | Decoder | Encoder | Total load/validation | Remainder |
| --- | ---: | ---: | ---: | ---: | ---: |
| resume-mandarin-acoustic | 0.064 s | 17.854 s | 149.998 s | 167.923 s | 0.0078 s |
| native-breeze-support | 0.064 s | 19.917 s | 141.447 s | 161.432 s | 0.0049 s |
| native-breeze-support-corrected | 0.066 s | 22.437 s | 149.850 s | 172.361 s | 0.0076 s |

All three logged receipt hits and skipped prewarm. The encoder accounts for about
87-89% of this boundary; remaining validation/orchestration is under 8 ms. Asset hashing
is a separate approximately one-second phase. These are historical native measurements,
not new successful profile runs or a matched before/after latency improvement.

The actual clean Argmax checkout is pinned at
`1e2a163736dfa5a198e637ae44c114e1c6d5cc2d`.
[Model loading](https://github.com/argmaxinc/argmax-oss-swift/blob/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d/Sources/WhisperKit/Core/Models.swift#L12-L29)
creates the configuration and awaits Core ML directly.
[WhisperKit](https://github.com/argmaxinc/argmax-oss-swift/blob/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d/Sources/WhisperKit/Core/WhisperKit.swift#L364-L450)
loads Mel, decoder and encoder sequentially. Breeze's encoder and decoder both remain
CPU/Neural Engine; the preserved Vietnamese Core AI compile flag does not select a GPU
Breeze encoder. Shape/admission checks remain mandatory.

Leading hypothesis: repeated installations relocate the data sandbox and thus the model's
absolute path. The inspected historical runs have distinct container paths even though
the sandbox-relative preparation receipt hits. Apple's
[WWDC23 Core ML performance guidance](https://developer.apple.com/videos/play/wwdc2023/10049/)
states that specialized assets are tied to model path/configuration (11:33-11:59). The
Core ML instrument distinguishes `prepare and cache` from `cached` loads (12:05-12:27).
A receipt does not own or prove that cache. **Recompilation is not established here.**

Separate preparation-only tooling uses Time Profiler plus the actual Core ML instrument,
normal Release launch, no probe flags, no microphone or Mac audio input. It requires a
matching cleaned-up model-free profiler check, exact active Instruments device, fresh
same-PID admission after native activation, complete component boundaries and a finalized
PID-scoped trace with the Core ML schema. Existing faults/budgets/locks are retained.

Qualification is BLOCKED. The first attach found the phone offline in Instruments while
app RPCs worked; no models started. Fresh USB readiness enabled capture. A new-stage
setup whitelist omission then caused a required skip, which was retained and fixed.
The corrected model-free check failed XCTest initialization with `Timed out while enabling
automation mode`, before its test body or Prepare. The phone was unlocked in both saved
preflight and subsequent status; locking is not established as the cause. The trace
attached/finalized and contains the Core ML schema but no model events. Original failures
and cleanup FAIL remain preserved; separate ownership-aware recovery and fresh empty
phone/host inventories confirmed no owned work remains. No expensive model replay occurred.
The corrected signed runner build took 21.40 s including cleanup; main executable bytes
remain the installed warning-fix artifact above. Host checks and whitespace validation pass.

Historical proposed next steps, now deferred by the user-confirmed warm-relaunch result below:
1. Resolve native initialization or use an explicitly coordinated paired normal Prepare/End
   capture. Confirm the encoder's actual `cached` versus `prepare and cache` label.
2. Measure a cold post-install load against a normal relaunch with the same installed build,
   model path, compute map and coverage, without another reinstall or cache deletion. If
   relocation explains the repeated cold cost, qualify reuse of the identical installed
   artifact in automation. Do not promise daily-use latency from installation-heavy runs.
3. If stable-path cached encoder loading is still slow, inspect its sampled stacks and
   propose a separately approved encoder-only CPU/GPU comparison using the same retained
   weights and decoder. No compute/provider/pin/VAD/limit change, model re-export,
   quantization, forced receipt hit or skipped validation is part of this checkpoint.

Private evidence: `.build/verification/breeze-load-profile-20260930/`, including historical
profiles, Apple guidance, host checks, prepared identities, model-free failures and recovery.
Native accuracy/Help/listening/persistence gates retain their separate prior statuses.

## User-confirmed warm relaunch: startup investigation closed for the PoC

The user tested the existing installed Simplified Chinese build without another reinstall:
End the conversation, wait for completion, fully quit Mural, reopen, then Prepare & start.
They report the whole conversation becoming ready in approximately **five seconds** and
are satisfied with current normal-use behavior. This is human-reported approximate timing,
not a new instrumented run, matched benchmark or proof of the internal cache label.
A full process restart distinguishes this observation from same-process model reuse.

Together with the retained long post-install loads and Apple's path-sensitive cache
behavior, this strongly supports installation-related cold loading as the working
explanation. The user accepts that cost between reinstalling and first preparation.
Treat startup as resolved for this PoC; do not resume the blocked profiler workflow or
propose compute/quantization/cache changes merely because another reinstall loads slowly.
Record post-install/cold and unchanged-install/warm timings separately. Preserve model-ready
waits, actual loading/validation, receipt invalidation and all resource/thermal guards.
Reopen latency investigation only for slow unchanged-install relaunches, a relevant changed
model/runtime/compute contract, or an explicit request to optimize cold startup.

General positive smoke feedback does not retroactively pass the failed prerecorded-word
or native lookup/Help checks. Native raw/display persistence and explicit editing already
passed and need not be repeated on unchanged contracts. The remaining focused manual checks
are Simplified meaning/lookup/on-screen Help with English reply speech and no Chinese
Help playback, a short mixed Mandarin-English name/number turn, and observation that notification-only warnings
do not interrupt ordinary multi-turn use. A new Traditional acoustic check remains unverified;
run it only if closing that formal shared-model gate, not as a prerequisite for daily use.
No new phone access, installation, recording or model load was performed for this note.
Private user feedback: `.build/verification/breeze-load-profile-20260930/user-warm-relaunch.json`.

## MVP closeout: user-accepted Simplified workflow

The user completed manual smoke on the installed ordinary build and accepts the tested
Simplified Chinese workflow as working as expected. This closes the bounded MVP PoC,
not every recognizer benchmark, hardware condition or unexecuted automation branch.

| Contract | Closeout evidence |
| --- | --- |
| Live mixed Mandarin/English, names and numbers | User confirms the turn checked out; earlier live English feedback was also positive |
| Simplified display | User acceptance plus eight fresh Core tests / eleven real pinned OpenCC goldens |
| Meaning and word lookup | User confirms both show Simplified Chinese |
| On-screen Help and speech | User separately confirms Simplified Help, audible English replies and no Chinese Help audio |
| Ordinary multi-turn UX | User confirms several turns without unexpected Pause/Resume; real-observer model-free notification regressions already passed |
| Raw/display separation, reopen and explicit edit | Earlier exact-UUID native persistence/edit pass; five fresh persistence tests and 28 production boundary assertions |
| Warm startup | User reports approximately five seconds after End, full quit and unchanged-install relaunch; slow post-install preparation accepted |
| Signed build/resources | Reviewed current source/artifacts match the installed ordinary Core AI Release preparation; exact OpenCC pins, sixteen dictionaries and notices verified |

Fresh closeout checks passed with eight ChineseScriptPresentationTests and five
LocalSpeechPairPersistenceTests, real OpenCC (not a stub), 28 injected-map production
boundary assertions and host runner checks. Earlier simulator screenshots/recordings,
focused UI assertions, cleanup PASS/Shutdown and native scoped persistence evidence remain
applicable to unchanged production contracts. No new phone access, installation, audio
capture, model load or cache mutation was required to record acceptance and commit source.

Source review found the optional Breeze profiler's early-exit check nested inside the
resource/provisioning branch, so it could not run for Breeze. The shared exit check now
covers both profiler stages while leaving an already-requested native abort/drain intact.
Host checks reject premature successful/failed exits and retain final trace/cleanup gates.
This tooling-only correction does not qualify the blocked profiler or require replaying it.

Explicit remaining limits:
- A fresh Traditional spoken session on this build was not checked. Source, converter and
  model-free diagnostics verify shared Breeze identity and disabled Traditional projection;
  do not claim a new native Traditional acoustic pass.
- Earlier prerecorded English/mixed-word and no-speech failures remain failed. Current
  live-user acceptance does not prove accent causality or broad word accuracy.
- Automated support and profiling stages retain their recorded failures/unqualified
  branches. User Help/lookup/listening acceptance is separate evidence, not an automated pass.
- No quantitative memory/thermal soak, lifetime safety proof or quantization benefit is
  claimed. Hard resource/thermal/model guards and disabled Chinese automatic learning credit
  remain unchanged; ordinary turns do not prove a fresh actual warning occurred.

Source delivery is an accepted Simplified MVP checkpoint on mvp, with unrelated simulator
limiter instruction edits excluded. Private acceptance and checks are under
`.build/verification/breeze-simplified-closeout-20260930/`. Reopen the closed startup
investigation only under the warm-relaunch conditions above, not merely after another install.

## Rollback

After native owners drain, revert only these reviewed source commits/hunks and build the preserved prior artifact/configuration. Do not erase models, active pointers, preferences or history. Never automatically prepare old FireRed after reverting CN mapping. Older app code can read canonical/raw fields but may discard unknown display metadata on later saves; preserve required test evidence before a binary downgrade. Schema stays 2; canonical and raw data are not migrated or rewritten.
