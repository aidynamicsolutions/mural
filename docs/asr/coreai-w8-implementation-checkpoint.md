# W8 encoder implementation checkpoint: stopped on cache aliasing

2026-09-17. Base: `ed673ec40d629d32214f3a7e8cd59ea926235aa1`, clean `mvp` before implementation. Fast-forward-only fetch/merge reported already current. This is a partial implementation/qualification result, not a BOTH-component acceptance or default promotion.

## Blocking result

`coreai-build 3600.83.1` produced different FP8/INT8 source assets and different AOT weight resources, but **identical AOT `main.hash`**:

`14b1d7cc210fb36aee5c885ff13c8256e0daa8e9c9e66d3e75d4f6fee7de0f8f`

After INT8 populated the fresh-install cache, requesting the verified FP8 AOT bundle returned a cache hit under that shared key. Its output SHA-256 exactly matched INT8, not the earlier actual FP8 output. A valid outer bundle fingerprint therefore did not establish the identity of the cached weights. This was discovered during numerical comparison, before decoder/corpus qualification.

Stopped all model progression. Final code rejects FP8, INT8 and their PAL8 combinations **before model loading**. The final installed Release was exercised with the FP8 flag and returned the explicit cache-identity blocker, with no model-loading events or memory warnings. No cache deletion, hash patch, runtime-internal patch, source substitution or automatic fallback was used.

Apple's documented `AIModel(contentsOf:options:)` also uses the default cache; it is not an uncached workaround. `AIModelCache` publicly documents only default and app-group caches, not an arbitrary per-candidate directory. No signing/app-group change was attempted. Next single investigation: obtain independently keyed AOT artifacts through a supported compiler/export correction and reproduce identity isolation before resuming decoder tests. A new compiler requires the uncompressed same-toolchain control. Do not simply remove the guard or retry these artifacts.

## Implementation

- `Tools/CoreAI/compress_phowhisper_encoder.py`: separate direct `AIModelAsset.load` / `quantize_weights` route; frozen source fingerprint and FP16 contracts; exclusive output directory; no source overwrite; original metadata/lineage; per-constant coverage and exported compression-op audit; saved-asset reinspection.
- `Tools/CoreAI/compression-requirements.lock.txt`: isolated environment pins. Original exporter and its environment were not changed.
- `Tools/CoreAI/test_encoder_compression.py`: executable tiny FP8/INT8 graph check, saved ops/coverage, source immutability, fingerprint mutation and symlink rejection.
- `App/MuralApp.swift`: explicit `MURAL_COREAI_W8` Release probe gate; one-fixture encoder-only run, owned FP16/mel dumps inside the unique run directory, load-component timings. Existing owner/drain path retained.
- `App/LocalConversationEngine.swift`: closed build-gated encoder/decoder selection and final compressed-candidate stop guard. Support manifest and encoder fingerprint selected together. Greeting prewarm and Send load both use the same prepared support directory. Normal Release remains unchanged. Original/PAL8 selection is implemented but **not phone-qualified**.
- `Tools/CoreAI/test_product_residency.py`: compiles actual selection/guard code, including rejection of blocked candidates, invalid combinations and duplicates.

No new model, adapter training, frontend, tokenizer, suppression, language policy, greedy decoding, replay-mel check or native cancellation behavior was introduced. The corpus reference files remain unchanged. No tutor repair was performed.

## Recovered assets and installed APIs

Verified locally: frozen merged safetensors; source encoder `fd6ea079...`; accepted GPU AOT `f783c9b5...`; full original support manifest `7b0bff26...`; full PAL8 manifest `430c6b54...`; all 22 WAV hashes against the existing app's frozen list. Human-reference CSVs and saved PAL8 reports were recovered and fingerprinted. Keep 001-016 and 018-022 scored; 017 remains diagnostic.

Installed isolated environment: Python 3.11.11, `coreai-core 1.0.0b2`, `coreai-torch 0.4.1`, `coreai-opt 0.2.1`, Torch 2.11.0, NumPy 2.3.5, ml-dtypes 0.6.0. Actual signature was inspected. `QScheme` must be imported from `coreai_opt.coreai_utils.common`, not the package root. Tiny graph checks passed before loading the full encoder. Compiler unchanged, so no new-toolchain control was required.

Host: macOS 26.6.2, Xcode 27.0 (27A5252f). Phone: iPhone 17 / iPhone18,3 / h18p, **iOS 27.2 (24B5084k)**, not the historical iOS 27.0 phone checkpoint. No native Mac model inference or host simulation is claimed. Graph verification/export and phone inference are distinct evidence.

Import-time warnings: coremltools does not support the installed scikit-learn conversion version and has not tested Torch 2.11.0; Torch also emits Mac distributed-redirect and TreeSpec deprecation notices. No per-weight quantization skip warning occurred. AOT commands exited zero with no warning in their saved logs. Release build retains the no-AppIntents metadata warning.

## Compression and manifests

Both formats: symmetric, per-channel, threshold 1024, source-precision scales, no activation quantization, original FP16 `[1,80,3000]` -> `[1,1500,1280]`. Original auxiliary FP32 graph operations remain; this is not a claim that every working scalar is FP16.

| Measure | FP8 E4M3FN | INT8 |
|---|---:|---:|
| Eligible/compressed constant tensors | 194 / 194 | 194 / 194 |
| Compressed elements | 634,368,000 | 634,368,000 |
| Source-precision bytes represented | 1,268,736,000 | 1,268,736,000 |
| Eligible tensors left uncompressed | 0 | 0 |
| Other uncompressed floating constants | 299 | 299 |
| Other floating elements / source bytes | 2,416,646 / 4,833,294 | same |
| Saved `blockwise_shift_scale` operations | 194 | 194 |
| Export bytes | 640,120,936 | 640,126,161 |
| AOT bundle bytes | 640,470,615 | 1,273,955,343 |

Other constants include small parameters and graph constants; calling every one a skipped learned weight would be inaccurate. INT8 AOT storage expansion is observed, not proof of a specific device arithmetic mode. Neither file size nor op labels establish runtime memory savings or acceleration.

Portable manifests: [`coreai-w8-candidates.json`](coreai-w8-candidates.json). Full manifests and per-constant audits remain under `.build/coreai/w8-{fp8,int8}-pc-v1/`; combined evidence manifest is `.build/verification/coreai-w8-20260917/candidate-manifests.json`.

## Physical measurements: encoder-only, one sample each

| Attributed run | Load interval, s | Run interval, s | Highest event footprint, bytes | Lifetime RSS peak, bytes |
|---|---:|---:|---:|---:|
| FP8 before user uninstall | 1.430 | 2.175 | 421,972,432 | 1,359,790,080 |
| INT8 fresh install | 3.014 | 3.322 | 222,972,848 | 2,595,438,592 |
| Original fresh install | 2.665 | 1.467 | 223,972,248 | 2,601,402,368 |
| FP8 request returning INT8 cache, **invalid FP8 attribution** | 2.295 | 0.471 | 223,579,032 | 2,602,123,264 |

Load interval is logged load-begin to load-complete, including cache/specialization/function load as applicable. Run interval includes native inference, owned output validation/copy, tensor file writes and event overhead, **not pure kernel time**. Physical footprint is an event sample, not a periodic sampler or peak. RSS is process-lifetime maximum, not model-only physical footprint or system/driver memory. No energy measurement. All runs recorded nominal thermal state (0), zero memory warnings and 1,920,000 finite output values. No sustained-thermal conclusion.

One sample per attributed configuration, different cache/install state, no matched warm distribution: no speed/RAM benefit is established; no meaningful p95. The pre-uninstall FP8 sample must not be treated as a matched post-install comparison. All samples and release intervals are in `probe-comparison.json`.

Same exact accepted mel bytes versus the new original-encoder output:

| Actual encoder | Max absolute error | Mean absolute error | Cosine |
|---|---:|---:|---:|
| FP8, pre-uninstall | 17.083008 | 0.017781 | 0.998791 |
| INT8, fresh install | 1.914063 | 0.007813 | 0.999891 |

Finite values/cosine do not pass bilingual quality. The first draft numerical comparison inadvertently compared INT8 with its aliased cache hit; it is explicitly marked superseded in local evidence. No identical-prefix logits, decoder transcripts or quality acceptance was obtained.

## Human feedback, storage interruption and cleanup

Human confirmed via interview: phone ready/unlocked; first FP8 completed without issue; later INT8 completed without issue. Agent-observed reports independently show those encoder-only completions. Human feedback does not establish ASR accuracy.

INT8 transfer initially failed with socket-closed errors. A wired check did not resolve it. The user then reported an out-of-space alert and approximately 57 GB Mural storage, **deleted the app themselves**, and explicitly requested reinstall/start fresh. The agent did not initiate that deletion. Previous local history/settings/caches cannot be claimed preserved after that user action. No history recovery was attempted.

Reinstalled `com.kevintruong.mural.dev`; measured available data storage 197,128,220,672 bytes before restoring verified trial assets. Restored only required FP16/PAL8 support, three AOT encoders and the frozen corpus, not the historical failed model zoo. Transfers then succeeded. New cache creation was labeled fresh-install. Final available-data reading: 196,794,982,400 bytes (OS-reported metric, not app size).

The initial Release launch did not enter the Debug-only probe; stale reports were rejected, no inference credited. The explicit Release probe flag corrected that. One original-probe collection was interrupted by the user; no result was credited. Process inspection confirmed no surviving owned capture. Every subsequent capture ended in `finally`; the final blocked-candidate check also stopped its capture. No ongoing Mural log collection, device-wide archive, cache deletion, latch clearing, cloud fallback or deliberate memory exhaustion.

## Gates and remaining work

Passed: FP8/INT8 offline checks and h18p GPU-preferred AOT; attributed encoder-only finite outputs; 65 core tests; product-residency/selection, Talk opt-in, hybrid layout, cached-load checks; trial and default Release builds; final safety-guard Release install and phone rejection before loading. Original exporter diff is empty.

**Blocked/not run:** C-F/C-I with FP16 decoder; original-encoder/PAL8 control; combined D; corpus WER/CER and new transcript differences; full Send-to-final, token-loop/first-token comparisons; greeting-versus-Send decoder identity in live logs; mixed-language first/warm turns, quiet Yes/No, short Vietnamese, number/negation, silence, End/drain/new-turn and focused offline checks. No claim of completion for these gates. Implemented selection is not evidence of those behaviors.

Known historical PAL8 differences remain visible and accepted only for this trial:

- 006: `Em không biết từ này.` -> `Em complete từ này.`
- 007: `seal tea` -> `seoul tea`; both wrong for `siêu thị`.

No new transcript differences can be reported because decoder qualification did not run. No references were changed. Return for review before a cache-identity workaround, further optimization or production-default change.

Local evidence root: `.build/verification/coreai-w8-20260917/`. It includes exact build/AOT/transfer/launch commands, hashes, source/API inspection, import warnings, raw reports/events/tensors, comparison data, disk readings and stopped-capture records. Private device logs remain uncommitted.
