# Silence prevention: inspected source and qualification candidate

## Status

Prepared against `mvp` at `8c09e10a26cadae527d4ac73d860029207974e6d`.
The committed final FP8/PAL8 engineering review and final iPhone validation were
read first. The latter explicitly records safety, content and human UX PASS and
closes the bounded optimization exercise. That is prerequisite evidence, not
silence/VAD qualification evidence.

**This candidate is not an accepted silence fix.** Default VAD mode is `off`.
`observe` measures without rejecting; `gate` is an explicit experimental arm.
Do not promote the default until the accompanying iPhone qualification passes.
The preparation host was Linux. GitHub reads were connected, but no commit,
file-write, tree-write or ref-write action was exposed. Plugin discovery did not
supply a writer; CLI GitHub access failed DNS resolution. No remote write or
commit was made by this preparation session. The delivered application edits
are guarded source replacements, not a claim of an applied repository checkout.

No ASR precision, model pin, decoder heuristic, package version, prewarm policy,
converter, microphone tap, capture queue or ASR fallback policy is changed.

## Root cause and insertion point

The microphone tap yields owned float PCM packets into the existing bounded
32-packet stream. The single `LocalConversationEngine.transcribe` task copies
these packets into the existing AVAudioConverter and produces 16 kHz mono PCM.
For PhoWhisper, converted samples accumulate until Send; the converter's trailing
frames are appended before transcription. PhoWhisper then runs its staged
encoder, decoder and transcript assembly. Nonempty final text is appended and
saved by `ConversationCoordinator.recordLocal`, then passed to the tutor and TTS.

PhoWhisper currently disables compression-ratio, log-probability,
first-token-log-probability and no-speech thresholds. The source explicitly
acknowledged the deferred silence hallucination. Without an earlier speech test,
nonempty fabricated ASR text is indistinguishable from a legitimate user turn to
the coordinator. No word blacklist or quantization change addresses that cause.

The existing empty transcript path already supplies “No speech recognized. Try
another recording.”, returns the audio engine and coordinator to Ready, and skips
user-fragment append/save and conversation reply. `TalkView` renders the notice.
There is a secondary hole: `recordLocal`'s defer and `TalkView`'s busy-to-idle
callback can schedule automatic meaning generation for the previous assistant
passage. The candidate marks a completed empty recording on the audio owner and
guards **both** automatic paths. Explicit Help, typed replies and meaning actions
remain available; this is not a global tutor-disable latch. Prepare and each new
recording reset the marker. Empty results also clear stale submission timing.

The VAD hook is after the converter tail is appended and before
`WhisperRecognizer.transcribe`. The existing speculative greeting-decoder prewarm
is still awaited even when VAD rejects. This preserves its native-drain boundary.
A rejected turn returns the existing empty result rather than introducing another
conversation state or error type.

## Exact dependency and model

The committed Xcode `Package.resolved` pins FluidAudio **0.15.7** to
`41540ea237350afe5117a082b5c28eda642d0612`; the public `v0.15.7` tag resolves to the
same commit. The Xcode dependency is exact. This is not an implementation copied
from the current default branch.

Inspected at that revision:

| Source | Relevant contract |
|---|---|
| `Sources/FluidAudio/VAD/VadManager.swift` | Public actor; async configuration/model-loading initializer; raw-sample whole-buffer API; internal chunk prediction; synchronous Core ML prediction and pooled input buffers. |
| `Sources/FluidAudio/VAD/VadManager+Streaming.swift` | Public `processStreamingChunk(_:state:config:returnSeconds:timeResolution:)`; external per-stream recurrent state; hysteresis events. |
| `Sources/FluidAudio/VAD/VadTypes.swift` | `VadConfig`, `VadStreamState.initial()`, `VadStreamResult`, segmentation defaults and error types. |
| `Sources/FluidAudio/ModelNames.swift` | `.vad` repository and required compiled model name. |
| `Sources/FluidAudio/Shared/Download/ModelHub.swift` | Cache layout, missing-asset download, loading and recovery behavior. |

The required artifact is:

```text
Repository: FluidInference/silero-vad-coreml
File: silero-vad-unified-256ms-v6.2.1.mlmodelc
```

The model filename comes from the pinned registry, not the model card's older
v6.0.0 comparison. The SDK revision does not independently attest installed model
bytes. Record the compiled bundle inventory/fingerprint on the Mac and phone
before accepting results. No installed VAD model or fingerprint was available to
the Linux preparation host.

### API and behavior

Initialization uses `try await VadManager(config: VadConfig(...))` only during
Prepare. There is also a public initializer accepting an already loaded `MLModel`,
and a directory initializer; neither is needed for this candidate.

The candidate uses `processStreamingChunk` on the existing Float32, 16 kHz, mono
samples, with a fresh `VadStreamState.initial()` for every recording. Its returned
state is fed into the next window of that recording only. It does not use the
URL or AVAudioPCMBuffer APIs, so it does not invoke another resampler.

Each native prediction accepts 4,096 new samples (256 ms), 64 context samples,
and 128-element hidden and cell state arrays. The raw input tensor has 4,160
samples. A short final window is repeat-last padded by this version of the SDK;
the caller supplies its actual length and does not count padding as captured
speech. No normalization is applied by the inspected chunk implementation.

The SDK's default probability threshold is **0.85**. Segmentation defaults include
150 ms minimum speech, 750 ms minimum silence, 100 ms padding, and a 0.15 negative
threshold offset. The streaming state machine does not enforce the whole-buffer
minimum-speech-duration setting. This candidate consumes raw probabilities, not
segmentation events; those defaults do not create another rejection gate.

The whole-buffer `[Float]` API is available and creates fresh state, but it eagerly
builds a full array of copied chunks and does not check task cancellation between
predictions. The candidate instead copies one bounded chunk at a time and checks
cancellation before and after every awaited prediction. It cannot interrupt an
in-flight synchronous Core ML call; it awaits that call and then stops. There is
no detached VAD task, additional microphone owner, or cross-turn state cache.

Compute units are explicitly `.cpuAndNeuralEngine`, matching the SDK default.
This permits CPU and ANE and excludes GPU for this model; it is **not proof of
actual operator placement or ANE execution**. Real device runtime and footprint
remain unmeasured. The input tensor dimensions bound scratch data, not total
process memory, resident model memory, or accelerator allocation.

### Download, cache and offline behavior

The compiled model is separately downloaded, not embedded in the Swift package.
The default loader uses Application Support / `FluidAudio/Models`, the pinned
`Repo.vad.folderName`, and `ModelNames.VAD.sileroVadFile`. A complete valid cache
loads locally. Missing assets can download during Prepare. The pinned recovery
loader may purge/redownload this VAD repository on non-cancellation/non-transient
load errors unless its global offline mode is set; this patch does not modify
that global setting or other model caches.

After a successful Prepare, Send uses only the retained manager: no download or
model-loading API is called on the turn path. Offline cached relaunch/Prepare and
recording must still be proved on iPhone. Missing/corrupt VAD preparation or VAD
prediction errors are logged without exception content and **allow the same
retained ASR to run**. They are not converted into “No speech recognized” and do
not switch ASR models. Consequently, a VAD failure can leave the original silence
hallucination possible. It is a failed qualification row, never a successful
silence rejection. Initial offline preparation with missing VAD assets may incur
network failure/retry delay; measure it separately, not as warm offline behavior.

## Candidate policy and instrumentation

`SpeechPresencePolicy` contains one proposed threshold: **0.30**. Any window at or
above it preserves the entire original recording for unchanged ASR. There is no
minimum audio amplitude, no minimum run of active windows, no minimum word
duration, and no removal of initial/final silence. A low-probability window alone
cannot discard a turn that has another active window.

This threshold is a deliberately permissive hypothesis below the SDK's 0.85
classification default, **not a measured optimum or a quiet-speech guarantee**.
Rejection requires valid probabilities for the complete bounded recording and
zero active windows. Missing windows, invalid probabilities, empty/invalid
evidence and VAD errors fail open. Decoder thresholds remain unchanged; Whisper
noSpeechProb has not been measured as secondary evidence in this session.

| Argument | Behavior |
|---|---|
| Absent or `--asr-vad=off` | ASR control; no VAD preparation/inference. |
| `--asr-vad=observe` | Measure proposed decisions, but always continue to ASR. |
| `--asr-vad=gate` | Experimental Silero-only rejection; enable for qualification only after observation review. |

Duplicate or invalid VAD arguments fail configuration instead of choosing an
ambiguous arm. VAD is limited to PhoWhisper; unrelated experimental recognizers
are unchanged.

Opt-in metadata logs contain the existing capture UUID, sample count/duration,
per-window probability, maximum/mean probability, active-window count/coverage,
first/last active-window sample boundaries, evidence completeness, proposed and
actual rejection, and analysis runtime. Existing capture/send/final/tutor-audio
UUID events supply conversation timings. Existing process-memory logging is
sampled around successful analysis. `analysis_seconds` includes the sample loop,
window logging and boundary memory samples; full Send-to-final remains the
normal UX interval. Preparation loading and failed/cancelled scopes are distinct.

Active-window duration and boundaries are **coarse 256 ms coverage proxies**, not
word-level speech duration, onset/offset truth, or independent acoustic labels.
No new code persists PCM, records private transcripts, or logs their contents.
Exact displayed transcripts belong in the local controlled-test ledger.

## Host verification and remaining gates

On Linux / Swift 6.2.1:

- 12 XCTest policy tests passed, zero failures, in an isolated package containing
  the actual new Core policy and test file. This is not the full existing suite.
- 14 integration checks compiled the actual added VAD methods and changed
  finalization/coordinator excerpts with API-shaped VAD/audio/logger fixtures.
  They passed control/observe/gate routing, unchanged PCM/tail delivery, fresh
  per-turn state, unavailable/error/invalid-probability fail-open behavior,
  pre-cancellation and native-like draining cancellation, prewarm draining,
  empty-result UX/no save/no reply/no automatic meaning, accepted replies and
  stale-result cancellation after End.
- 8 guarded-application tests passed on synthetic source fixtures, including wrong branch, moved local/remote head, dirty source, changed dependency, duplicate anchor and file-collision refusal. They did not contact or write a real remote.
- These fixtures are **not real Silero, Core ML, FP8/PAL8 inference, UIKit,
  AVFoundation, on-device TTS, offline network tests or physical memory tests**.
- The final fixture compile produced no warnings. Apple build warnings and
  physical-device crashes/memory warnings were not evaluated.

No acoustic silence/noise samples, real quiet Yes/No, bilingual recordings,
performance savings or real-speech overhead were measured here. No acceptance
criterion requiring iPhone evidence is marked passed. Run
`vad-qualification-handoff.md` before any default promotion.
