# Local-agent prompt — FireRedASR2-AED only

Start this as a separate work item after the Breeze checkpoint is recorded.

---

Work in `aidynamicsolutions/mural`, branch `mvp`, preserving user changes and all
accepted Breeze/PhoWhisper behavior, assets, signing and learning data. Read
`docs/asr/chinese/README.md`, `firered-aed-plan.md` and `host-checks.md`.
Do not restart Breeze conversion or create another broad research plan.

The delivered FireRed work is a plan and local AED replay helper, NOT a native
Swift implementation. Implement the smallest maintained-runtime iPhone probe first.

1. Record source head and toolchain. Run the ChineseASR Python tests and relevant
   existing repository gates. Pin the official FireRedASR2-AED checkpoint, its v2
   ONNX conversion and a sherpa-onnx runtime with dynamic v2 decoder-cache support.
   Inspect the actual source/export metadata and hashes, including external weight
   files and tokens. The 2025 v1 download named in an old example is NOT v2. Reject
   CTC-only, LLM and whole FireRedASR2S pipeline substitutions. Record licenses/notices.
2. Use a copied `mainland-smoke.template.json` and private human-checked recordings.
   Run `run_reference.py firered-onnx` against the exact local INT8 AED encoder,
   decoder and tokens. It uses `from_fire_red_asr`, not a CTC API. Start with a few
   clips and preserve failure reports. Compare a small matched sample with official
   v2 AED PyTorch separately before claiming export parity. No test audio is uploaded.
3. Build the pinned maintained sherpa iOS library/XCFramework using its actual headers
   and C/Swift examples. Do not guess APIs, write a custom beam decoder or attempt a
   new Core ML conversion. Use supported CPU execution first and do not promise ANE
   placement. This is the only new runtime dependency in this work item; leave the
   current WhisperKit/FluidAudio pins unchanged.
4. Make a development-only native file probe for one local 3–10-second WAV with only
   FireRed resident. Establish v2 AED output, repeated execution, cleanup, latency
   and peak memory on a physical iPhone 17. Stop on identity uncertainty, build/API
   mismatch, memory warning, crash or unusable resource behavior. Report the blocker;
   never silently replace AED with CTC or send audio to a server.
5. Only after that passes, implement `FireRedEnglishRecognizer` using the existing
   small actor pattern: prepare and transcribe, one serial native owner, waveform
   input into sherpa's frontend, stream/result cleanup after native work completes.
   Reuse existing capture, resampler tail, VAD policy, 30-second bound and generation
   checks. Swift cancellation must not free C handles while synchronous inference
   is still executing. Add one opt-in ASR probe selection, not a provider registry,
   background service or new Mainland Talk default. Keep a verified local asset pin.
6. Build Release, check the unused/default path, and test matched Mainland Mandarin/
   English audio, both switch directions, monolingual controls, short replies, names,
   numbers, silence/noise, offline restart, interruption, End/restart during native
   work, near-30-second speech and at least 20 warm turns. Report each physical
   device and OS separately. Collect preparation/first/warm Send-to-final p50/p90,
   peak footprint, warnings and thermal state; don't call desktop numbers iPhone results.
7. Score complete results with `evaluate.py`, review English preservation with the
   user, and report any changed words or script behavior without normalizing errors
   away. Keep private transcripts/audio/full logs out of commits. A single-speaker
   run is only a smoke test. Commit reviewed native source plus a sanitized result
   fast-forward, identifying the actual tested source/model/export/runtime revisions.
   Leave product locale routing unchanged until the measured tradeoff is accepted.

Do the bounded implementation and testing now. When blocked, retain the useful
code/evidence and state exactly what remains. A hosted service is a separate privacy
and operations decision, not an authorized fallback in this task.
