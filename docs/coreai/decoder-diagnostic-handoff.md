# Continue Core AI decoder diagnosis

## Continuation completed: stop at review

Checkpoint 1 is now complete with execution blocked. Read
[decoder-diagnostic-checkpoint.md](decoder-diagnostic-checkpoint.md) for the
completed matrix, artifact identity resolution, numerical comparisons and minimal
reproducer. Dynamic and fixed length 4 both abort; CPU-only traps. No complete
transcript, KV-cache work or production integration. All original app changes and
the probe-contract test were preserved byte-for-byte. No inference or owned log
capture remains running. **Do not repeat the historical next actions below.**

The remainder is the preserved incoming handoff, recording the state before
this continuation. Its in-progress labels and next-action list are historical.

## User request and authorization

The user wants Mural's accepted offline Vietnamese-English ASR to start in roughly 12-15 seconds rather than 160-215 seconds, preserving its existing transcriptions. They approved the plan in `docs/coreai/startup-plan.md` with "ok implement your plan". I explicitly scoped this implementation to **checkpoint 1: bounded decoder diagnosis**, keeping normal Talk on WhisperKit. The user then requested this handoff to restart the session. Continue from here, not from the original loading spike.

Keep the later plan gates: no automatic production integration, no KV-cache work until the diagnostic/parity checkpoint is reviewed. If full-prefix inference stays blocked, return with evidence before proceeding directly to a fixed-step candidate. Do not re-ask permission for the already-approved checkpoint-1 build/install/diagnostic runs.

## Required context and constraints

Read:

1. This handoff.
2. `docs/coreai/startup-plan.md`.
3. `Tools/CoreAI/README.md` and `coreai_asr_handoff.md` (these predate the new diagnostic flags).
4. `docs/coreai/sequential-loading-checkpoint/report.md` and its README.
5. `.agents/skills/verify-mural/SKILL.md`, `features/local-conversation.md`, and the applicable global instructions.

Important:

- No subagents. Direct engineering/device diagnosis; the user performs live microphone/listening checks.
- Preserve weights, FP16, 80-mel frontend, PhoWhisper tokenizer, suppression/decoding contract, installed identity and learning data.
- No quantization, new model, remerge, VAD/silence changes, transcript replacement, cloud calls, OS/toolchain updates, or external publication.
- Do not repeat unchanged crashing configurations. One bounded run per diagnostic variant; stop at its first failure.
- SIGABRT cannot be caught as a Swift error. Task cancellation does not promise to interrupt a driver call.
- Do not uninstall, erase data, clear Core ML caches, delete historical artifacts, or commit without a request.

## Repository state

Root: `/Users/tiger/Dev/ios/mural`
Branch: `mvp`
HEAD: `cedc4a6dc918bb561e763edfd10d66e7c3835165`

Uncommitted work to preserve:

- Modified `App/MuralApp.swift`.
- Modified `App/VietnameseEnglishRecognizer.swift`.
- New `Tools/CoreAI/test_probe_contract.py`.
- New `docs/coreai/startup-plan.md` from the preceding review.
- New this handoff.

No commit was made. Do not reset or overwrite this work. The latest source diff is also saved at `.build/verification/coreai-decoder-diagnostic/implementation.diff`.

## What is implemented

The Core AI development probe in `App/MuralApp.swift` now has:

- Unique run directories: `Documents/CoreAI/PhoWhisper/Runs/<UUID>/` with `report.json` and flushed `events.jsonl`.
- `Documents/coreai-asr-probe.json` remains a compatibility/latest pointer, not the historical evidence store.
- Before/after decoder-call events with exact input tokens, prefix length, monotonic uptime, elapsed inference time, output shape/type, finite validation, memory, thermal state, top-5 logits, and winner margin.
- Last-row FP32 diagnostic dumps (`step-0001.logits.f32`, etc.). All raw output rows are checked for finiteness before accepting the last row.
- Three bounded teacher-forced cases: `--coreai-decoder-case=one-one`, `four`, `one-four`. They require `--coreai-decode-only` and a single explicit fixture. Prefixes are `[50258]` and `[50258,50278,50359,50363]`. These are diagnostic inputs, not forced-language production transcription.
- `--coreai-decoder-cpu-only`: only allowed with a bounded decoder case, and requires a source `.aimodel`, not the default-compute `.aimodelc`. If no explicit decoder path is provided, it looks for `phowhisper-cs-fp16-v1.decoder.aimodel` in the existing split asset directory. **Not staged/run yet.**
- New checkpoint directory `Documents/CoreAI/PhoWhisper/EncoderCheckpoints-v2/`. Metadata binds the fixture bytes, encoder/support asset fingerprints, sample count and encoder-tensor SHA-256. Legacy checkpoints remain untouched.
- Probe suppression now mirrors pinned WhisperKit's exclusion of special-token IDs from `suppress_tokens`.
- Probe token stopping now uses `Constants.maxTokenContext - 1`, with explicit `endToken` versus `tokenLimit` result metadata. This change needs full corpus verification later; no parity claim yet.
- A finite-input argmax helper, including rejection of NaNs/infinities even in suppressed/non-selected positions.
- The corpus stops on the first thrown fixture failure, instead of continuing. Diagnostic/checkpoint completion is explicitly NOT labeled a transcript.

`VietnameseEnglishRecognizer.logMemory` now returns its existing footprint/RSS measurements as a dictionary, with `@discardableResult`, so the probe can persist them. Existing logging and callers remain unchanged. No production ASR selection or conversation logic was changed.

### Important issue fixed during implementation

The first new encode-only launch stopped after `prepare-before`, before any Core AI inference. No matching new Mural crash/Jetsam report was found at that inspection; do not claim a proven phone termination cause.

A narrow Mac reproduction of the new Foundation file-hashing helper showed large transient memory while scanning the 1.27 GB encoder. Added a per-chunk `autoreleasepool` to bound Foundation buffers. Mac helper maximum RSS dropped from about 834 MB to 202 MB (these figures include Swift execution/tool overhead). The rebuilt phone probe then completed asset verification in about 3.6-4 seconds, with roughly 21 MB footprint at verification boundaries. The fresh encode-only run succeeded.

Old failed preparation evidence: `encode.json`, `encode-run/`, `hash-check.log`.
Corrected evidence: `encode-bounded.json`, `encode-bounded-run/`, `hash-check-bounded.log`.
Do not replay the initial unbounded-buffer implementation.

## Build, device, and installed state

Last discovered phone:

- Kevq, iPhone 17 / iPhone18,3.
- UDID `00008150-000D25942278401C`; rediscover rather than assume it remains connected.
- iOS 27.0 build `24A435`, Core AI architecture `h18p`.
- Xcode 27.0 `27A5252f`; SDK build `24A5422a`.
- Mac macOS 26.6.2 `25G83`. Core AI Swift runtime experiments cannot simply be run on this Mac; use the phone or a separately approved supported host.
- Installed bundle: **`com.kevintruong.mural.dev`**. Keep this override.

Release built and installed in place successfully after the buffer correction:

```sh
xcodebuild -project Mural.xcodeproj -scheme Mural -configuration Release \
  -destination 'platform=iOS,id=<rediscovered UDID>' \
  -derivedDataPath .build/local-mvp-phase-1-device-derived-data \
  PRODUCT_BUNDLE_IDENTIFIER=com.kevintruong.mural.dev build
```

App: `.build/local-mvp-phase-1-device-derived-data/Build/Products/Release-iphoneos/Mural.app`
Final deployed executable SHA-256: `f0010befefb1ba75734bfdd0c5b8aa7e21f891cb02b88d790071bf303bb29a1e`.
Evidence: `build-final.log`, `install-final.log`, `deployed-app.sha256`.

At handoff, the app was still running idle on the completed one-one diagnostic, PID 41625. No inference was left running. Do not reuse this PID without checking it.

The owned `idevicesyslog` capture PID 95633 was stopped. `capture-cleanup.txt` records cleanup; do not signal that historical PID again. No other owned persistent process was started.

Existing build warnings only: deprecated conversation interruption API and missing AppIntents metadata dependency. `git diff --check` passed.

## Completed diagnostic evidence

All fresh local evidence is under:

```text
.build/verification/coreai-decoder-diagnostic/
```

### Corrected encode-only run

Run ID: `025C7AA8-6141-4365-A18E-C196F313233A`.
Files: `encode-bounded.json`, `encode-bounded-run/`, `checkpoints/001.wav.fp16`, `checkpoints/001.wav.json`.

- Fixture: 001.wav, 90,560 samples (5.66 s).
- Fixture SHA-256: `e9789f09cf31930239ff5842a1b502103844481d4669fb7e0de77b69966b597f`.
- Encoder tensor SHA-256: `cdf3c3f5300103ad2b0a23e414b070041d21e7f7c0f77f18ce32bc52824957ae`.
- Tensor is 3,840,000 bytes, finite FP16 `[1,1500,1280]`.
- This exactly reproduces the previous session's saved encoder tensor. It is NOT a PyTorch/Core ML numerical-parity result.

### Repeated length-1 decoder case: PASS

Run ID: `95F6A3D8-E141-4363-B885-16EF2A5444AF`.
Files: `one-one.json`, `one-one-run/events.jsonl`, both raw logits files, `one-one-check.json`.
Launch:

```sh
xcrun devicectl device process launch --device "$DEVICE_UDID" --terminate-existing \
  com.kevintruong.mural.dev --coreai-asr-probe --coreai-asr-auto \
  --coreai-fixture=001.wav --coreai-decode-only --coreai-decoder-case=one-one
```

Results:

- Decoder cache hit; `loadFunction` 3.370817 s.
- First length-1 execution: **9.201957 s**.
- Second length-1 execution: **0.055945 s**.
- Both returned finite `[1,1,51865]` FP16 logits.
- Top IDs: `[50278,50259,50294,50352,50282]`.
- Top values: `[20.71875,11.828125,9.140625,8.65625,8.0859375]`.
- Winner margin: 8.890625.
- Both saved last rows are **bit-exact**, 207,460 bytes each.
- Footprint after calls approximately 1.912 GB; process-lifetime RSS peak approximately 3.488 GB. These are distinct metrics.
- Thermal samples nominal (0).

This proves repeat execution at length 1 works for this fixture. It does not prove language correctness against the reference, any length-4 call, a completed transcript, or the 12-15 second product UX.

## Frozen sources and tools

Source model:

```text
/Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/merge-fp16/model
```

Weights SHA-256 was freshly rechecked:
`264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a`.

Source Core AI decoder:
`.build/coreai/split-export/phowhisper-cs-fp16-v1.decoder.aimodel`

AOT assets:
`.build/coreai/split-aot/{encoder,decoder}/phowhisper-cs-fp16-v1.<role>.h18p.aimodelc`

Phone default assets:
`Library/Application Support/CoreAI/PhoWhisperSplit/`

Accepted support assets:
`Library/Application Support/PhoWhisperCS/phowhisper-cs-fp16-v1/`

Accepted frozen corpus and baseline:

- `.build/coreai/fixtures/`
- `.build/coreai/frozen-source-replay.json`
- `/Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/coreml-pinned-runtime.jsonl`
- Normalization in `/Users/tiger/tmp/mural-asr-benchmark/benchmark.py`: NFC, lowercase, punctuation to spaces, collapsed whitespace, accents preserved.

Reuse the existing export environment, no dependency install needed:

```text
/Users/tiger/.cache/uv/environments-v2/export-phowhisper-split-coreai-97c1d1b385bbb09a/bin/python
```

`python-environment.json` records Python 3.11.11, torch 2.11.0, transformers 4.57.3, numpy 2.4.6, safetensors 0.8.0, coreai-core 1.0.0b2, coreai-torch 0.4.1. AutoConfig attention selection was null and the model class supports SDPA; the actual resolved attention implementation after model loading still needs recording. Original accepted Python benchmark explicitly selected eager attention.

`identity.json` has local file/tree digests and toolchain metadata. Caution: its recursive tree digest was calculated with Python's JSON sorting. The Swift probe uses Foundation JSONSerialization sorted-key formatting. A Mac Swift helper produced a different encoder tree digest from the Python helper even on the same local directory. Do NOT compare those whole-tree digest implementations as if they were interchangeable. Individual file SHA-256 is standard. Use the actual Swift fingerprint helper on the Mac if comparing its tree identity to the phone.

A separate identity caveat: `device-assets.txt` shows extra `specialized_model_*.mpsgraph` files in the phone AOT directories relative to the original Mac AOT directories. They may be runtime-generated or retained from prior staging. This is not proof of altered weights or the crash cause. Before claiming exact original-AOT parity, compare immutable artifact files/manifests using the same digest method and record any extra derived files. Do not delete existing assets or caches blindly. The phone fingerprints stayed unchanged between corrected encode and one-one runs, so the v2 checkpoint identity check passed.

## Exact next actions

1. Review the current diff and this evidence, rediscover the phone, preserve the checkout. No rebuild is necessary unless code changes or installed identity differs.
2. Resolve/record the artifact-identity caveat above without resetting caches or overwriting the accepted assets. Keep comparisons honest.
3. Start one new owned Mural-only log capture if needed, recording PID and cleanup responsibility. Do not collect a broad device archive.
4. Run **`--coreai-decoder-case=four`** in a fresh app process, same fixture/checkpoint, same default AOT options. Use a bounded observation window (roughly 90-120 s); the historical ANE failure took about 64 s after language detection. Retrieve the fresh latest report, then its unique run directory. Stop at the first native error/crash; no retry of that unchanged case.
5. Run **`--coreai-decoder-case=one-four`** as the other discriminating case, also fresh and bounded. Again retain before/after events and any correlated Mural crash report. Do not run the full corpus.
6. Depending on results, stage the unchanged decoder `.aimodel` under the split directory and run the bounded CPU-only control. Use `--coreai-decoder-cpu-only --coreai-decoder-case=four` (or one-four if needed). This specializes the source for CPU, not the AOT default asset. Record CPU cost as diagnostic, not shipping performance.
7. Add/run the smallest PyTorch numerical comparison using the saved FP16 encoder tensor and the exact diagnostic prefixes. Use the frozen model, record actual attention implementation, compare finite raw last-row logits/top candidates/margins to the saved phone `.f32` outputs. No PyTorch decoder comparison has been run yet; no reference tool has been added.
8. Only if evidence implicates dynamic shapes, export bounded fixed-length 1/4 diagnostic functions and compile h18p only, with unchanged FP16 weights. This conditional export step is still part of checkpoint 1. Do not build KV cache yet.
9. Update `Tools/CoreAI/README.md` for implemented flags/report semantics, write a checkpoint result with limits, and return to the user at the diagnostic gate. The plan's later phases remain unperformed.

Retrieval pattern (read the fresh report's `runID`, do not copy a previous run by mistake):

```sh
xcrun devicectl device copy from --device "$DEVICE_UDID" \
  --domain-type appDataContainer --domain-identifier com.kevintruong.mural.dev \
  --source Documents/coreai-asr-probe.json --destination "$E/<case>.json"

xcrun devicectl device copy from --device "$DEVICE_UDID" \
  --domain-type appDataContainer --domain-identifier com.kevintruong.mural.dev \
  --source "Documents/CoreAI/PhoWhisper/Runs/<fresh runID>" \
  --destination "$E/<case>-run"
```

`devicectl device info processes --search Mural` works. Filtering `executable CONTAINS "Mural"` fails because executable is a URL, not a string collection. Do not waste time retrying it.

## Checks already passed / remaining limits

Passed:

- `python3 Tools/CoreAI/test_probe_contract.py` after the hashing correction.
- `python3 Tools/CoreAI/test_mel_reader.py` (its code was not subsequently changed).
- Release build/install, v2 encode-only checkpoint, repeated length-1 decoder execution.
- `git diff --check`.

Not performed:

- Length-4-first or 1-to-4 cases.
- CPU-only control, new exports, PyTorch decoder logits comparison.
- Any complete Core AI transcript, 22/22 parity, or production integration.
- New microphone/listening checks or first-use product timing.

The first checkpoint is IN PROGRESS, not completed. Continue the bounded investigation; do not claim that the ASR startup problem is solved.
