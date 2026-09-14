# Local conversation feasibility probes

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
