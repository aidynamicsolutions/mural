# Core AI staged-residency checkpoint

Status: **Fixture-001 residency milestone passed; production gate remains closed.**

## What changed

The development-only `--coreai-product-mode=staged` path separates the large working sets:

1. Verify the frozen FP16 encoder, support manifest and fixture audio.
2. Run the existing Core ML mel frontend and the Core AI encoder without a WhisperKit decoder loaded.
3. Copy `[1,1500,1280]` encoder output into owned `[Float16]` storage.
4. Return from the encoder scope, dropping its Core AI model, function and array references.
5. Load/prewarm the existing WhisperKit/Core ML frontend and decoder.
6. Transcribe the same audio through WhisperKit with a replay encoder that supplies the owned embeddings. The replay first requires an exact hash match between WhisperKit's mel and the mel used by Core AI.
7. Require exact fixture-001 text, normalization, language, tokens and audio identity. Release before the next turn; stop on a reported memory warning.

This preserves WhisperKit's orchestration, tokenizer, language detection and decoder rather than implementing a new decoder. The small mel computation is repeated deliberately to keep that orchestration intact. A delegating decoder wrapper records real language/text decoder entry and return. Cancellation qualification remains disabled for the staged mode.

This is still a bounded diagnostic, not normal Talk integration. The prototype releases WhisperKit after each turn; it does not yet retain the tokenizer between turns. All latency claims must include that cost.

## Encoder load failure and approved repair

The first loading-only experiment failed before encoder residency was established. Phase-specific diagnostics isolated the failure to `AIModel.loadFunction(named: "main")`; cache lookup succeeded. Device logs reported MPSGraph could not load the model for its cache identifier. The specialized artifact files still existed.

The user explicitly approved **one deletion of only this verified encoder's default-specialization cache entry**, followed by rebuilding it and retrying loading-only once. No other cache, model, precision, data or decoder was changed. That experiment succeeded without warnings:

- Loaded sampled footprint: 1,307,543,416 bytes.
- First post-release sample: 26,494,840 bytes at about 107 ms after teardown returned.
- Cache miss after deletion, then successful specialization/function load.

The subsequent staged runs loaded the cache successfully, including after installing the staged build. This demonstrates that rebuilding the entry restored loading; it does not establish why the previous entry failed. There is **no automatic cache-delete retry** in the load helper. The explicit repair mode is not permission for future repeated invalidation.

Evidence: `.build/verification/coreai-residency-load-diagnosis/`, including `encoder-system.log`, `cache-inventory.txt`, `rebuild-run/`, and preserved Apple cache documentation. The failed diagnosed run is `19A61F9E-05B7-4156-883F-AF5C76C28B2C`; the approved repair/loading-only run is `0FE361EA-569A-4A49-BC29-6218CA9A3DA2`.

## Physical staged results

Same iPhone 17 / iPhone18,3, Core AI h18p, recorded iOS 27.0 (24A435), Debug build, bundle `com.kevintruong.mural.dev`. Each row starts a fresh process; turns within a row are serial in that same process.

| Run | Turns | Exact fixture-001 matches | Recorded iOS warnings | Highest event-sampled footprint | Thermal samples |
|---|---:|---:|---:|---:|---|
| `728CFC44-0470-44CB-B77B-F393C958648E` | 1 | 1/1 | 0 | 2,081,294,464 bytes | nominal |
| `88D88D83-81D9-4846-A879-5CC487B7B3F2` | 2 | 2/2 | 0 | 2,072,414,288 bytes | nominal |
| `6F1BE483-1F8D-4A92-A7A5-916FFCD9DD5F` | 10 | 10/10 | 0 | 2,069,203,000 bytes | nominal |

All reports are terminal and complete. Raw text, normalized text, detected language, generated tokens, mel hashes and audio hashes were independently compared with the saved all-Core-ML fixture-001 baseline. System logs and top-level reports both showed zero warnings during collection.

### The important transition

On turn one of the single-turn run:

- Encoder output copied: 1,517,373,304 bytes.
- Encoder scope returned / references released: 1,506,822,008 bytes.
- Before decoder load/prewarm, after ordinary configuration/tokenizer work: 52,496,272 bytes.
- Actual language decoder entry: 2,062,174,264 bytes.

In the ten-turn run, footprint before decoder prewarm was **47.8-88.3 MB** on every turn. No fixed delay was inserted between encoder release and decoder loading. The drop is observed across normal work, not an allocator-retirement guarantee or a threshold-based admission policy.

Compared with the prior roughly 3.5 GB combined-residency observations, this supports overlapping working sets as a major contributor. These are event samples, not continuous process peaks or a controlled performance comparison.

## Validation

- Device Debug build succeeded with the existing AppIntents metadata warning.
- `Tools/CoreAI/test_product_residency.py` passed: actual config/parity helpers, loading-only restrictions, staged bounds and exact recovery checks.
- `Tools/CoreAI/test_hybrid_layout.py` passed.
- `Tools/CoreAI/test_probe_contract.py` passed.
- Physical one-, two-, then ten-turn staged runs passed in that order.
- `git diff --check` passed.

Evidence: `.build/verification/coreai-staged/`, with build/install logs, each run's launch/system log, pointer, terminal report, transcripts and event stream. Logs and evidence remain local/ignored. No source commit or publication was made.

## Limits and next work

This reopens the memory investigation; it does **not** pass the overall product gate:

- Thirteen successful turns all use the same short fixture. No 22-file parity, silence/Yes/No coverage or representative long-recording sequence yet.
- No staged cancellation, background/foreground, offline or tutor/TTS coexistence qualification.
- No Release performance distribution. `ProductTurn.timings` covers the later WhisperKit transcription call: its in-pipeline encoder time is zero for replay, and its total excludes the earlier staged frontend/encoder and model preparation. Use the full event timeline for staged end-to-end duration; do not interpret that field as end-to-end ASR latency.
- Reference release is distinct from runtime retirement. No claim that all internal framework work finishes synchronously with ARC release.
- The explicit cache repair restored operation but its underlying failure cause remains unresolved.
- The staged flag intentionally restricts runs to fixture 001, at most ten turns, and no cancellation. Broader qualification requires deliberate expansion and baseline comparisons, not silently relaxing these guards.

Next: extend the staged harness to frozen-corpus baseline comparisons, preserve warning-stop behavior, then qualify actual cancellation boundaries and lifecycle/coexistence. Normal Talk stays on the existing WhisperKit/Core ML backend until the full production plan passes.
