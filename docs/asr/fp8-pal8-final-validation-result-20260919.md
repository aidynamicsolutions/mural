# FP8/PAL8 final validation result - 2026-09-19

## Disposition

- **Engineering safety:** PASS, qualified by the residual diagnostics and host-harness limitation below.
- **Content result:** PASS with one formatting-only F04 observation; no new critical content regression reported.
- **Human UX acceptance:** PASS by user report.
- **Selected baseline:** packed-v3 FP8 Core AI encoder + PAL8 Core ML decoder, `prewarm=always`.
- **Normal Talk default:** unchanged. No production-default promotion was made.
- **Optimization closure:** the bounded validation can close on the selected FP8/PAL8 baseline. This is not a cold-cache, long-soak, energy, p95, or perfect bilingual accuracy claim.

## Source, build, and path

The reviewed patch was applied to the current remote parent without rewriting history:

- Tested parent: `65c96f6df18b99eee3739081d064c74b2b3ba326`
- Tested `LocalConversationEngine.swift` blob: `894695b83f446e5c70d4bc157d7dad0390e36c41`
- Reviewed-task patch SHA-256: `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`
- Branch and remote before publication: `mvp`, both at `65c96f6df18b99eee3739081d064c74b2b3ba326`
- Unrelated local changes in `.agents/skills/verify-mural/` were preserved and are not part of this result.

Ordinary Release was built without ASR opt-in conditions and compiled successfully, proving the missing-probe Release regression is fixed:

- Bundle override: `com.kevintruong.mural.dev`
- Executable SHA-256: `e9e201759a6c09abac243e91b7ea8f3ee8dede9cefb38dfbbf8b0a0485a9f31c`

The selected Release was built with both existing conditions and the inherited local signing override:

- `MURAL_COREAI_TALK`
- `MURAL_COREAI_W8`
- Team: `8U5UDBW8NS`
- Bundle: `com.kevintruong.mural.dev`
- Executable SHA-256: `4a770fc857c4efa0130a12fe1053e23743425b990d0ef7f3af1c64cd5dd28c33`

The selected app was installed in place without uninstalling or clearing data, then launched with exactly:

```text
--coreai-w8-v3-encoder=fp8
--coreai-w8-v3-decoder=pal8
--coreai-w8-v3-prewarm=always
```

The phone was freshly rediscovered as Kevq, iPhone 17 (`iPhone18,3`), iOS 27.2 build `24B5084k`, arm64e. The app ran as PID 15487 in the existing `com.kevintruong.mural.dev` bundle. Normal Talk, English learning language, Vietnamese support, On-device mode, Wi-Fi off, and cellular off were confirmed.

Existing build warnings were retained and not broadened: the known iOS 27 `InterruptionType` deprecation, the existing async alternative warning, and AppIntents metadata being skipped without an AppIntents framework dependency. No new warning from the reviewed changes was observed.

## Artifact identity and ABI

Canonical Mac rehash and current phone manifest/hash checks passed:

| Item | Expected and observed |
|---|---|
| FP8 full manifest | `73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13` |
| PAL8 support manifest | `430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336` |
| FP8 AOT fingerprint | `c5c7d3264c7256fc50c37e4e4a3471ec69c278397f1887cca65b96a6ee796c65` |
| FP8 AOT native hash | `e7f2444e520608250ec7e8e11d820af9b1b19e3b813021b2e5acd700dee33485` |
| Named function | `mural_v3_encoder_fp8_packed_6ac300f97511fb8879a6` |
| PAL8 directory | `phowhisper-cs-pal8-g16-v1` |
| PAL8 decoder inventory | `edbc7ee3fa462e9f28712a07123135ee8a90ae677255befefd85302d28784af8` |
| PAL8 compiled decoder bytes | `991764466` |
| PAL8 manifest-listed support bytes | `1655763645` |

The FP8 source bundle fingerprint was `df7f666667918bbd21b874ff63c5009f970675b1d9ad5fd7336517803a1ec720` with native source hash bytes `b9754ecc845a0c5da63234a289a83a31593c618a198daf938e230cfdc450bd89`. The frozen source provenance matched the manifest control hashes, including source weights `264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a`.

The current phone copies of the FP8 manifest, PAL8 manifest, FP8 source `main.hash`, and FP8 AOT `main.hash` matched the expected file hashes and native bytes. The app also completed the full PAL8 support inventory verification on the phone before each Prepare.

The host identity and runtime contracts passed for h18p, FP16 input `[1,80,3000]`, challenge `[1,40]`, packed packet `[1,1920040]`, finite FP16 hidden states `[1,1500,1280]`, and decoder bridge `[1,1280,1,1500]`. Live logs show the exact named function being loaded by Core AI; no `main` fallback was used.

## Host checks

The applicable host checks were run in the existing pinned environment where required. Linux synthetic results are not treated as Apple results.

- `test_asr_final_review.py`: PASS, 8 tests.
- Pinned `test_w8_runtime_identity`: PASS, 8 tests, including packed/split extraction and PAL6/PAL4 contract coverage.
- `test_w8_identity.py`: PASS, 9 tests, 1 expected skip.
- `test_product_residency.py`: PASS.
- `test_talk_opt_in.py`: PASS.
- `test_cached_load.py`: PASS.
- Pinned `test_decoder_trial.py`: PASS, 32 tests, 2 skips.
- Pinned `test_combined_trial.py`: PASS, 39 tests.
- Pinned `test_pal6_experiment.py`: PASS, 30 tests.
- `test_hybrid_layout.py`: PASS.
- `test_asset_verification_memory.py`: PASS, bounded hash buffers; peak RSS 8,601,600 bytes.
- `test_probe_contract.py`: PASS.
- `swift test`: PASS, 65 tests, 0 failures.
- `git diff --check`: PASS.
- An initial unpinned runtime identity invocation failed because the default Python lacked `torch`; the existing pinned environment passed. No dependency was installed or upgraded.
- `test_mel_reader.py`: BLOCKED by its existing extraction harness, which emits a helper referencing `PhoWhisperStagedEncoder` out of scope. The reviewed patch did not touch this test or its source contract, so no unrelated cleanup was made. This remains a host-harness limitation, not an observed phone failure.

## Live Prepare and runtime proof

The fresh Mural-only capture recorded, in the selected process:

- `asset-verification-end model=phowhisper-cs-pal8-g16-v1`
- `asr_staged_prepared ... selection=fp8 decoder_support=phowhisper-cs-pal8-g16-v1`
- `decoder_prewarm=with-greeting`
- `asr_ready model=PhoWhisper CS`
- `asr_staged_decoder_speculative_complete`
- `CoreAIRuntime Loading function 'mural_v3_encoder_fp8_packed_6ac300f97511fb8879a6'`

Four targeted live attempts were correlated by their actual UUIDs and monotonic uptime values:

- Three completed turns had capture, send, final, and first tutor-audio events.
- One F12 cancellation had capture and send only, then drained without finalization or tutor audio. It remained in the ledger and was excluded from successful latency summaries.
- No `asr_trial_failure` or `asr_turn_failed` event occurred.

### Latency

Scope is app monotonic time, correlated by capture ID. Browser/form time and speech onset were not inferred. No p95 is claimed.

| Scope | Valid count | First completed turn | Warm median | Warm range |
|---|---:|---:|---:|---:|
| Send-to-final | 3 | 3.216643 s | 2.944964 s | 2.775736-3.114192 s |
| Send-to-first-tutor-audio | 3 | 7.456842 s | 6.382744 s | 6.195949-6.569538 s |

The warm set contains the two completed turns after the first completed turn. The canceled F12 attempt is not included. The first tutor-audio IDs matched the same completed replies, not the greeting.

### Separate phase scopes

The logs keep these intervals separate. The encoder function-load duration was not separately timed; the named function load event was observed. Values below are not summed into app latency:

- First completed turn: native encoder `0.521027 s`; validation/copy `0.011463 s`; decoder prewarm `0.466127 s`; decoder load `0.093585 s`; replay decoder prediction `0.751388 s`; replay decoder loop `0.795471 s`; replay decode `0.802653 s`; staged harness interval `3.197887 s`.
- Warm completed turns: native encoder median `0.508087 s`, range `0.506789-0.509384 s`; validation/copy median `0.011608 s`, range `0.010978-0.012237 s`; decoder prewarm median `0.361769 s`, range `0.215158-0.508380 s`; decoder load median `0.090792 s`, range `0.090527-0.091056 s`; replay prediction median `0.747374 s`, range `0.739463-0.755285 s`; replay loop median `0.778363 s`, range `0.770696-0.786029 s`; replay decode median `0.785151 s`, range `0.776967-0.793335 s`; staged harness median `2.930930 s`, range `2.762586-3.099273 s`.
- The replay decoder interval is explicitly labeled `replay-transcription-not-native-decoder`.
- The staged harness interval is explicitly labeled `staged-transcribe-through-unload-not-ui-send`.
- Phase footprint samples are not process-lifetime RSS, continuous peak, or model-only RAM.

## Block results and safety coverage

The complete user block had 14 attempted items: 13 completed, 0 content failures, and 1 intentional interruption at F12. No retry was used. The original human ledger reported F01-F03, F05-F10, F11, F13, and F14 preserved; F04 was formatting-only with meaning preserved; F12 canceled cleanly. The targeted captured run independently reported successful F01, F13, and F14 replies, clean F12 cancellation, fresh-conversation isolation, clean background/resume, and normal owner/native drain.

- F12: `local_ended` occurred after the turn had entered native FP8 encoder work; no final or tutor-audio event followed, and `asr_staged_turn_drained` was observed. This supports the requested cancellation boundary without claiming more native interruption than the timestamps prove.
- F14: the fresh conversation was ended and prepared again. The log contains the background/foreground transition followed by a new Prepare and a clean F14 capture/final/audio sequence. No stale or duplicate turn was reported.
- Memory warning events: none.
- Native abort/failure events: none.
- Unsafe overlap, stale/cross-session turn, and failure to drain: none observed.
- Thermal state in live memory records: `0`; the user reported comfortable warmth.
- Non-gating framework diagnostics were present: AudioQueue underflow messages injected silence, zero-byte AVAudioBuffer messages, and repeated `AXCoreUtilities` structural-concurrency faults. No ASR abort, memory warning, stuck owner, or user-visible late tutor audio was observed. These remain residual risks and were not silently removed or relabeled.

## Human acceptance and residual risks

The user reported Prepare, the first turn, and later replies felt reasonably responsive; waiting did not worsen across turns; warmth was comfortable; and no remaining known limitation was identified. The subjective first-turn estimate was about eight seconds. Objective values above are the authoritative measured intervals for this block.

Known limitations and non-claims:

- The sample is a bounded four-turn diagnostic run plus the completed user block, not a stable p95 or long soak.
- No cold-cache risk, energy result, sustained-thermal comparison, perfect bilingual accuracy, or production-default deployment claim is made.
- The existing `test_mel_reader.py` extraction harness remains blocked.
- Framework audio/concurrency diagnostics need separate follow-up if they recur in ordinary use.
- PAL4, PAL6, mixed precision, conversion, model-family, prewarm-policy, and silence/VAD work remain out of scope.

Raw audio, full device logs, screenshots, stores, and private content remain only in the ignored evidence directory:

`.build/verification/fp8-pal8-final-20260919-102715-4779`

The owned Mural-only capture was stopped after the block and no `idevicesyslog` process remains. This result contains sanitized measurements only.
