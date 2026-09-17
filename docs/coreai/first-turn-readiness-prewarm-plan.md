# First-turn readiness and staged decoder prewarm handoff

Status: **early-start implementation retained after five early/late physical-device trial pairs; cold-start benefit remains bounded by one cold observation.**

## Goal

Remove two avoidable sources of first-turn friction in On-device Talk without changing ASR quality, decoder policy, model weights, model precision, tokenizer behavior, frontend behavior, fallback policy, or the default build backend:

1. Do not invoke the local meaning model for the fixed application-authored greeting `Hi! What did you do today?`. Its Vietnamese meaning is deterministic and can be served as an immutable built-in cache entry.
2. Start a decoder-only Core ML prewarm as the greeting begins. Let that work overlap the greeting and the user's thinking/recording time, then require it to drain before the staged Core AI encoder begins after Send.

## Required ownership and safety invariants

- `LocalConversationEngine.WhisperRecognizer` remains the ASR model owner.
- The staged encoder remains the existing frozen FP16 Core AI GPU-preferred encoder. Do not change its weights, precision, frontend, tensor contracts, tokenizer, or decoding options.
- The decoder remains the existing WhisperKit/Core ML text decoder with `.cpuAndNeuralEngine` compute. This is not a Core AI decoder experiment.
- Speculative decoder prewarm must never overlap the Core AI encoder. Send must await the exact prewarm task before entering staged encoder work.
- The speculative prewarm must not make Record unavailable. It is intentionally excluded from `asrBusy` / `localResourcesBusy`.
- Keep the existing Send-time `WhisperKit.prewarmModels()` and `loadModels()` sequence for this first experiment. The early decoder-only prewarm is intended to warm reusable system/runtime state; it does not replace the proven Send path yet.
- No automatic fallback, cache repair, cache deletion, model retry loop, uninstall, or user-data reset.
- Stop/background/memory-warning handling cancels speculative prewarm. A later Prepare must drain the old task before installing a new recognizer owner.

## Intended first-turn timeline

1. Prepare verifies local assets and tokenizer as before.
2. Mural appends and begins speaking the fixed greeting.
3. Decoder-only speculative prewarm starts with the greeting; Record remains enabled.
4. TTS finishes.
5. The fixed Vietnamese meaning is rendered synchronously from the built-in cache, so no meaning-model load gates Record.
6. User records while decoder prewarm may continue.
7. User taps Send; accepted microphone packets drain and resampling completes.
8. ASR awaits the exact speculative decoder-prewarm task. If it failed, surface the existing turn failure rather than silently retrying/falling back.
9. Only after that task has returned does the staged Core AI encoder start.
10. Encoder scope returns and releases its resources.
11. Existing WhisperKit/Core ML prewarm, load, decode and unload run unchanged.

## Fixed greeting meaning

The built-in mapping is intentionally exact and narrow:

- Learning language: English (`en`)
- Meaning language: Vietnamese
- Text: `Hi! What did you do today?`
- Meaning: `Chào bạn! Hôm nay bạn đã làm gì?`

Any changed greeting, different learning language, different meaning language, or generated tutor response must continue through the ordinary meaning cache/model path.

## Diagnostic events

Use bounded, content-free logs to distinguish the new overlap from Send-time work:

- `asr_staged_decoder_speculative_begin`
- `asr_staged_decoder_speculative_complete ... seconds=`
- `asr_staged_decoder_speculative_cancelled`
- `asr_staged_decoder_speculative_failed`
- `asr_staged_decoder_wait_begin`
- `asr_staged_decoder_wait_complete ... seconds=`
- staged Send-time decoder prewarm/load/decode/unload timings where present

Do not log transcript/audio content.

## Review and qualification

First perform normal source/build checks from the repository verification skill. Then use the paired physical-iPhone workflow: agent builds/installs/collects bounded logs; the user operates the microphone/UI.

The minimum device comparison should cover:

- Fresh explicit opt-in Release launch, Prepare, greeting, and immediate Record availability after TTS.
- Confirm the fixed greeting meaning appears without a local meaning-model wait.
- Immediate Record after the greeting, then a short recording and Send.
- A delayed Record case so speculative prewarm has more wall-clock time before Send.
- At least one second turn to confirm warm-turn behavior is unchanged.
- End while speculative prewarm is active, then restart after drain.
- Background while speculative prewarm is active, then return/resume without overlapping old and new owners.
- Offline operation remains intact.
- No recorded memory warning, no automatic fallback, no cache mutation, and no decoder/Core AI encoder overlap in logs.

Compare Send-to-final timing against the preserved first-turn observation (46.87 seconds, with encoder release about three seconds after Send) and warm-turn observations (5.54/5.84 seconds). Those historical numbers are evidence references, not acceptance thresholds. Report the new decoder wait, Send-time prewarm/load, and total Send-to-final values rather than claiming the cold cost disappeared.

## Background restoration status

Latest user testing accepts the background-restoration correction. Treat that as **human-confirmed acceptance**, not agent-observed verification and not proof of every prolonged-suspension/process-replacement scenario. Do not repeat the old full replay checklist unless a new lifecycle regression appears.

## Success criteria

- Record becomes available as soon as the fixed greeting TTS/start task finishes; no initial meaning-model loading gate remains.
- Speculative decoder prewarm begins with greeting TTS, not after it.
- Recording can proceed while speculative prewarm runs.
- Send waits for speculative prewarm to finish before the Core AI encoder begins.
- Existing staged quality and decode settings are unchanged.
- First-turn Send-to-final latency materially decreases on a cold process without introducing warnings, ownership overlap, fallback, or lifecycle regressions.

If the speculative prewarm does not make the subsequent Send-time decoder path cheaper on the phone, preserve the evidence and remove/reconsider this optimization rather than broadening model residency or changing decoding policy.
