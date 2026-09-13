# Mural Local Conversation MVP — Implementation Plan

## 1. Goal

Add a new **fully on-device conversation mode** to `aidynamicsolutions/mural`.

The initial supported learning pair is:

```text
Target / learning language: English
Support / meaning language: Vietnamese
```

A Vietnamese native speaker should be able to:

* practise speaking English;
* answer in English;
* switch to Vietnamese when stuck;
* mix Vietnamese and English in the same utterance;
* ask for help in Vietnamese;
* receive a short natural English equivalent;
* repeat/practise the suggested English;
* retain Mural's existing vocabulary/learning-evidence system.

The free local mode must require **no OpenAI API key and no paid inference**.

The existing GPT-Live implementation remains available as the premium/realtime mode and should regress as little as possible.

---

# 2. Explicit MVP boundaries

### Build now

* iOS 27 minimum for this MVP branch.
* English target language.
* Vietnamese support/meaning language.
* FluidAudio local streaming ASR.
* English/Vietnamese code-switching.
* Apple `SystemLanguageModel` as the local conversational model.
* Short, turn-based local conversations.
* Local English TTS using Apple's system speech synthesizer.
* Mural transcripts.
* Mural learning assessments and vocabulary evidence.
* Existing Meaning, Help and typed-reply behavior in local form.
* Simple Settings choice between local and GPT-Live.
* Physical iPhone 17/17 Pro validation.
* Premium GPT-Live remains intact.

### Do **not** build yet

* Gemma 4.
* LFM2.5.
* MLX local-LLM model selection.
* Private Cloud Compute.
* Payments/subscriptions.
* Web search in local mode.
* Local current-events research.
* FluidAudio TTS/Supertonic/PocketTTS unless Apple's TTS proves unacceptable during the MVP.
* True full duplex.
* Back-channeling.
* Talking and listening simultaneously.
* Barge-in while Mural is speaking.
* Pronunciation scoring.
* Vietnamese as a target language.
* More support-language combinations.

This scope boundary matters. The goal is to determine whether **local turn-based conversation is good enough to be the free product tier**.

---

# 3. Preserve Mural's existing architecture

Do not rewrite Mural.

The current app already has the things we want to preserve:

```text
ConversationCoordinator
        │
        ├── SessionRecord
        ├── transcripts
        ├── meanings
        ├── LearningEngine
        ├── assessments
        ├── vocabulary evidence
        └── UI state
```

`ConversationCoordinator` already owns the conversation lifecycle and saves transcript fragments, assessments and learning state.

The current GPT-Live transport should remain basically untouched. It already handles WebRTC, microphone audio and OpenAI Live events.

Likewise, do not rewrite `LearningEngine`. Its validation of evidence is valuable, particularly because it already distinguishes assisted from independent production.

The new architecture should therefore look like:

```text
                    ConversationCoordinator
                             │
                    choose conversation mode
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
      LocalConversationEngine           LiveTransport
              │                          existing
              │                             │
      fully local pipeline              GPT-Live
              │                             │
              └──────────────┬──────────────┘
                             │
                        SessionRecord
                             │
                       LearningEngine
```

Do **not** introduce a large provider/plugin abstraction for this MVP.

A simple branch between local and live is sufficient.

---

# 4. Use MAIChat as reference, not as a dependency

Inspect:

`aidynamicsolutions/maichat`

particularly:

```text
fullmoon/Services/VoiceToTextService.swift
fullmoon/Models/LLMEvaluator.swift
fullmoon/Services/ModelCatalogService.swift
```

MAIChat already demonstrates useful patterns:

* microphone permission handling;
* local model preparation;
* ASR prewarming;
* readiness states;
* background model initialization;
* cancellation;
* memory-aware behavior;
* device-side model execution.

Its `VoiceToTextService` already uses FluidAudio and maintains a reusable ASR manager instead of creating it for each transcription.

However, **do not copy MAIChat's implementation verbatim**.

Its current voice flow is still dictation-oriented:

```text
record file
→ stop
→ transcribe
```

and its FluidAudio dependency starts at the old `0.8.1` API.

Its model catalogue is also intentionally out of scope. The existing list is based around older Llama/Qwen/DeepSeek models.

Do **not** bring `MLXLLM`, `MLXLMCommon`, its remote model catalogue, or its model download UI into Mural.

The Apple system model replaces that layer for this MVP.

---

# 5. Update FluidAudio first

Pin FluidAudio to the current stable release:

```text
v0.15.7
```

Do not use `from:` or `main` for the MVP. Use the exact tag so testing is reproducible.

`v0.15.7` was released September 10 and includes several Nemotron multilingual streaming fixes as well as streaming final-window fixes.

Add the FluidAudio product to the Mural app target.

Do not add MLX packages.

The Mural project currently contains only its local `MuralCore` package and WebRTC dependency, so this should be a contained package change.

For the MVP branch, raise:

```text
IPHONEOS_DEPLOYMENT_TARGET
26.1 → 27.0
```

Mural currently targets iOS 26.1.

Do not implement iOS 26 compatibility shims yet.

---

# 6. ASR choice: FluidAudio Nemotron 3.5 multilingual

Do **not** use MAIChat's existing Parakeet-v3 path for this conversation mode.

Use the current FluidAudio streaming Nemotron multilingual implementation.

The underlying model includes explicit prompts for:

```text
en-US → 0
vi-VN → 33
auto  → 101
```

and defaults to automatic language detection. ([Hugging Face][1])

That makes it much better suited to:

> “I went to… siêu thị… I don't know how to say that.”

than an English-only recognizer.

Use the **full multilingual vocabulary**, not FluidAudio's Latin-pruned English/Spanish/French variant. The current Core ML release exposes a multilingual vocabulary intended for languages beyond the optimized Latin set. ([Hugging Face][2])

### Important implementation rule

Reset the streaming ASR state at the end of **every conversational user turn**.

Do not maintain one endless ASR stream across the entire conversation.

Conceptually:

```text
listen to turn
   ↓
finalize transcript
   ↓
reset ASR state
   ↓
model responds
   ↓
start fresh ASR state
```

This gives the automatic language detector a fresh chance to identify Vietnamese vs. English on every new turn.

---

# 7. Create `LocalConversationEngine.swift`

Add:

```text
App/LocalConversationEngine.swift
```

This class owns only local audio interaction.

Responsibilities:

```text
AVAudioSession
AVAudioEngine microphone capture
16 kHz mono conversion
FluidAudio VAD
FluidAudio streaming Nemotron ASR
turn-end detection
local TTS playback
input audio level
state callbacks
```

It must **not** know about:

* SwiftData;
* SessionRecord;
* learner level;
* themes;
* assessments;
* vocabulary;
* GPT-Live;
* OpenAI.

Those stay in `ConversationCoordinator`.

Suggested interface:

```swift
@MainActor
final class LocalConversationEngine {
    enum Phase {
        case idle
        case preparing
        case listening
        case transcribing
        case speaking
        case stopped
    }

    var onFinalTranscript: ((String, TimeInterval, TimeInterval) -> Void)?
    var onInputLevel: ((Double) -> Void)?
    var onPhaseChanged: ((Phase) -> Void)?
    var onSpeechFinished: (() -> Void)?
    var onFailure: ((String) -> Void)?

    func prepare() async throws
    func startListening() async throws
    func stopListening()
    func speak(_ text: String) async throws
    func setMuted(_ muted: Bool)
    func stop()
}
```

Exact naming is not important.

Keeping its surface this small is important.

---

# 8. Audio capture

Use `AVAudioEngine`, not `AVAudioRecorder`.

Configure:

```text
category: .playAndRecord
mode: .voiceChat
options:
    .defaultToSpeaker
    .allowBluetoothHFP
```

Install an input tap on the microphone node.

Convert incoming audio to:

```text
16 kHz
mono
Float32
```

before passing it to FluidAudio.

Reuse the audio engine for the entire conversation instead of repeatedly creating/destroying it.

---

# 9. Turn detection

Use FluidAudio's Silero VAD rather than a manual dB-only threshold.

FluidAudio exposes `VadManager` and speech-start/speech-end events. ([GitHub][3])

Because this is a language-learning application, don't end the user's turn too aggressively.

Initial tuning:

```text
speech-start:
normal FluidAudio threshold

speech-end:
~1 second continuous silence

minimum utterance:
~250–300 ms

maximum utterance:
30 seconds for the MVP
```

Learners pause while searching for words, so a 300–500 ms silence cutoff will feel hostile.

Do not expose these values as Settings options.

Tune them in code after physical-device testing.

---

# 10. Local mode is turn-based

For MVP:

```text
USER SPEAKING
   ↓
ASR
   ↓
USER STOPS
   ↓
model thinks
   ↓
MURAL SPEAKS
   ↓
MURAL FINISHES
   ↓
microphone listens again
```

While Mural TTS is speaking:

**do not listen for the user's next turn.**

No barge-in.

No echo-cancellation tuning beyond normal `voiceChat`.

No simultaneous listen/speak.

That complexity belongs to GPT-Live premium and should not delay MVP.

---

# 11. Local TTS: use Apple first

For the MVP, use:

```swift
AVSpeechSynthesizer
```

with an English system voice.

Do not add another downloaded TTS model yet.

This dramatically reduces:

* model storage;
* RAM pressure;
* first-use downloads;
* licensing work;
* model lifecycle code;
* potential ANE contention with ASR.

FluidAudio now has excellent local TTS, including Supertonic-3 on iPhone 17 Pro, so we can revisit it after the end-to-end product works. ([GitHub][3])

For MVP the question is:

> Does the local conversation experience work?

Not:

> Which local voice sounds best?

Keep the voice replaceable behind one tiny `LocalSpeechSynthesizer` wrapper, but do not create a generic TTS provider framework.

---

# 12. Add `LocalTutorModel.swift`

Add:

```text
App/LocalTutorModel.swift
```

Use:

```swift
import FoundationModels

SystemLanguageModel.default
LanguageModelSession
```

Apple's iOS 27 system model is specifically intended for on-device text-generation tasks and exposes runtime availability and language-support checks. ([Apple Developer][4])

At startup/local conversation preparation, verify:

```text
model.availability == available
supportsLocale(en)
supportsLocale(vi-VN)
```

If local AI is unavailable:

* show a clear error;
* offer the user the GPT-Live option through Settings;
* **do not silently send their conversation to OpenAI.**

---

# 13. Do not use a persistent unlimited model conversation

Do not rely on `LanguageModelSession` accumulating the full conversation indefinitely.

For every local response, create/bound the model context explicitly.

Use:

```text
current teaching instructions
learner challenge
next goal
words due for review
selected theme
last ~6 passages
latest user passage
```

Mural already builds bounded transcript context rather than blindly sending everything.

Create a local-specific helper such as:

```swift
TeachingPolicy.localContext(...)
```

Do not change the existing Live/Luna context behavior unless required.

Target prompt size should be well under the system model's context limit.

---

# 14. Add a dedicated local teaching prompt

Do not reuse the GPT-Live prompt word-for-word.

Add something like:

```swift
TeachingPolicy.localConversation(...)
```

The instruction should convey:

```text
You are Mural, an English conversation partner for a learner
whose support language is Vietnamese.

Speak primarily in natural, concise English.

The learner may reply in:
- English
- Vietnamese
- or a mixture of both.

Vietnamese is support, not a mistake.

If the learner uses Vietnamese because they do not know an English word:
- infer the intended meaning;
- give the natural English equivalent;
- model it in one short English sentence;
- invite the learner to try it.

Correct at most one meaningful English mistake per turn.
Do not correct every imperfection.
Ask at most one question.
Keep spoken replies short: normally 1–3 sentences.
Never invent current news or claim to browse the web.
```

Preserve the useful current Mural principles:

* accept support languages;
* bridge them back to the target language;
* keep corrections gentle;
* teach only a few expressions at once;
* don't lecture.

The existing Mural voice prompt already contains much of this philosophy.

---

# 15. Streaming model generation

Use Apple's:

```swift
LanguageModelSession.streamResponse(...)
```

rather than waiting for a full response.

Apple's Foundation Models framework supports streamed text and streamed `Generable` output. ([Apple Developer][5])

For the first implementation:

```text
stream reply into UI immediately
→ wait for complete reply
→ speak it
```

Do **not** initially implement streamed sentence-by-sentence TTS.

That is an optimization.

Measure full-response latency first.

If the response gap is too long, then add a small sentence accumulator later.

This ordering avoids premature complexity.

---

# 16. Add local conversation branching to `ConversationCoordinator`

Do not create a new coordinator.

Modify the existing one.

Internally keep:

```swift
private let transport = LiveTransport()
private let localEngine = LocalConversationEngine()
private let localTutor = LocalTutorModel()
```

Add a small operational preference:

```text
mural.usePremiumVoice
```

Use `UserDefaults` for this MVP rather than modifying Mural's learning-backup schema.

Why:

* it is an operational/provider choice;
* it does not belong to learning history;
* avoids unnecessary Archive v3 migration;
* easy to remove/change later.

Effective mode:

```text
usePremiumVoice == false
    → local

usePremiumVoice == true
    → existing GPT-Live
```

---

# 17. Modify `start()`

Current `start()` requires AI consent and an OpenAI API key before beginning.

Refactor to:

```text
start()
  │
  ├── premium?
  │      ↓
  │   existing GPT-Live start path
  │
  └── local?
         ↓
      startLocal()
```

`startLocal()` should:

1. Require learning language `en`.
2. Require meaning/support language `Vietnamese`.
3. Check Apple Foundation Model availability.
4. Create new `SessionRecord`.
5. Prepare/prewarm local ASR.
6. Generate a short greeting/question.
7. Speak greeting.
8. Start listening.

No API key check.

No OpenAI consent.

No network call.

---

# 18. Add Vietnamese to `MeaningLanguages`

Current Mural does not include Vietnamese among meaning languages.

Add:

```text
Vietnamese
```

and a greeting:

```text
Xin chào!
```

For this MVP, reuse:

```text
meaningLanguage
```

as the learner's **support language**.

Do **not** introduce a second `supportLanguage` preference yet.

For an English learner:

```text
learningLanguageID = "en"
meaningLanguage = "Vietnamese"
```

is enough.

Later we can separate "subtitle language" and "support language" if users demonstrate a real need.

---

# 19. Fix onboarding consent

This is important.

Current onboarding says that Mural sends audio/text to OpenAI and automatically records consent.

That must no longer happen for local users.

Change onboarding copy to something like:

> Mural can process conversations on this iPhone. If you later turn on GPT-Live, Mural will ask before sending audio and text to OpenAI.

Do **not** set:

```swift
aiConsentVersion
```

during ordinary local onboarding.

Instead:

* local conversation → no cloud AI consent needed;
* first premium GPT-Live start → existing AI consent sheet appears;
* after user agrees → existing premium behavior continues.

This makes privacy behavior truthful.

---

# 20. Final transcript handling

For each finalized local ASR turn:

create one normal Mural:

```swift
Fragment(
    speaker: .user,
    text: transcript,
    startMS: ...,
    endMS: ...
)
```

Append it to the current `SessionRecord`.

Do not store FluidAudio's partial transcription fragments as Mural transcript fragments.

Only persist the finalized utterance.

For the assistant:

* keep partial streamed model output only as transient UI state;
* once generation is complete, append **one assistant Fragment** containing the final reply.

This keeps the existing transcript/assessment grouping predictable.

---

# 21. Do not copy MAIChat's filler removal

MAIChat currently removes filler words such as:

```text
uh
um
hmm
```

and collapses repeated/stuttered words before using the transcript.

Do not do this in Mural.

For a language learner:

> “I... um... went... went to the supermarket.”

contains potentially meaningful fluency/retrieval evidence.

For MVP:

```text
persist raw finalized ASR transcript
```

and let the model interpret it.

No transcription cleanup beyond:

* trimming accidental whitespace;
* removing ASR control/language-tag tokens if FluidAudio doesn't already do so.

Never strip Vietnamese diacritics.

---

# 22. Learning assessment stays separate from conversation reply

Do not combine reply + assessment into one giant structured model response yet.

Keep the architecture conceptually similar to current Mural:

```text
USER TURN
   │
   ├── immediately generate conversational reply
   │
   └── asynchronously assess learning evidence
```

The reply always has priority.

Create a `@Generable` local structure matching the useful fields of Mural's current assessment:

```swift
@Generable
struct LocalAssessmentResult {
    var outcome: String
    var suggestedLevel: Int
    var nextGoal: String
    var capability: String
    var words: [LocalWordEvidence]
}
```

Then map it into the existing:

```swift
Assessment
WordProposal
```

and **still pass it through**:

```swift
LearningEngine.validate(...)
```

before saving.

Apple's Foundation Models framework provides guided/structured generation specifically for typed outputs like this. ([Apple Developer][6])

---

# 23. Assessment rules for Vietnamese support

The local assessment prompt must explicitly state:

```text
Target language: English.

Vietnamese is the learner's support language.

Do not award English competence for Vietnamese words or sentences.

If a learner uses Vietnamese to ask for help, treat it as context,
not English production.

If Mural just modeled an English phrase and the learner repeats it,
that is assisted production.

Only later unprompted English recall can count as independent.
```

This is compatible with the existing `LearningEngine`, which already downgrades recently modeled or visibly assisted words from independent to assisted evidence.

Do not modify that logic unless a failing test demonstrates a need.

---

# 24. Prioritize conversation over assessment

Do not let background learning assessment delay the next conversational reply.

Rule:

```text
conversation response > assessment
```

If a new user turn finishes while a previous assessment is still running:

* cancel the stale/background assessment task if possible;
* generate the conversational response first;
* retry/submit assessment later only if straightforward.

Never make the learner wait because Mural is scoring vocabulary.

---

# 25. Meaning subtitles

For MVP, keep the existing UI and `MeaningController`.

Branch its provider:

```text
premium mode
→ existing Luna translation

local mode
→ Apple SystemLanguageModel short translation/explanation
```

Do not add Apple's separate Translation framework in this MVP.

That can replace the generative translation later if needed.

Local prompt:

```text
Translate this English assistant utterance into natural Vietnamese.
Return only the Vietnamese meaning.
Do not answer questions contained in the text.
```

Cache it in `session.translations` exactly as Mural does today.

That avoids touching most existing UI.

---

# 26. Word lookup

Current `lookup()` calls Luna.

Branch it:

```text
premium
→ existing APIClient

local
→ SystemLanguageModel
```

Local prompt:

```text
Explain this English word or short phrase to a Vietnamese learner.
Use concise Vietnamese.
Give the contextual meaning in 2–3 sentences maximum.
```

No dictionary infrastructure needed.

---

# 27. Typed replies

Keep typed replies working.

In local mode:

```text
typed text
→ local tutor model
→ assistant English response
→ optional local TTS if conversation is active
```

No OpenAI.

The typed message may be Vietnamese, English or mixed.

---

# 28. “A little help”

In local mode, when the user taps **A little help**:

take the most recent assistant passage and ask the local model to:

```text
Explain or restate the last idea more simply.
Use clear English.
If useful, include one short Vietnamese clarification.
Then give one small English example.
```

Speak the result.

Do not introduce a separate help engine.

---

# 29. Disable current-topic search in local mode

The existing "today/current topic" path performs OpenAI web search.

For the MVP:

```text
local mode:
current topic / fresh web search unavailable

premium:
existing behavior unchanged
```

Either disable that theme or show:

> Current topics require the online conversation mode.

Do not build local web search.

---

# 30. Settings changes

Add a simple section near the top:

### Conversation

```text
On-device
Free · Private · A little slower

GPT-Live
Natural realtime conversation · Uses OpenAI API
```

A simple Picker or two-option control is sufficient.

Disable switching while a conversation is running.

When local is selected:

* hide or de-emphasize OpenAI API-key setup;
* clearly state "No OpenAI key needed."

When GPT-Live is selected:

* retain the existing API-key UI;
* retain usage estimate;
* retain OpenAI privacy text.

Do not implement subscription/payment UI.

"Premium" is architectural/product language for now, not a StoreKit implementation.

---

# 31. Update status strings

Local phase should produce understandable UI states:

```text
preparing → "Preparing on-device voice…"
listening → "I'm listening"
thinking → "Thinking…"
speaking → "Mural is speaking"
muted → "Microphone muted"
```

Reuse the existing Mural orb.

Input mic level can continue animating it while listening.

While TTS is speaking, a fixed moderate output energy is sufficient for MVP.

Do not build TTS waveform analysis.

---

# 32. Keep premium behavior unchanged

Do not refactor GPT-Live to use Apple's model in this PR.

Premium remains:

```text
GPT-Live
+
existing GPT-5.6 Luna secondary calls
```

This deliberately gives us a known-good comparison.

Once local mode works, a follow-up can investigate replacing premium's Luna calls with `SystemLanguageModel`.

This separation makes regressions much easier to diagnose.

---

# 33. Error behavior

Local mode must handle these explicitly:

### Apple model unavailable

Examples:

* Apple Intelligence disabled;
* model still downloading;
* device not eligible.

Show an actionable message.

Do not silently switch to cloud.

### FluidAudio model unavailable/downloading

Show:

> Preparing offline speech recognition…

If download fails:

> Mural couldn't prepare offline speech recognition. Check your connection and try again.

### Model generation failure

Save the user's transcript.

Show a short retry message.

Do not lose the conversation.

### ASR produces empty result

Ignore it and resume listening.

### App backgrounds

Stop local microphone/TTS/model work and save the conversation using the same philosophy as current Mural.

---

# 34. Model preparation

Borrow MAIChat's idea of explicit:

```text
modelsMissing
warmingUp
ready
failed
```

but implement it against FluidAudio 0.15.7 rather than copying its old ASR code. MAIChat's prewarming pattern is useful because it performs model preparation off the main actor and surfaces readiness separately.

For MVP:

* first local conversation may download Nemotron assets;
* cache them using FluidAudio's normal model cache;
* subsequent sessions reuse them;
* prewarm ASR when Talk becomes active or immediately before local conversation start.

Do not bundle hundreds of MB of model weights into the app binary yet.

---

# 35. Logging and benchmark instrumentation

Add **DEBUG-only** timing instrumentation.

For every local user turn record:

```text
speechStart
speechEnd
asrFinal
llmRequestStart
llmFirstOutput
llmComplete
ttsStart
ttsComplete
```

Log durations such as:

```text
ASR finalize:
speechEnd → asrFinal

model TTFT:
llmRequestStart → llmFirstOutput

first audible response:
speechEnd → ttsStart

total response:
speechEnd → ttsComplete
```

Also periodically record:

```swift
ProcessInfo.processInfo.thermalState
```

and, if easy, current process memory.

Do not send analytics anywhere.

These are local DEBUG logs only.

---

# 36. Physical-device acceptance test

The MVP is not complete based on Simulator tests.

Test on an iPhone 17-class physical device running iOS 27.

Run at least 20 turns continuously.

Test these four utterance classes repeatedly:

```text
PURE ENGLISH
"Yesterday I went to the supermarket."

PURE VIETNAMESE
"Tôi không hiểu câu đó."

ENGLISH + VIETNAMESE MISSING WORD
"Yesterday I went to siêu thị. How do I say that in English?"

NATURAL CODE-SWITCHING
"I don't really understand cái từ này. Can you explain it?"
```

Also test:

```text
"How do I say 'đi chợ' in English?"

"I went to the market."

"Yesterday I go to work."

"Em không biết từ này."

"What does 'appointment' mean?"

"I have an appointment tomorrow."
```

---

# 37. MVP quality gates

Do not call the feature successful merely because it runs.

The local mode should meet these targets on the physical device:

### Functional

* Starts without an OpenAI API key.
* Works in airplane mode **after required model assets are cached**.
* Pure English transcription is reliable.
* Pure Vietnamese support turns are understandable.
* Common English/Vietnamese mixed turns retain enough meaning for the tutor to respond correctly.
* Tutor normally replies in English.
* Vietnamese assistance is accepted rather than treated as a mistake.
* AI bridges Vietnamese words back into English.
* Session transcript persists correctly.
* English vocabulary evidence is recorded.
* Vietnamese words are not recorded as English competence.
* Immediate repetition is treated as assisted evidence.
* Existing GPT-Live mode still works.

### Latency

Primary metric:

> **end of user's speech → first audible Mural speech**

Targets:

```text
≤ 2.0 sec median      excellent
≤ 2.5 sec median      MVP success
2.5–3.5 sec           usable but needs optimization
> 3.5 sec median      do not ship free mode yet
```

Do not optimize sentence-level streaming TTS until this is measured.

### Stability

A 20-minute test should:

* not crash;
* not trigger repeated memory pressure;
* not reach sustained critical thermal state;
* not progressively get slower because model context keeps growing.

---

# 38. Automated tests

Add focused tests only.

Do not attempt to unit-test FluidAudio or Apple's model.

Add tests for:

### Teaching policy

Given:

```text
target = English
support = Vietnamese
```

verify local instructions:

* say English is target;
* allow Vietnamese support;
* tell model to bridge Vietnamese to English;
* limit reply length;
* forbid web/current-event claims.

### Learning evidence

Create fixture:

```text
USER: "Tôi không biết từ này."
ASSISTANT: "You can say 'supermarket'."
USER: "Supermarket."
```

verify `"supermarket"` is not independent evidence immediately.

Then add a later independent passage and verify it can become independent.

### Mode routing

Verify:

```text
local mode:
does not require CredentialStore.hasKey

premium:
still requires API key
```

### Transcript persistence

Verify local user/assistant fragments serialize through `Archive`.

### Support language

Verify `MeaningLanguages` accepts `"Vietnamese"`.

No giant mock framework is needed.

---

# 39. UI tests

Update/add only a few native UI tests:

```text
Onboarding can choose:
English
Vietnamese meaning/help language

Local mode can be selected without API key.

GPT-Live mode still exposes API key UI.

Starting local mode does not show OpenAI consent.

Starting GPT-Live without prior consent does show OpenAI consent.
```

Do not attempt microphone/model inference in UI automation.

Physical-device testing covers that.

---

# 40. Files likely to change

Expected existing files:

```text
Mural.xcodeproj/project.pbxproj
App/ConversationCoordinator.swift
App/LibraryViews.swift
App/OnboardingView.swift
App/RootView.swift
App/ThirdPartyNotices.txt
Core/TeachingPolicy.swift
Core/Languages/LanguageModule.swift
Tests/...
UITests/...
```

Expected new files:

```text
App/LocalConversationEngine.swift
App/LocalTutorModel.swift
```

Optionally one tiny helper:

```text
App/ConversationMode.swift
```

Do not create ten new abstractions/directories.

---

# 41. Things specifically not to import from MAIChat

Do **not** copy:

```text
LLMEvaluator.swift
ModelCatalogService.swift
Models.swift model catalogue
MLXLLM dependency
MLXLMCommon dependency
DeepSeek/Qwen/Llama model picker
TranscriptionFilter filler removal
AVAudioRecorder file-dictation flow
```

MAIChat proves that local inference and FluidAudio work on iOS; it should not dictate Mural's new architecture.

Its existing local LLM evaluator is useful reference material for cancellation/lifecycle, but Apple's system model makes that whole model-management layer unnecessary for this MVP.

---

# 42. Do not add Gemma 4 yet

The benchmark you supplied makes Gemma 4 worth evaluating later.

But adding it now would require:

```text
MLX runtime
+
several GB of weights
+
download management
+
model switching
+
memory management
+
prompt compatibility testing
```

before we even know whether Apple's free system model is insufficient.

That is exactly the kind of scope expansion the MVP should avoid.

After the local Apple version is measured, the follow-up experiment can compare:

```text
Apple SystemLanguageModel
vs
LFM2.5-2.6B
vs
Gemma 4 E2B
```

using the **same Mural turn prompt and test corpus**.

No architecture decision today should prevent that, but no code for it is needed today.

---

# 43. Definition of done

The implementation is finished when I can install Mural on a physical iPhone 17, configure:

```text
Learning language: English
Help / meaning language: Vietnamese
Conversation mode: On-device
```

with **no OpenAI API key**, tap Talk, and have this interaction:

```text
MURAL:
Hi! What did you do today?

USER:
Today I went to... siêu thị. I don't know that word in English.

MURAL:
You can say "supermarket."
Try: "Today I went to the supermarket."

USER:
Today I went to the supermarket.

MURAL:
Exactly. What did you buy there?
```

and then:

* see the transcript saved;
* see appropriate English learning evidence;
* see Vietnamese excluded from English competence;
* have the whole exchange run locally;
* end the session;
* switch Settings to GPT-Live;
* confirm the existing premium path still works.

That is the MVP.

---

## Implementation order

I would have the agent execute in this sequence:

**Phase 1 — Baseline and dependencies**
Run current Mural tests/build. Create feature branch. Raise MVP target to iOS 27. Pin FluidAudio `v0.15.7`. Confirm existing premium app still builds.

**Phase 2 — Local speech probe inside Mural**
Build `LocalConversationEngine` with AVAudioEngine + FluidAudio multilingual Nemotron + VAD. Print finalized English/Vietnamese transcripts. No LLM yet. Validate code-switching on the phone.

**Stop here if Vietnamese/English ASR is unusable.** Do not build around bad ASR.

**Phase 3 — Apple local tutor**
Add `LocalTutorModel`. Feed hardcoded/transcribed text into SystemLanguageModel. Confirm Vietnamese-support → English teaching responses.

**Phase 4 — End-to-end turn**
ASR → local model → system TTS → listen again.

At this point measure first-audio latency before adding anything else.

**Phase 5 — Integrate Mural records**
Append normal user and assistant `Fragment`s. Persist SessionRecord. Keep UI captions working.

**Phase 6 — Learning evidence**
Add local structured assessment and feed it through existing `LearningEngine.validate`.

**Phase 7 — Existing supporting features**
Local Meaning, Lookup, Help and typed replies. Disable current-topic search locally.

**Phase 8 — Product UI/privacy**
Add On-device vs GPT-Live setting. Fix OpenAI consent so it appears only for GPT-Live. Add Vietnamese Meaning language.

**Phase 9 — Tests and physical validation**
Run core/UI tests, then the bilingual 20-minute physical-device script.

Only after that should anyone start optimizing TTS, trying Gemma 4, adding barge-in, or replacing Luna in premium mode.

That sequencing is important: **prove the one hard assumption—usable English/Vietnamese local conversation—before adding polish.**

The two external implementation facts I would pin in the handoff are that FluidAudio's current stable release is `v0.15.7` , and iOS 27's Foundation Models framework exposes the newer `SystemLanguageModel`, locale support checks, and streaming `LanguageModelSession` APIs we need. ([Apple Developer][7])

[1]: https://huggingface.co/smcleod/nemotron-3.5-asr-streaming-0.6b-int8/blob/main/config.json?utm_source=chatgpt.com "config.json · smcleod/nemotron-3.5-asr-streaming-0.6b-int8 at main"
[2]: https://huggingface.co/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML?utm_source=chatgpt.com "FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML · Hugging Face"
[3]: https://github.com/FluidInference/FluidAudio?utm_source=chatgpt.com "GitHub - FluidInference/FluidAudio: Frontier CoreML audio models in your apps — text-to-speech, speech-to-text, voice activity detection, and speaker diarization. In Swift, powered by SOTA open source. · GitHub"
[4]: https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel?changes=_10_5&utm_source=chatgpt.com "SystemLanguageModel | Apple Developer Documentation"
[5]: https://developer.apple.com/documentation/foundationmodels/languagemodelsession?utm_source=chatgpt.com "LanguageModelSession | Apple Developer Documentation"
[6]: https://developer.apple.com/documentation/foundationmodels/languagemodelsession/streamresponse%28generating%3Aincludeschemainprompt%3Aoptions%3Aprompt%3A%29?changes=_6_2%2C_6_2%2C_6_2%2C_6_2&utm_source=chatgpt.com "streamResponse(generating:includeSchemaInPrompt:options:prompt:) | Apple Developer Documentation"
[7]: https://developer.apple.com/documentation/Updates/FoundationModels?utm_source=chatgpt.com "Foundation Models updates | Apple Developer Documentation"
