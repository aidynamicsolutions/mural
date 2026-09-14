# Mural ASR Direction: Parakeet CTC 0.6B Vietnamese–English Code-Switching

## Purpose

This document captures the recommended direction for fixing Mural's current local-ASR blocker:

> The current FluidAudio Nemotron path does not reliably preserve **Vietnamese + English code-switching inside the same utterance**.

Example:

> "Yesterday I went to **siêu thị**, but I don't know the English word."

The proposed replacement is:

> **NVIDIA Parakeet CTC 0.6B — Unified Vietnamese–English Code-Switching**

The goal is to keep the rest of Mural's local conversation architecture intact and replace only the ASR recognizer used for the `English target + Vietnamese support` pair.

---

# Recommendation

Do **not** spend more time trying to force Nemotron's automatic language mode to handle intra-sentence English/Vietnamese switching.

Instead:

1. Keep FluidAudio for:
   - microphone capture
   - VAD
   - audio buffering
   - 16 kHz mono conversion
   - turn-boundary detection
2. Replace the Nemotron recognizer for this language pair with **NVIDIA Parakeet CTC 0.6B Unified Vietnamese–English CS**.
3. Start with **turn-based final transcription**, not continuous streaming CTC:
   - collect one VAD-delimited user turn
   - run the bilingual CTC recognizer
   - return one mixed-language transcript
   - pass that transcript to Apple's local Foundation Model
4. First prove this with an isolated benchmark before integrating deeply into Mural.

---

# Why Nemotron is failing

The current streaming Nemotron/RNN-T approach can become biased toward the language already being decoded.

When a speaker switches language in the middle of one continuous utterance, the beginning of the new language can be dropped, blanked, or decoded as though it belonged to the original language.

This is a particularly poor fit for natural learner speech such as:

- "Yesterday I went to **siêu thị**."
- "I don't know **cái từ này**, how do I say it?"
- "Hôm qua tôi **went to the supermarket**."
- "Yesterday **em đi shopping với bạn**."

A third-party Nemotron streaming implementation documents the same kind of language-switching failure.

Source:

- Nemotron streaming implementation / language-switch issue context:  
  https://github.com/kdrkdrkdr/nemotron-asr-streaming.c

---

# Best-fit model: NVIDIA Parakeet CTC 0.6B Vietnamese–English

NVIDIA provides a model specifically aimed at **Vietnamese + English code-switching**, rather than a generic multilingual ASR model that must choose one dominant language.

Model:

**Parakeet-CTC-0.6B Unified Vietnamese–English CS**

Key properties:

- approximately 600M parameters
- FastConformer + CTC architecture
- trained for Vietnamese and English
- intended to preserve code-switched speech
- suitable for the exact Mural use case:
  - Vietnamese native speaker
  - learning English
  - naturally falling back to Vietnamese inside an English sentence

Official sources:

- NVIDIA ASR support matrix / Vietnamese-English support:  
  https://docs.nvidia.com/nim/speech/26.02.0/asr/index.html

- Official NVIDIA model card:  
  https://huggingface.co/nvidia/parakeet-ctc-0.6b-Vietnamese

The official model card describes the model as a unified Vietnamese–English code-switching ASR model and documents the training/configuration details.

---

# Why this is a better fit for Mural

Instead of:

```text
"I went to siêu thị yesterday"
        ↓
generic multilingual recognizer
        ↓
choose one language
        ↓
Vietnamese phrase is damaged or dropped
```

the intended behavior is:

```text
"I went to siêu thị yesterday"
        ↓
Vietnamese–English bilingual CTC
        ↓
"I went to siêu thị yesterday"
```

There is no requirement to decide that the whole utterance is "English" or "Vietnamese."

That is the key architectural advantage.

---

# Core ML / iPhone feasibility

There are already community Core ML conversions of this model.

## Candidate 1

A split Core ML version provides:

- `MelSpectrogram.mlmodelc`
- `AudioEncoder.mlmodelc`
- `vocab.json`
- Neural Engine / GPU execution path
- iOS compatibility
- roughly phone-feasible memory/model size

Source:

- Community Core ML conversion:  
  https://huggingface.co/leakless/parakeet-ctc-0.6b-Vietnamese-coreml

## Candidate 2

Another Core ML conversion / implementation:

- alternative Core ML package:  
  https://huggingface.co/ancs21/parakeet-ctc-0.6b-vi-coreml

These should be treated as **proof-of-concept assets**, not automatically as production artifacts.

For production, prefer re-exporting from NVIDIA's official weights so the build has:

- reproducible conversion
- controlled quantization
- verified vocabulary
- known provenance
- correct NVIDIA model licensing/attribution

Official base model license/source:

- https://huggingface.co/nvidia/parakeet-ctc-0.6b-Vietnamese

---

# FluidAudio integration opportunity

Current FluidAudio already contains infrastructure for loading custom Core ML CTC models directly from disk.

Relevant source file:

- `CtcModels.swift`  
  https://github.com/FluidInference/FluidAudio/blob/main/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/CustomVocabulary/WordSpotting/CtcModels.swift

The public loader supports a directory containing:

```text
MelSpectrogram.mlmodelc/
AudioEncoder.mlmodelc/
vocab.json
```

This matches the layout used by the Vietnamese Core ML conversion.

Relevant method:

```swift
CtcModels.loadDirect(from:)
```

This means the implementation should first investigate whether the bilingual Parakeet model can be loaded using FluidAudio's existing Core ML/CTC infrastructure rather than creating a completely separate inference stack.

Also relevant:

- FluidAudio custom vocabulary / CTC documentation:  
  https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/CustomVocabulary.md

- FluidAudio current repository:  
  https://github.com/FluidInference/FluidAudio

---

# Proposed Mural architecture

Keep the existing local conversation pipeline:

```text
microphone
    ↓
FluidAudio VAD
    ↓
collect one completed user turn
    ↓
Vietnamese-English Parakeet CTC
    ↓
mixed EN/VI transcript
    ↓
Apple SystemLanguageModel
    ↓
English teaching response
    ↓
local TTS
```

Do not replace the entire FluidAudio audio layer.

Replace only the recognizer used for:

```text
learning language = English
support language = Vietnamese
```

---

# MVP integration strategy

## Phase 1 — Isolated ASR benchmark first

Before touching the full Mural conversation flow, create a very small test harness.

Use the same WAV/audio samples against:

1. current Nemotron implementation
2. Parakeet CTC Vietnamese–English

Suggested test utterances:

### Pure English

> "Yesterday I went to the supermarket."

### Pure Vietnamese

> "Hôm qua tôi đi siêu thị."

### English → Vietnamese

> "Yesterday I went to siêu thị."

### Vietnamese → English

> "Hôm qua tôi went to the supermarket."

### Natural code-switch

> "I don't know cái từ này, how do I say it?"

### Natural learner speech

> "Yesterday em đi shopping với bạn."

### Missing English vocabulary

> "How do I say đi chợ in English?"

### Mixed support phrase

> "I went to... em không biết nói sao... the market?"

Measure:

- preservation of English words
- preservation of Vietnamese words
- words lost at switch boundaries
- semantic correctness
- latency
- memory usage
- thermal behavior on physical iPhone

Do not use generic WER alone as the acceptance criterion.

The important metric is:

> Does the transcript preserve enough of both languages for the tutoring model to understand the learner correctly?

---

# Phase 2 — Add a small recognizer adapter

Suggested new file:

```text
App/VietnameseEnglishRecognizer.swift
```

Keep the responsibility narrow.

Possible interface:

```swift
final class VietnameseEnglishRecognizer {
    func prepare() async throws

    func transcribe(
        samples: [Float],
        sampleRate: Double
    ) async throws -> String
}
```

Responsibilities:

- load bilingual Core ML model assets
- accept finalized 16 kHz mono Float32 audio
- normalize/pad/chunk audio as required
- run model inference
- perform CTC greedy decode
- preserve Vietnamese Unicode/diacritics
- return one final transcript

Do **not** add:

- generic model provider architecture
- model catalogue
- language detector
- runtime model selection UI
- MLX
- cloud fallback

The language pair itself decides which recognizer to use.

---

# Phase 3 — Reuse FluidAudio around the recognizer

Keep the implementation agent's current working pieces:

```text
FluidAudio microphone path
FluidAudio VAD
audio session management
turn-end detection
buffer lifecycle
```

Only replace:

```text
Nemotron transcription
```

with:

```text
Vietnamese-English Parakeet CTC transcription
```

for the English + Vietnamese support configuration.

---

# Phase 4 — Keep it turn-based first

Do not attempt full streaming CTC in the first implementation.

Use:

```text
user speaks
    ↓
VAD detects end of turn
    ↓
run Parakeet CTC on completed turn
    ↓
final transcript
    ↓
Apple local tutor model
```

This is acceptable for the free/on-device Mural tier.

The product goal is not GPT-Live-level full duplex. That remains the premium feature.

Turn-based recognition is simpler and gives the best chance of getting code-switch accuracy right.

---

# Expected model asset shape

The Core ML conversion should expose something equivalent to:

```text
MelSpectrogram.mlmodelc
AudioEncoder.mlmodelc
vocab.json
```

The implementation agent should inspect the actual Core ML package shapes before assuming the FluidAudio loader is plug-and-play.

Potential mismatch areas to verify:

- input tensor names
- output tensor names
- mel frontend assumptions
- maximum audio duration
- padding requirements
- sample rate
- vocabulary indexing
- blank token ID
- CTC collapse behavior
- quantized vs float model expectations

Do not assume all community conversions use exactly the same tensor contract.

---

# CTC decoding

If the Core ML package returns per-frame CTC logits:

1. take argmax token per valid frame
2. collapse repeated consecutive token IDs
3. remove blank token
4. map IDs through `vocab.json`
5. detokenize correctly
6. normalize whitespace
7. preserve Vietnamese diacritics exactly

Important:

Do not run MAIChat-style filler/stutter cleanup on this transcript.

For language learning:

> "I... um... went to siêu thị"

contains pedagogically useful information.

Only remove model/control tokens if needed.

---

# Audio chunking

Some existing Core ML conversions are built around fixed-duration windows, commonly around 15 seconds.

For the Mural MVP:

- cap normal user turns well below that where practical
- if required, pad short turns to the model's expected input shape
- for long turns, use overlapping chunks only after the basic short-turn path works

Do not start by implementing sophisticated long-form stitching.

Typical Mural user turns should be short.

---

# Physical-device requirements

Do not accept Simulator-only success.

Test on the actual target iPhone.

Record:

```text
model load time
ASR inference time
peak memory
thermal state
battery impact
code-switch accuracy
```

Primary success condition:

> Mixed Vietnamese/English utterances are semantically preserved significantly better than the current Nemotron path.

---

# Alternatives researched

## Whisper / WhisperKit

Whisper has excellent iOS tooling through WhisperKit and strong multilingual recognition generally.

Source:

- WhisperKit / Argmax Swift repository:  
  https://github.com/argmaxinc/argmax-oss-swift

However, Whisper often commits to one language for a segment and has documented issues with intra-sentence code switching.

Discussion:

- OpenAI Whisper code-switching discussion:  
  https://github.com/openai/whisper/discussions/2009

Recommendation:

**Do not switch from Nemotron to Whisper specifically to solve this blocker.**

It may simply create a different form of language-switching failure.

---

## Qwen3-ASR 0.6B

Qwen3-ASR supports Vietnamese and English and is interesting as a general multilingual ASR model.

Source:

- Official Qwen3-ASR repository:  
  https://github.com/QwenLM/Qwen3-ASR/

However, there are reports/discussions showing code-switch input being normalized into one language rather than faithfully preserving both.

Relevant discussion:

- Qwen3-ASR code-switching discussion:  
  https://github.com/QwenLM/Qwen3-ASR/discussions/122

Recommendation:

**Do not spend MVP time porting this to iPhone before testing the purpose-built NVIDIA bilingual model.**

---

## Meta Omnilingual ASR

Meta's Omnilingual ASR is interesting longer-term.

It includes relatively small multilingual models and covers a very large number of languages.

Source:

- Meta Omnilingual ASR research page:  
  https://ai.meta.com/research/publications/omnilingual-asr-open-source-multilingual-speech-recognition-for-1600-languages/

However:

- no mature Mural/FluidAudio/Core ML path has been identified yet
- English/Vietnamese intra-utterance code-switching quality is not established for this exact use case

Recommendation:

**Research later, not for the current blocker.**

---

# Current recommendation ranking

| Model | English + Vietnamese | Intra-utterance code switching | iPhone path | Recommendation |
|---|---:|---:|---:|---|
| **Parakeet CTC 0.6B Vietnamese–English** | Yes | **Purpose-built for it** | **Core ML conversions exist** | **Test first** |
| Nemotron multilingual | Yes | Current blocker | Already in FluidAudio | Replace for this pair |
| Whisper Large v3 / Turbo | Yes | Unreliable | WhisperKit | Not first choice |
| Qwen3-ASR 0.6B | Yes | Reports of failures | Possible, more work | Not first choice |
| Meta Omnilingual ASR | Yes | Unverified | No mature path yet | Later research |

---

# Implementation recommendation to the agent

Use the following decision rule:

```text
if learningLanguage == English
and supportLanguage == Vietnamese
    → VietnameseEnglishRecognizer
else
    → existing ASR path
```

Do not generalize this prematurely.

The first objective is simply to prove that the Vietnamese-English bilingual model fixes the concrete user problem.

---

# Production follow-up if the POC works

If the community Core ML model proves good enough:

1. reproduce the conversion from NVIDIA's official checkpoint
2. document exact conversion script/version
3. validate output against the community package
4. benchmark on iPhone 17-class hardware
5. verify NVIDIA model license requirements
6. add required notices/attribution
7. pin/checksum production assets
8. host/download the approved converted model from a controlled source

Do not ship a community checkpoint blindly.

---

# Go / No-Go criteria

## GO

Proceed if:

- mixed English/Vietnamese utterances are preserved reliably
- switch-boundary word loss is materially lower than Nemotron
- latency remains acceptable for turn-based free conversation
- memory fits comfortably alongside:
  - Apple Foundation Model
  - Mural UI
  - VAD/audio buffers
  - TTS
- 20-minute sessions remain stable

## NO-GO

Do not integrate if:

- the model still collapses mixed speech into one language
- code-switch accuracy is only marginally better than Nemotron
- iPhone memory/thermal behavior is unacceptable
- Core ML conversion introduces significant accuracy degradation versus the official checkpoint

---

# Source Links

## NVIDIA / Parakeet

- NVIDIA ASR model support documentation  
  https://docs.nvidia.com/nim/speech/26.02.0/asr/index.html

- Official NVIDIA Parakeet CTC 0.6B Vietnamese model  
  https://huggingface.co/nvidia/parakeet-ctc-0.6b-Vietnamese

## Core ML conversions

- `leakless/parakeet-ctc-0.6b-Vietnamese-coreml`  
  https://huggingface.co/leakless/parakeet-ctc-0.6b-Vietnamese-coreml

- `ancs21/parakeet-ctc-0.6b-vi-coreml`  
  https://huggingface.co/ancs21/parakeet-ctc-0.6b-vi-coreml

## FluidAudio

- FluidAudio repository  
  https://github.com/FluidInference/FluidAudio

- Custom CTC model loader (`CtcModels.swift`)  
  https://github.com/FluidInference/FluidAudio/blob/main/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/CustomVocabulary/WordSpotting/CtcModels.swift

- FluidAudio custom vocabulary / CTC documentation  
  https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/CustomVocabulary.md

## Nemotron switching issue context

- Independent Nemotron streaming implementation  
  https://github.com/kdrkdrkdr/nemotron-asr-streaming.c

## Whisper

- WhisperKit / Argmax Swift  
  https://github.com/argmaxinc/argmax-oss-swift

- Whisper intra-sentence code-switching discussion  
  https://github.com/openai/whisper/discussions/2009

## Qwen3-ASR

- Official Qwen3-ASR repository  
  https://github.com/QwenLM/Qwen3-ASR/

- Code-switching discussion  
  https://github.com/QwenLM/Qwen3-ASR/discussions/122

## Meta Omnilingual ASR

- Meta Omnilingual ASR research  
  https://ai.meta.com/research/publications/omnilingual-asr-open-source-multilingual-speech-recognition-for-1600-languages/

---

# Short instruction to implementation agent

> Stop trying to make the existing Nemotron multilingual recognizer solve intra-sentence English/Vietnamese code switching.
>
> First build an isolated benchmark for **NVIDIA Parakeet CTC 0.6B Unified Vietnamese–English CS** using the available Core ML conversion. Compare it directly against the current Nemotron path using realistic mixed Vietnamese/English learner speech.
>
> If it materially improves switch-boundary preservation and remains viable on iPhone hardware, integrate it as a narrow `VietnameseEnglishRecognizer` used only when the target language is English and the support language is Vietnamese.
>
> Keep FluidAudio's existing microphone, VAD, buffering, and turn-detection infrastructure. Do not redesign the rest of Mural or introduce a generic ASR-provider framework for this MVP.
