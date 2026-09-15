# Sequential Core AI loading checkpoint

## Outcome: FAIL / transcription still blocked

Implemented sequential model lifetimes with the existing exact FP16 split AOT assets, then tested both in-process sequencing and a fresh decoder-only process. Both reached language detection, then aborted in Apple MPSGraph's ANE inference path before completing the first transcript. The second test rules out encoder/decoder co-residency as the sole cause. No KV cache, new exports, compression, precision, tokenizer or decoding changes in this follow-up. No 22/22 parity claim.

## Identity and changes

- HEAD remains `865c3744a39954db0a165b2f7d85561e1a2f7800`, branch `mvp`; existing uncommitted mel reader/exporter fixes preserved.
- New changes in `App/MuralApp.swift`: load models only within separate encoder/decoder scopes; copy encoder output into owned `[Float16]`; assert finite output and exact FP16 bits at decoder handoff; log memory boundaries using the existing helper; record model-load timings per result rather than frontend preparation; single-fixture selection and optional separate-process checkpoint modes.
- `Tools/CoreAI/README.md` documents the new diagnostics and timing semantics.
- Release builds succeeded; one temporary mutable-view compile error corrected. `git diff --check` and `python3 Tools/CoreAI/test_mel_reader.py` passed.
- Installed in place with `com.kevintruong.mural.dev`; phone rediscovered as iPhone 17/iPhone18,3, iOS 27.0/24A435, architecture h18p.
- Same original matching encoder/decoder AOT pair restored in the preceding checkpoint, no changes to it this run. Frozen model weights remain those previously SHA-verified as `264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a`.
- No uninstall, user learning data changes, Core ML support-asset deletion or conversation integration.

## 1. Sequential loading in one process

Command arguments: `--coreai-asr-probe --coreai-asr-auto --coreai-fixture=001.wav`.

PID 40396. The first frozen fixture only was selected, as agreed before the full corpus.

| Boundary | Physical footprint bytes | Process-lifetime RSS peak bytes | Thermal state |
|---|---:|---:|---:|
| Before encoder | 56,805,240 | 120,733,696 | 0 |
| Encoder loaded | 1,339,049,848 | 125,517,824 | 0 |
| Encoder output copied | 1,531,660,176 | 125,845,504 | 0 |
| Encoder Swift scope ended | 1,531,643,768 | 125,845,504 | 0 |
| Decoder loaded | 66,489,576 | 3,285,663,744 | 0 |

- Mel: 0.007603 s.
- Encoder execution plus owned copy: 0.662868 s.
- Language detection: 10.689065 s, token 50278.
- Later ANE request failed status `0xe00002bc` / `0x12`; SIGABRT at about 23:43:36.
- Memory was not released immediately at the Swift scope boundary. The later footprint dropped, but this is not proof that all driver/cache resources were gone.
- Evidence: `runtime.txt`, `Mural-sequential-crash.json`, preparation-only `coreai-asr-probe.json`.

## 2. Encode-only checkpoint, then fresh decoder-only process

Encode-only command: `--coreai-asr-probe --coreai-asr-auto --coreai-fixture=001.wav --coreai-encode-only`.

- Encoder process PID 40451 completed and was explicitly terminated before decoding.
- Fixture sample count: 90,560 (5.66 s at 16 kHz).
- Saved encoder data: exactly 3,840,000 bytes, 1,920,000 FP16 numbers.
- Retrieved checkpoint checked with Python struct: all finite, range -10.7265625 to 28.9375.
- SHA256: `cdf3c3f5300103ad2b0a23e414b070041d21e7f7c0f77f18ce32bc52824957ae`.
- Encoder cache hit; lookup 0.001537 s; specialization 0 s; loadFunction 1.381556 s; encoder execution/copy 0.696819 s; mel 0.004582 s.
- Raw checkpoint retained locally; sanitized metadata in `encoder-checkpoint.json`; `encode-only.json` explicitly marks encode-only mode and is NOT a transcript result.

Decode-only command: `--coreai-asr-probe --coreai-asr-auto --coreai-fixture=001.wav --coreai-decode-only`.

- Fresh PID 40455 never loads or runs the Core AI encoder.
- Checkpoint length, filename, sample count, finite values validated; constructed decoder input checked against all original FP16 bit patterns.
- Physical footprint before decoder: 74,024,776 bytes; process RSS peak 116,588,544 bytes; thermal state 0.
- After decoder load: physical footprint 55,692,520 bytes; process RSS peak 3,246,505,984 bytes; thermal state 0. RSS peak and physical footprint are different metrics, not contradictory current-allocation totals.
- Language detection completed in 12.878480 s, token 50278.
- Subsequent ANE request failed with `0xe00002bc`, Core ML/ANE status `0x12`, then SIGABRT at about 23:48:19.
- Crash stack: `MTLReportFailure` -> `GPU::ANERegionCallOpHandler::encodeAsynchronousWithIOFences` on the ANE path.
- Evidence: `runtime-decode-only.txt`, `Mural-decoder-only-crash.json`, fresh preparation-only `decode-only.json`.

## Gate and evidence limits

- Normalized transcript matches established: 0 / 22; no fixture completed. Full corpus intentionally NOT started after the first-fixture failures.
- Exact transcript mismatches: not evaluable; no completed text.
- Decoder language token is recorded, not independently validated against the baseline token.
- Encoder outputs finite and FP16 handoff bit-exact; no claim that all decoder logits were finite or numerically matched baseline.
- Two correlated SIGABRT crashes; no new Jetsam entry observed in before/final snapshots. Both sanitized crash extracts included; raw IPS files retained locally.
- Thermal samples nominal (0); physical heat not assessed. No peak-system-memory measurement or hardware placement claim beyond the failing ANE runtime path in logs.
- Mel, encoder and language timings above are available for English fixture 001.wav only. Decoder/total/transcript/token-count timings and other representatives unavailable.
- Owned log captures stopped. No repeated full-corpus launches or model optimizations attempted.

## Conclusion

Sequential loading is implemented, but is not sufficient. The isolated decoder fails even without an encoder loaded in that process. Further work should focus specifically on the full-prefix decoder's shape specialization and ANE runtime execution (or an Apple toolchain/runtime defect), not assume loading both models was the root cause. Changing the decoder architecture, precision, KV caching, or production integration remains outside this completed experiment.

## Publication copy

This report and its adjacent evidence are prepared for Git. Crash JSON files are sanitized extracts, runtime text files contain only selected relevant lines, and app-container identifiers in probe JSON are replaced by `<APP_DATA_CONTAINER>`. Original evidence remains under ignored `.build/verification/coreai-sequential/`. No audio, encoder tensor, full device inventory or raw device log is included.
