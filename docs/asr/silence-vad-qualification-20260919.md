# Silence VAD qualification — 2026-09-19

## Disposition

**IMPLEMENTED FOR OPT-IN QUALIFICATION; NOT IPHONE-QUALIFIED; DEFAULT OFF.**

Starting `mvp`: `8c09e10a26cadae527d4ac73d860029207974e6d`.
The existing `fp8-pal8-final-validation-result-20260919.md` records engineering,
content and human UX passes, closing the prerequisite optimization work. This
change does not reopen it. Retain packed-v3 FP8 Core AI encoder + PAL8 Core ML
decoder and `prewarm=always`. No package, model-precision, decoder-heuristic,
prewarm-policy, capture-owner or tutor-model change is included.

There is no new iPhone evidence in this report. Default promotion would be
premature: synthetic probability tests do not establish quiet Yes/No recall.
The normal launch therefore still has the known silence risk. Follow
`silence-vad-iphone-handoff.md` before enabling the candidate as a default.

## Root cause and insertion point

The PhoWhisper decode options deliberately leave `compressionRatioThreshold`,
`logProbThreshold`, `firstTokenLogProbThreshold` and `noSpeechThreshold` nil.
Nonempty captured audio previously reached ASR even without speech; any
fabricated nonempty decode then passed the coordinator's genuine-text check.
No text blacklist, amplitude cutoff, alternate ASR, or Whisper threshold was added.

Actual path:

```text
AVAudioEngine microphone tap (owned read-only packets; bounded queue)
  -> existing AVAudioConverter -> 16 kHz mono Float32 turnSamples
  -> Send: stop capture, drain accepted packets, flush converter tail
  -> await existing greeting decoder-warmup owner
  -> WhisperRecognizer.transcribe: optional Silero qualification/gate
       reject -> empty string
       otherwise -> existing FP8 staged encoder -> PAL8 decoder -> text
  -> recordConversationTurn (trim, notice, ASR Ready)
  -> ConversationCoordinator.recordLocal
       empty -> notice + Ready, before appendLocal/replyLocal
       nonempty -> save user fragment -> tutor reply -> TTS
```

The empty path was already intact and was not rewritten. It creates no new
user fragment and calls neither `replyLocal` nor `speakLocal`. Existing optional
meaning support for the *previous assistant passage* is unchanged; keep it
fixed between performance conditions rather than attributing unrelated support
work to this turn. An assistant greeting alone does not create a saved session.

The VAD manager is owned by the existing nested WhisperRecognizer actor; no
second microphone owner, converter, stream, detached worker or new App file is
needed. The capture UUID is passed through solely to correlate sanitized VAD
metrics with the existing Send/final/audio events. The existing `asrTask`
retains the recognizer while canceled/native work drains. End/background and the
memory-warning latch are unchanged. No alternate ASR fallback is introduced.

## Pinned API audit

Source is **FluidAudio 0.15.7**, resolved revision
`41540ea237350afe5117a082b5c28eda642d0612`, not current upstream examples.
The Xcode exact dependency and Package.resolved are unchanged.

| Concern | Verified pinned behavior / use here |
|---|---|
| Model | `ModelNames.VAD.sileroVadFile` = `silero-vad-unified-256ms-v6.2.1.mlmodelc`, repository `FluidInference/silero-vad-coreml`. |
| Initialization used | `try await VadManager(config: VadConfig(defaultThreshold: 0.30, computeUnits: .cpuAndNeuralEngine))`, only during Prepare in observe/gate mode. |
| Other initialization APIs | Public async `modelDirectory:` initializer and synchronous `VadManager(config:vadModel:)` for a preloaded MLModel are also present. |
| Samples | 16,000 Hz mono Float32, original amplitude; no normalization or resampling in our VAD call. |
| Window | 4,096 new samples / 256 ms plus 64 context samples; input shape `[1,4160]`. |
| Recurrent state | Hidden 128 Float32, cell 128 Float32, context 64 Float32. `VadStreamState.initial()` is created inside each turn. Only model weights/buffers are reused. |
| API used per window | Public `processStreamingChunk(_:state:config:returnSeconds:timeResolution:)`, using default segmentation arguments; read raw `.probability` and carry `.state`. |
| Access restriction | `processChunk(_:inputState:)` is **internal**, so is not used by Mural. |
| Whole-buffer API | Public `process(_ samples: [Float])` exists and resets model state, but first copies all chunks and does not check cancellation between them. Our bounded loop avoids that extra turn copy and supplies cancellation checks. |
| Padding | Library repeats the last sample to complete the final 4,096-sample window. It prepends prior context itself. No extra zero padding is added by Mural. Duration metrics clip to real samples, not padded length. |
| Library thresholds | VadConfig default is 0.85. Segmentation defaults: min speech 0.15 s, min silence 0.75 s, max speech 14 s, padding 0.1 s, negative offset 0.15. These segment-duration/event rules are NOT our turn acceptance rule. |
| Compute | `.cpuAndNeuralEngine` permits CPU/ANE, not GPU; it is not proof that every operation actually ran on ANE. Core ML's synchronous `prediction(from:)` runs inside the VAD actor's autoreleasepool using pooled arrays. |
| Cancellation | Pinned prediction is not forcibly preemptible. Mural checks cancellation before/after each awaited window and propagates it, rather than returning a late empty/transcript. No unload occurs under an active native call. |
| Memory | One 4,096-sample temporary chunk and at most 118 probabilities for a 30 s turn, plus the existing recording. Explicit recurrent arrays contain 1,280 bytes of floats; this is NOT total model RAM. Actual model/process overhead needs device measurement. |
| Cache | Separate asset, not shipped by SwiftPM. Default location: `Application Support/FluidAudio/Models/silero-vad/<model name>`. |
| Loading/download | VadManager calls ModelHub.loadModels. A complete cache loads without a download. Missing assets may download during Prepare; the library can purge/re-fetch this VAD cache after a non-cancellation/non-transient load failure. No model I/O is initiated by Mural on Send. |
| Asset revision | The library tree listing uses Hugging Face `main`, not an immutable weight revision. Package pinning alone is NOT a model-byte pin. Record the actual cached file inventory/digest before qualification and verify the same inventory on the phone. Weight hashes have NOT been measured remotely. |
| Offline | After successful Prepare, inference uses the retained model. Relaunch + Prepare with both radios off must also be tested against the complete cache. Missing/failing VAD fails open to the SAME retained ASR and is a qualification failure, not a passed silence test. Global ModelHub.offlineMode is not changed for other audio code. |

Audited source paths under the resolved revision:
`Sources/FluidAudio/VAD/{VadManager.swift,VadManager+Streaming.swift,VadTypes.swift}`,
`Sources/FluidAudio/ModelNames.swift`, and
`Sources/FluidAudio/Shared/Download/{ModelHub.swift,HFTreeLister.swift}`.
Relevant Git blobs: manager `e347a53491a25a5213d4b78f9ca428543c7b015b`,
streaming `90f6b9b0f88a6c292ccbd04927f501fbf0b119f7`,
types `7249b0a49f7dc0e195ce39f45abd0f319ecae0b5`,
names `a5ffc4c4347aacb2d0dec4b16c409ea0a6963f39`.

## Candidate policy and experiment controls

- No argument, or `--speech-vad=off`: existing behavior, no VAD loading or inference.
- `--speech-vad=observe`: VAD metrics/proposed decision, but ALWAYS run unchanged ASR.
- `--speech-vad=gate`: explicitly opt into the unqualified candidate rejection policy.
- Duplicate, malformed and unknown VAD arguments are rejected during preparation.

Candidate positive threshold: **0.30**, exploratory rather than measurement-derived.
Accept the whole recording when **any** window meets it. Do not require multiple
consecutive windows, minimum utterance duration, a speech fraction, or an RMS
floor. Do not trim leading/trailing audio or ignore a short final burst.
A nonempty recording shorter than one window with no positive evidence is
**inconclusive**, not rejected. Invalid/incomplete probabilities, invalid samples,
model absence and inference errors never count as evidence of silence. Existing
ASR input validation still handles invalid PCM.

This simple maximum-probability rule favors recall over noise rejection and
needs no added hysteresis: once any window passes, later silence cannot revoke
it. It may admit breathing/noise; quiet words may still be missed by the model.
Only empirical results can resolve that tradeoff. Do not promote based on one
silent recording or synthetic unit tests. A missed quiet Yes/No fails qualification.

Experiment order: A off control; observation of Silero probabilities plus unchanged
ASR; B Silero-only gate after reviewing that observation. C Whisper-only and D
combined are **not run** here. The current Whisper no-speech filtering remains
nil, and no second gate/noSpeechProb rule is introduced without isolated evidence.

## Diagnostics and performance scope

Only explicit observe/gate mode emits `asr_vad_*` records. Window probabilities,
real sample counts, coarse speech-active boundaries, active-window/sample duration,
proposed/actual rejection, model name, runtime and phase footprint are correlated
by the existing capture UUID. Boundaries are window estimates, not word timing;
`first_seconds`/`last_seconds = -1` means no active boundary. Footprint zero means
the existing sampler returned no measurement. Each prediction window is logged,
so threshold analysis need not infer probabilities from an already-gated transcript.

`vad_seconds` covers the window loop, probability logging and policy calculation;
it excludes Prepare/model load and before/after footprint sampling. Existing
`asr_trial_send`/`asr_trial_final` measure full Send-to-final including those costs.
The exact displayed transcript is collected by the local agent for the fixed test
phrases, **not automatically logged or persisted in repository diagnostics**.

Rejected turns return before staged mel/encoder loading, per-turn decoder
prewarm/load/prediction, and reply/TTS calls. **This is a source-path observation,
not measured savings.** The existing greeting-time speculative decoder prewarm
has already happened and is not a saving. Verify absence of per-turn stage events
and compare matched timings/footprint on iPhone. Never add overlapping component
timers or treat process-lifetime RSS peak as a per-VAD model peak.

## Executed host checks

Environment: Linux x86_64, Swift 6.2.1. An isolated SwiftPM harness containing
only the new Core policy and its test file ran **11 tests, 0 failures**. It covers
mode parsing, observe/off non-rejection, 1/3-second negative probability sequences,
single-window speech at every position, short negative recordings, threshold/window
boundaries, clipped tail durations, malformed/incomplete evidence, bounded input,
and independent policy evaluations. These are synthetic probabilities, NOT Silero
inference or quiet-speech recognition results.

`swiftc -frontend -parse App/LocalConversationEngine.swift`: PASS. This is syntax
parsing, NOT Apple SDK type checking/linking. Diff/source checks confirmed the
frozen encoder/precision section, decodingOptions, transcribeStaged, Stop,
Send/drain and converter processing scopes remain byte-identical, with VAD before
staged inference and fresh state inside each turn. The original full source was
verified against Git blob `70bff8805a99821479204387997d5900e6b194df` before editing.

The existing full Core suite, Xcode build, real FluidAudio/Core ML execution,
actual retained ASR fixtures and new iPhone matrix are **not run in this environment**.
No new device latency, savings, memory-warning, native-abort or offline PASS claim
is made. Previous FP8/PAL8 results are not substituted for VAD results.

## Remaining acceptance evidence

All new device fields remain NOT RUN: intentional silence/room/fan/breathing;
quiet Yes/No; low-volume English/Vietnamese; bilingual/siêu thị/numbers/negation;
Ready/no saved user/no tutor/TTS; genuine-speech overhead; rejected-turn savings;
End/background/cancellation/native drain; cold process with warm assets offline;
model-byte identity; memory warnings/crashes and perceived UX. Commit only a
sanitized result report after this evidence exists. Default promotion is a
separate narrow decision after every acceptance criterion passes.
