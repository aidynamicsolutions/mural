# Short-reply VAD investigation - 2026-09-20

> Historical initial investigation. Its no-policy-change disposition and unqualified converter status were superseded by the [subsequent user-approved fix and phone verification](short-reply-vad-fix-20260920.md). Earlier microphone recordings were not retained; eight new final recordings were later saved with explicit consent. The identities and limitations below describe the initial handoff, not the final merged state. Private verification evidence was later moved, with hashes verified, into the main `mural` checkout under the same `.build/verification/` relative paths before the temporary worktree was removed.

## Disposition

**False rejection reproduced without loading ASR. No production policy change justified.** In a paired, human-labeled Silero-only phone check, the current gate rejected 2/12 spoken replies and accepted 0/5 nonspeech recordings. These are counts for this small convenience set, not a population accuracy estimate. The two failures were normal brief Yes/No, with complete evidence and exactly accounted source/converter/VAD sample counts.

The failed Yes's top-three score was **0.797526**, below the retained real breathing/movement example's **0.802897**. Lowering only the cutoff enough to accept that Yes necessarily accepts that known noise example. Restoring the older any-window policy also reopens known fan noise. The current `0.85` score threshold, default gate, model, and trimming constants remain unchanged.

A **separate converter packet-loss defect** was found with native AVAudioConverter and synthetic PCM. Its shared-root correction and failing-before/passing-after regression are included in the isolated worktree. It does **not** explain these logged rejections: their sample counts are intact. The converter correction passed host tests and Release builds but was made after the paired check and has **not been installed or phone-qualified**.

FireRed remains stopped for the separate unresolved memory investigation. No FireRed, Breeze, PhoWhisper, tutor or TTS inference was run for this investigation. The ordinary pre-converter-fix app was restored, the owned log capture was stopped, and the phone was released. Nothing was committed or pushed.

## Scope and source identity

- Base: current local `mvp`, `185696849b35fd6b70474f8929232b3a88cb2ec1`.
- Isolated branch/worktree: `short-reply-vad-investigation` / `mural-short-vad`.
- At inspection, local `origin/mvp` equaled this base, rather than being five commits behind as stated in the handoff. No fetch, reset, synchronization or changes to the original worktree were performed. Its three untracked local-agent handoffs were preserved.
- The memory agent declared docs-only ownership before diagnostic edits. Shared runtime/model artifacts were read-only. Exclusive phone use was reserved for the paired VAD-only check and subsequently released.
- `Core/SpeechPresencePolicy.swift`, FireRed/Breeze actors, package pins, assets, signing, stored data, memory-warning latch and ASR defaults are unchanged.

Reviewed context: [FireRed qualification](chinese/firered-aed-qualification.md), [Breeze native result](chinese/breeze-native-result-20260920.md), [VAD qualification and later aggregate/default follow-ups](vad-qualification-result-20260919.md), [trimming](vad-trimming-qualification-20260919.md), [historical source review](vad-source-review-20260919.md), [ASR overview](README.md), and the memory-agent handoff. The earlier off-default, single-window candidate is historical, not the policy tested here.

## 1. What the original FireRed evidence establishes

Private evidence was available under the original worktree's `.build/verification/firered-device-20260920/`, including `live-batch1.log`, `live-batch1-metrics.log`, `live-sanitized-metrics.json`, `live-source.sha256`, and `live-batch1-screen.png`. Full logs, screenshot and human text remain private.

| Submission order | Captured seconds | Gate | Result category | Send-to-final seconds |
|---|---:|---|---|---:|
| 1 | 4.4 | Accept | English phrase | 1.146 |
| 2 | 2.3 | Reject | Empty | 0.032 |
| 3 | 2.3 | Accept | Brief affirmative | 0.519 |
| 4 | 5.9 | Accept | English phrase | 1.493 |
| 5 | 2.8 | Reject | Empty | 0.030 |
| 6 | 3.4 | Reject | Empty | 0.035 |
| 7 | 7.7 | Accept | Mandarin control | 2.056 |

Every rejected turn logged `firered_vad mode=gate complete=true rejected=true`, with **no native FireRed decode call**. This is rejection before AED recognition, not an AED transcription error. FireRed does not apply PhoWhisper trimming, so neither pre-roll nor hangover caused this gate decision.

The user reported two rejected Yes attempts out of three, and a silence check was requested in the same batch. The user did not map each empty result to a timestamp. Submissions 5 and 6 must not be assigned spoken/silent labels retrospectively. No numeric acoustic accuracy estimate is derived from these missing recordings.

All seven logged 48 kHz source counts and converted 16 kHz counts matched. The three rejected converted counts were 36,800, 44,800 and 54,400. The accepted and rejected 2.3-second turns both had 36,800 samples: identical capture/window/tail lengths do not imply identical speech or probabilities.

**Evidence limit:** microphone WAVs, per-window probabilities and aggregate scores were not retained. These original recordings cannot be replayed. Capture duration includes surrounding quiet and is not spoken-word duration. Later Breeze successes were different recordings, not matched controls.

## 2. Actual capture-to-decision path

Reviewed `App/LocalConversationEngine.swift`, `Core/SpeechPresencePolicy.swift`, `App/FireRedEnglishRecognizer.swift`, `App/BreezeEnglishRecognizer.swift`, `App/VietnameseEnglishRecognizer.swift`, and pinned FluidAudio sources.

1. The microphone owner streams read-only PCM packets. The consumer checks cancellation, format consistency and the turn sample limit. An overloaded stream fails explicitly rather than silently accepting a dropped-packet turn. Send finishes capture and drains accepted queued packets; Stop cancels instead.
2. Each packet is copied into Float32 PCM and fed to the recording's AVAudioConverter. Target format is 16 kHz mono. After stream completion, the converter receives end-of-stream and its tail is added before analysis or final recognition. Source frames, converted body, converter tail and final VAD samples are separately accounted in the diagnostic build.
3. FireRed and Breeze accumulate full converted PCM, then perform their gate before the native decode. PhoWhisper invokes the nested `WhisperRecognizer.analyzeSpeech`, then conservatively trims accepted audio. No change to those caller boundaries was made.
4. Each analysis starts a fresh `VadStreamState.initial()`. The result state feeds the next 4,096-sample/256 ms window. The pinned SDK maintains 64 context samples and recurrent state; no state is intentionally carried between recordings.
5. FluidAudio pads a final partial window to 4,096 by repeating its last sample. Evidence records only the actual unpadded input count. A partial final window gets one probability just like other windows; this can affect short-turn scores without implying extra recorded speech. No state-reset or padding implementation defect was identified in the reviewed paths.
6. `threshold = 0.30` defines active-window evidence/trimming. Acceptance instead requires complete valid evidence and the mean of the three highest probabilities to be at least `0.85`. Fewer than three windows scores zero. Off bypasses VAD; observe measures without rejection or trimming. Neither was substituted for gate in the phone check.
7. Missing, invalid, incomplete or errored VAD evidence fails open in production. Cancellation is separate: callers check after native prediction, throw cancellation, and drain owned work rather than treating it as permission to recognize or publish.

The VAD-only entry reuses **the normal capture/converter and existing nested analyzer**, not FireRed's native recognizer. Its window/state/core-policy implementation was cross-checked against both FireRed and Breeze. The analyzer may also compute PhoWhisper trim regions, but the diagnostic reports the whole-turn gate and never decodes any audio. FireRed/Breeze still pass full accepted PCM; PhoWhisper retains 512 ms pre-roll, 1,024 ms hangover and 2,048 ms minimum removed gap.

### Deterministic policy limits, not acoustic accuracy

Added checks to the existing `Tests/SpeechPresencePolicyTests.swift`, preserving the earlier real noise/quiet-speech regressions and fail-open coverage:

- Complete recordings with 1 through 8,192 samples have fewer than three windows and reject even with synthetic probabilities of one.
- 8,193 samples, with a one-sample third window and synthetic `[1, 1, 1]`, can qualify. This is a 512.0625 ms **capture geometry** example, not proof of acoustic success or a strict 768 ms spoken-word minimum.
- Two saturated windows require a third probability of at least `0.55` to reach a mean of `0.85`. Three individually `0.85` windows are not required.
- Synthetic two-peak evidence surrounded by quiet rejects at the original failed capture lengths. Extra quiet does not dilute a top-three mean, but it does not manufacture a third strong window. These sequences are explicitly synthetic, not reconstructed FireRed traces.
- A retained September 19 observe speech-block sequence has score `0.832357` and would reject under today's policy. Its words were not independently checked here, so it is excluded from labeled accuracy counts.

## 3. Paired phone check and privacy

The user authorized bounded, exclusive VAD-only phone use and explicitly declined new audio retention. No new PCM/WAV was saved. Device Hub was fully closed during recording. The compile-scoped `MURAL_VAD_PROBE` entry, launched with `--asr-vad-only` and unchanged gate mode, loads only the already-cached Silero model directly. It does not use SDK cache recovery, delete or download models, open the learning store, create normal Talk, or invoke ASR/tutor/TTS. Failed-open evidence produces a diagnostic error, not a misleading gate pass.

Existing per-window probabilities, aggregate result, turn IDs, runtime and memory events were reused. Added sample-count logging is compile-scoped. The UI reports **“Gate would accept/reject. No ASR ran.”** An empty transcript is expected in both cases and is not the result to classify.

At the user's request, the paired interaction used **one recording per interview card**, with:

1. one requested utterance or nonspeech action;
2. Record/Send instructions and what notice to inspect;
3. choices combining what was actually spoken/done with the displayed accept/reject result;
4. a skipped/deviation/uncertain option, instead of inferring truth from the script.

No slower speech, repeated words or added silence was required as an acceptance workaround. The user confirmed actual actions individually. Two initial, unlabeled completed turns remain excluded rather than guessed. No new screenshot was obtained: `idevicescreenshot` was blocked by the unavailable screenshot service. UI outcomes below are the user's per-card reports corroborated by content-free logs, not independent screenshot inspection. The generic probe's transcript wording remains a minor diagnostic UI limitation, not a VAD result.

### New labeled results

All 19 completed turns had complete VAD evidence and exact 48 kHz source -> 16 kHz converted -> VAD count agreement. Seventeen were human-labeled. The table records **capture** length, not voiced duration. Scores are logged to six decimals. `A-E` were the initial diagnostic set; the comparison definitions were frozen before follow-up `F-M`, `N-P` and `R`. This is a tiny same-speaker/device convenience holdout, not a blinded or representative corpus.

| Card / human-checked class | Captured s | Actual samples | Top-three score | Gate |
|---|---:|---:|---:|---|
| A: room silence | 3.4 | 54,400 | 0.072266 | Reject |
| B: normal brief Yes | 1.9 | 30,400 | 0.797526 | **False reject** |
| C: normal brief No | 2.3 | 36,800 | 0.833659 | **False reject** |
| D: quiet Yes | 2.0 | 32,000 | 0.895833 | Accept |
| E: quiet No | 2.2 | 35,200 | 0.980794 | Accept |
| F: fan only | 5.1 | 81,600 | 0.065267 | Reject |
| G: breathing/movement, no words | 5.9 | 94,400 | 0.221354 | Reject |
| H: quiet background, no words | 4.3 | 68,800 | 0.049154 | Reject |
| I: short negation | 2.2 | 35,200 | 0.981445 | Accept |
| J: short number | 2.1 | 33,600 | 1.000000 | Accept |
| K: Yes at Recording onset | 1.6 | 25,600 | 0.997233 | Accept |
| L: No, immediate Send after finishing | 1.7 | 27,200 | 0.997233 | Accept |
| M: normal longer reply | 9.5 | 152,000 | 1.000000 | Accept |
| N: fresh normal Yes | 2.5 | 40,000 | 0.934570 | Accept |
| O: fresh normal No | 2.1 | 33,600 | 0.999837 | Accept |
| P: fresh silence | 2.4 | 38,400 | 0.126790 | Reject |
| R: No after Stop/Prepare | 1.8 | 28,800 | 0.897949 | Accept |

- **Labeled speech: 2 false rejections / 12. Labeled nonspeech: 0 false acceptances / 5.** Do not generalize these denominators to other speakers, routes or models.
- Q was a separate Stop-during-capture check. No VAD or final event followed, and the user reported no late result. R then succeeded without an extra stale result. Q is excluded from acoustic counts.
- All labeled turns ended in partial VAD windows. The nonspeech G tail was only 192 actual samples; the longer-reply M tail was 448. This checks actual partial-window execution, not all possible padding acoustics.
- Later fresh Yes/No successes do not erase the earlier failures or become matched recordings.
- No transcript comparison is available: recognition deliberately did not run, and audio was not retained.

### The two failed speech traces

These are **real logged probabilities from the new VAD-only recordings**, not original FireRed traces or synthetic audio:

```text
B: [0.099609, 0.048828, 0.023926, 1, 1, 0.392578, 0.104492, 0.038574]
C: [0.085449, 0.039551, 0.032715, 0.051758, 1, 1, 0.500977, 0.145508, 0.143066]
```

B had eight windows, final window 1,728 actual samples, and 284 converted tail samples. C had nine windows, final window 4,032 samples, and 28 converted tail samples. Both had three `>= 0.30` active windows, but not enough top-three strength to pass. The failure is **not fewer than three captured windows**. The two saturated windows were internal full windows, not the padded tail.

The immediate mathematical cause is established: `(1 + 1 + 0.392578) / 3 < 0.85` and `(1 + 1 + 0.500977) / 3 < 0.85`. Why these utterances produced those acoustic probabilities is not established. Window phase, recurrent model response, speaker/route characteristics and speech onset timing remain hypotheses. Exact converter counts do not prove that speech before microphone readiness or after Send was captured. Passing boundary probes and quiet speech narrow the concern but do not exclude all onset/tail loss or prove amplitude is irrelevant.

## 4. Matched probability replay and the noise tradeoff

Compared current policy and four diagnostic alternatives on **the same logged probability sequences**. This is not same-byte PCM replay, a model rerun or matched transcript evaluation. Logged probabilities are rounded to six decimals; replayed current decisions matched. Candidate definitions were frozen in private `comparison-plan.json` before follow-up cards. No candidate was installed or made the default.

Each cell is false rejections / labeled speech; false acceptances / labeled nonspeech.

| Probability rule | Initial A-E | Later untuned set | Historical retained regressions |
|---|---|---|---|
| Current top-three mean >= 0.85 | 2/4; 0/1 | 0/8; 0/4 | 0/2; 0/3 |
| Top-three mean >= 0.83 | 1/4; 0/1 | 0/8; 0/4 | 0/2; 0/3 |
| Top-three mean >= 0.79 | 0/4; 0/1 | 0/8; 0/4 | 0/2; **1/3** |
| Top-two mean >= 0.85 | 0/4; 0/1 | 0/8; 0/4 | 0/2; **1/3** |
| Any-window maximum >= 0.85 | 0/4; 0/1 | 0/8; 0/4 | 0/2; **2/3** |

Historical labeled regressions comprise quiet Yes/No, fan, breathing/movement and room noise. Their labels and real probability sequences were retained from the earlier qualification, not newly relabeled audio. The additional unverified historical observe speech-block row is not in these denominators.

The historical breathing peaks are `[0.993164, 0.990723, 0.424805]`, mean `0.802897`. Therefore **no monotone top-three cutoff can accept B while rejecting this breathing example**. Top-two averaging also accepts it; maximum-only additionally accepts the fan example. These were the kinds of false acceptances that previously allowed ASR hallucinations downstream. There was no new ASR run here to measure that downstream outcome again.

`0.83` rescues C without breaking these few retained negatives, but still rejects B. That is a partial sensitivity/specificity alternative requiring more evidence and explicit acceptance, not a demonstrated short-reply fix. A special case fitted to exact saturated peaks would be overfitting, not a justified policy.

## 5. Separate concrete converter defect and correction

The pre-change `LocalConversationEngine.convert` called `AVAudioConverter.convert` once for each packet and returned immediately. Apple's [conversion contract](https://developer.apple.com/documentation/avfaudio/avaudioconverter/convert(to:error:withinputfrom:)) attempts to fill the output buffer, requesting input as needed. A full output buffer does not prove the new input packet was requested.

A native Mac regression using the actual extracted function, synthetic sine PCM and endpoint impulses reproduced:

```text
source: 48 kHz mono, 24,576 frames, packets of 4,800 then a 576-frame remainder
last packet: output=256, status=haveData, input callback never supplied that packet
expected 16 kHz output: 8,192 samples
actual pre-fix output: 8,000 samples
```

The 576-frame source remainder was lost, corresponding to 192 target samples / 12 ms. This is a real conversion defect, not a probability simulation. It is **not attributed to the reported FireRed or new B/C failures**, whose logged counts match exactly.

The small shared-root correction retains the pending input across successive conversion calls, appends each output, and continues on `.haveData` until `.inputRanDry` or `.endOfStream`. Error and zero-progress paths throw. It does not add artificial samples, alter gain, change resampling format, retune VAD, or trim audio.

Added a native `ConverterTests` regression in `Tools/CoreAI/test_asr_final_review.py`. It fails before the correction with 8,000 versus 8,192 samples and passes afterward. Thirty-two synthetic packetizations cover mono/stereo, 480/4,800-frame packets, short and longer inputs, complete and partial final packets. Counts match whole-buffer conversion, sample differences are below `1e-6`, and a further EOF drain returns empty. This is host conversion evidence, not iPhone capture or recognizer accuracy evidence.

**Cross-caller review:** the same helper has two call sites in the shared capture consumer: every packet and EOF. It feeds Nemotron's arbitrary-size streaming sample buffer; FireRed, Breeze and Parakeet's full accumulated PCM; and Whisper/PhoWhisper's accumulated PCM and subsequent analysis. The pinned Nemotron API buffers arbitrary sample-array sizes internally. No actor, inference, transcript or trimming code was changed. The final correction is not phone-qualified or a model-level regression pass; keep this deployment gap explicit before merging or shipping it.

## 6. Empty results, cancellation and resource safety

Reviewed `App/ConversationCoordinator.swift` and `App/RootView.swift` with source contracts:

- Empty local recognition returns before `appendLocal` or `replyLocal`, clears submission timing and restores ready state. It does not save an empty user fragment, start tutor/TTS, or schedule automatic meaning for a no-speech result.
- Both the ordinary automatic-meaning scheduling path and the resource-busy/on-change refresh path respect the no-speech guard.
- Recognition publication checks cancellation and the generation token after owned work drains. Stop invalidates the token and cancels, but does not release the task handle early. Native prediction cancellation is checked after its return, not converted into a fail-open ASR result.
- The memory-warning latch and teardown ownership were not altered. The diagnostic prepare checks generation/cancellation and cannot invoke its ASR method.

The new probe bypasses learning data and tutor/TTS entirely. The paired Q/R check verifies Stop during capture and absence of a late result in that flow. **Neither proves in-flight native VAD/ASR cancellation or fresh normal-Talk downstream behavior end to end.** Those paths have source/test support here and historical qualification evidence, not a new full-model phone pass. Full AED confirmation remains blocked by the FireRed memory STOP.

For the 17 labeled turns, logged VAD analysis time was 0.007634-0.034225 seconds. These measurements include instrumentation, are not Send-to-final or ASR timings, and have no p95 claim. Across the VAD-only capture, highest logged phase footprint was 38,471,520 bytes; lifetime footprint peak 48,547,752 bytes; lifetime RSS peak 93,241,344 bytes. Logged thermal state stayed nominal. No memory-warning event, ASR decode, tutor or TTS event was recorded in this bounded VAD batch. This does not clear FireRed's separate memory issue.

## 7. Exact tested identities

- Phone: iPhone 17 / `iPhone18,3`, iOS 27.2 (`24B5084k`). Captured format: 48 kHz mono. No cross-route qualification claimed.
- Toolchain: Xcode 27.0 (`27A5252f`), iOS SDK 27.0. Signed Release, existing app bundle installed in place. No uninstall or data reset.
- FluidAudio 0.15.7, revision `41540ea237350afe5117a082b5c28eda642d0612`.
- Actual cached model: `Library/Application Support/FluidAudio/Models/silero-vad/silero-vad-unified-256ms-v6.2.1.mlmodelc`.
- A read-only copy from that phone directory contained **five files / 1,063,425 bytes**. Sorted UTF-8 `relative-path<TAB>bytes<TAB>file-sha256<LF>` inventory SHA-256: `11924cda2c126851cff8f07353dfe39edc30cfd183965ce0bc2a3a2845647024`, matching September 19. This verifies the newly used cache bytes. Package revision alone is not a model pin, and no new contemporaneous inventory exists for the original FireRed batch.
- Original FireRed tested source: `737a29e7a3b3f9f2ff67033573c05d3afb1b832c`; actor SHA-256 `094200743c36c88f7c03f739f5397db5a2a8f12a4baf5c495836b640a75df438`.

### Executable SHA-256

| Build | SHA-256 | Status |
|---|---|---|
| Original FireRed live | `22d2ce6772afec3234cda635102f3b5896f15e6571cafc58673c28398a43d89c` | Historical only; not rerun |
| VAD-only paired check | `44f92a63e71a39f55258858b7d09e6b1f3e68938ecc303f0e1d137d14b249fd8` | Installed/tested before converter fix |
| Restored ordinary Release | `bab57afa139fc91e0294e6371b424e16b93fb0cdf11005d0da7712def2f33913` | Installed/launched without arguments; before converter fix |
| Final ordinary Release | `7e740554a3bb7de5bee378ed1882fabf7f45957e920f2f730810a55047b17188` | Built only; includes converter fix |
| Final VAD-only Release | `a7cb1ccc8a34a9c7990b365a6f807c16219e791309c58fe2d752cd922d01bd4b` | Built only; includes converter fix |
| Final FireRed opt-in Release | `7f18fdd5b9a0b06b700db9b385fe9db38a1c1b28aed31b3cd7681dac1067084b` | Built only; never run |

The restored ordinary launch emitted the normal FP8/PAL8 backend identity, not VAD-only or FireRed. No normal ASR preparation/recognition was requested as part of restoration.

### Source SHA-256

| File/state | SHA-256 |
|---|---|
| `App/LocalConversationEngine.swift`, phone-tested diagnostic | `1d47dc1548cc85fafb01d616c73a85fcaacd19e1ec7b35cc19e3682d4e1bd6df` |
| Same file, final converter correction | `64fdec3b5fcb8e7d48c5042a3e26b7610eaa1683fe6c5e9d3d92e942b8c4528c` |
| `App/RootView.swift` | `2c7fd758a86427eb2c96bfcc15dabcb2fc1fa3f1677c2344480facd811e89b6e` |
| `App/MuralApp.swift` | `36a345825922ec69bec0c1202acb55ce318618c8fbdc3817d0d071d6d07d0ecf` |
| `Core/SpeechPresencePolicy.swift`, unchanged | `752ed5c4c5d6f273960c7d3e9821a16956f2ea11013028888f381fab0c763970` |
| `App/BreezeEnglishRecognizer.swift`, unchanged | `99c9a9fafa92b010fc22c7f6cb33e476fe491e41cde13b44e4caaa9efea8baaf` |
| `Package.resolved`, unchanged | `877b60df2f911668513f461db577d3e5936a98414bc17be497694f94034823a7` |

## 8. Validation

| Check | Result | Private log |
|---|---|---|
| `swift test --filter SpeechPresencePolicyTests` | 24 passed | `policy-final.log` |
| `swift test` | 89 passed | `core-final.log` |
| `python3 Tools/CoreAI/test_asr_final_review.py` | 15 passed, including native converter and source contracts | `source-final.log` |
| `python3 -m unittest discover -s Tools/ChineseASR -p 'test_*.py'` | 47 passed | `chinese-final.log` |
| Ordinary Release | Build passed | `ordinary-final-build.log` |
| `MURAL_VAD_PROBE` Release | Build passed | `vad-final-build.log` |
| FireRed file-probe/embedded Release | Build passed; no execution | `firered-final-build.log` |

Final builds include the converter correction. Actual compiler commands confirmed the respective flags, rather than assuming a successful build identified its backend. FireRed configuration was generated with `scripts/generate_project.py --firered-file-probe` and ordinary configuration restored through the generator; no manual generated-project edit or generated diff remains. Existing interruption deprecation, async-alternative and AppIntents metadata warnings remain. No new warning was introduced. `git diff --check` passed.

Release build shape, from the isolated worktree, with inherited signing and existing bundle override:

```sh
xcodebuild -project Mural.xcodeproj -scheme Mural -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath .build/vad-derived \
  -clonedSourcePackagesDirPath .build/source-packages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  PRODUCT_BUNDLE_IDENTIFIER=com.kevintruong.mural.dev build
```

The diagnostic adds `OTHER_SWIFT_FLAGS='$(inherited) -D MURAL_VAD_PROBE'`. The FireRed generated configuration supplies its existing opt-in flags. No dependencies were upgraded. These are compilation checks, not new inference, persistence or native-cancellation passes.

## 9. Private fixture ledger

Evidence root in the isolated worktree: `.build/verification/short-reply-vad-20260920/`. All files remain private/uncommitted. A fixture hash identifies **count plus real logged probability windows**, not retained microphone PCM. Canonical bytes are sorted-key, compact JSON `{"count":N,"windows":[{"start":S,"count":C,"probability":P},...]}` followed by LF. The tables show 16-hex SHA-256 prefixes; complete hashes and windows are in the full-hash-identified private manifests below.

| Card | Turn UUID | Probability-fixture SHA-256 prefix |
|---|---|---|
| A | `E26D6954-5C88-4D1B-8448-17FEF38E8669` | `c57a202d0b1cee59` |
| B | `0B83DFCD-9CFA-4423-9DF8-9AF2485D6551` | `5c83a9ee8687d389` |
| C | `D354FEA0-FDE0-4FFD-9110-164B314BF6E1` | `028cac8cf7e19502` |
| D | `1EEF6A23-D554-4804-9581-228028D59C1F` | `58a39bed3ac4b796` |
| E | `BFCB705B-5646-41CA-95B2-3C04ABADA17A` | `d92096da99322018` |
| F | `47D5E391-C93C-4B8B-9332-ECCDF92D0CB5` | `580e88ce36377b42` |
| G | `6FB18CB7-5605-431A-86EA-190A14148BBA` | `242e4583033a4421` |
| H | `F7399025-6902-44BE-9AB3-97B700944DEE` | `22055d3bfdee3b1b` |
| I | `293EC7EE-187D-4555-91BD-B1E340BB8A41` | `9bf53303a76eec60` |
| J | `429AE513-C815-4A55-8F82-A728BC4D36EA` | `4f272276e5937815` |
| K | `7A3CB933-6BC8-403A-A9AC-D4EF90545244` | `4c2788680c5f227f` |
| L | `D979C133-9F22-4C6C-A859-9F1A7FF56CDF` | `bb31eccd364e2a90` |
| M | `C294D986-B8A7-4B90-BC62-F418D79642B4` | `5c1e03fbe7dc645f` |
| N | `47C93B31-525D-4388-B7C1-28B00B1F4E3A` | `6ac37e22f9c319e2` |
| O | `71C0FC9C-22DC-480E-B0B7-79BC7B745342` | `f6982c507f2db795` |
| P | `B172DDB3-D31D-4371-9848-441DC3CC7511` | `1f2811d1f7035b10` |
| R | `95CA65EF-7F81-44A1-9BEC-CC0C9D37FD48` | `b348f2738db22103` |

Excluded initial completed IDs: `6C80FC68-906A-4EF0-A50E-7394D8BF6DEC` and `494AA438-123F-4FCD-A123-22140FF0DBC5` (unlabeled). Q: `95B99F86-14E4-4D06-8946-4FFA1909F1F2` (cancelled before a VAD result, no probability fixture).

| Historical class | Turn UUID | Probability-fixture SHA-256 prefix |
|---|---|---|
| Fan | `C4FB4E4B-ED63-4D34-9C41-5EC54152B580` | `ab3adeab1e7b69cb` |
| Breathing/movement | `2684E228-FC3E-4191-B21B-9B1BCBC94446` | `d9211b1c1295ffc4` |
| Quiet Yes | `E1C78EB4-B87F-4B2F-B817-361C06615ADE` | `c0390fd2fb0530c4` |
| Quiet No | `1D6C76D2-82D2-4E51-AB47-F24D2C6876DE` | `47a0436a3b081d24` |
| Room noise | `890F1CA5-093F-439B-B8BE-2FAD8FEE0409` | `02924c3f61e88961` |
| Observe speech-block, excluded from labeled counts | `ECCF6D2B-34C6-4540-BF60-A2761D2370E5` | `597a02af18c91d63` |

| Private file | Full SHA-256 |
|---|---|
| `completed-vad-batch.log` | `77776eba07feae3e6eb011f59c3e37a8d40b6536363564b26e2704118086fc35` |
| `live-probabilities.json` | `ad4e096522d72c9ce90cc7b67247f59e82c6489b1af8bdf24746236d261b3118` |
| `historical-probabilities.json` | `755240634cc53106f773e7581c4df462175ddb3d99758b76d75df04789345c0f` |
| `comparison-plan.json` | `13f2840ee4b310a410553b30402716bf2a757d5fbd5171ab50de037076e764ca` |
| `policy-comparison.json` | `c8821ea0ddc4c9e0fa847e6b729375b6c573099e4bfc4e35eda09be9ef65ef82` |
| Original FireRed `live-batch1.log` | `fb821f543b2392804ca41cac11fa2a223cb923186608fc4031dc07d1ec4afaa2` |
| Original FireRed `live-batch1-metrics.log` | `ac74c191b9c6809e7e6bac7f1b87cd39b09251e9e6bb25711006d20b9f949b7a` |
| Original FireRed `live-sanitized-metrics.json` | `9a382aa648db11aefd980c197e83b963127b082d432e296ffd48d3ef1d159e0a` |
| Original FireRed `live-source.sha256` | `160a559982ec9bae7cca58864f058891c9ec301dd1c144c6c09fdd953cadae53` |
| Original FireRed `live-batch1-screen.png` | `d4ac2bc011f302e40ede8ea546c9d945630ab764910deaf4129058056f3f3f77` |

## 10. Recommendation and remaining gates

1. **Keep the current production gate for now.** The investigation establishes real short-reply false rejections, but no tested scalar cutoff fixes both new failures while retaining known noise rejection. Do not promote observe/off, blanket-accept short turns, force expected text, add a word blacklist or a second detector.
2. Review the small converter correction independently. It fixes measured sample loss for an edge packetization, not the reproduced sensitivity tradeoff. Before deployment, verify its final build on the phone through the same VAD-only path and then approved affected-recognizer regression paths. The prior paired results belong to the pre-fix executable.
3. A policy change needs explicit acceptance of a demonstrated speech/noise tradeoff. More probability-only, individually labeled cards are possible without retention. Any same-byte acoustic comparison first requires consent for a bounded private recording set/location; none was given here. Include more speakers/routes, phase/boundary variation and the difficult nonspeech cases, with definitions frozen before a held-out set. Do not hand-fit the two failures.
4. Matched FireRed transcript confirmation remains blocked until its memory gate is resolved or a separately approved controlled diagnostic permits it. No warning-latch bypass or normal-Talk ASR substitution is authorized by these results.
5. Uppercase English and Simplified/Traditional output differences remain separate deferred formatting/model-output issues. Breeze spacing/formatting and all raw transcript behavior are untouched. No hosted fallback, ASR-default promotion, model/cache/store deletion or memory-safety weakening was introduced.

Private evidence is retained. Owned capture is stopped. Ordinary app is restored in place, phone released, source changes left uncommitted in the isolated worktree for review.
