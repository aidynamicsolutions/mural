# Hybrid encoder cache-invalidation checkpoint

Date: September 16, 2026.
Status: **Cache miss/re-specialization and first hybrid transcript succeeded. Second turn incomplete after memory warning and process disappearance. Stopped for review.**

## Authorization and scope

The user approved cache isolation/invalidation after the [fresh-path experiment](hybrid-fresh-encoder-checkpoint.md)
showed that restaging the original AOT did not produce a cache miss. The documented
`AIModelCache` surface offers the app-default cache and an app-group cache, not an
arbitrary directory initializer. No app group, new entitlement or signing change
was introduced. Instead, this experiment used the documented, narrowly scoped
`deleteEntry(for:options:)` for **only the encoder + `.default` options**.

The prior encoder cache artifact was copied to Mac evidence before deletion:
8 files, 1,276,881,685 bytes, with per-file SHA-256 hashes retained. This is a
forensic artifact backup, not a claim that copying it back would restore the
SDK's cache index. Original source/AOT assets and all learning data remain.

## What happened

Run: `F0A5FAB7-48DA-41B6-B64D-112A29C6BB29`, PID 42612.

1. Verified the staged original h18p encoder, accepted support files and frozen
   fixture 001 using the same pinned hashes as the prior checkpoint.
2. Observed an encoder cache hit. Released the temporary model reference.
3. Called `deleteEntry(for: encoderURL, options: .default)` exactly once.
4. Observed a cache miss, then specialized and loaded the encoder successfully.
5. Loaded the existing WhisperKit frontend/decoder/tokenizer with unchanged
   compute and decoding settings.
6. Completed fixture 001 with the exact baseline text, language and tokens.
7. Began the repeated turn. Mural disappeared before a second encoder-before
   event. The scoped log records a memory warning during the first turn, but no
   corresponding Mural crash or Jetsam report was available in two subsequent
   inventory checks. No unchanged retry was made.

The earlier encoder function-load failure is resolved **for this run** by
invalidation/re-specialization. Its underlying cache failure cause remains
unidentified; this does not justify routine production cache deletion.

The second-turn failure is **not proven to be SIGABRT or Jetsam**. Memory pressure
is a supported lead, not a definitive termination diagnosis. The first turn's
results were flushed before the process disappeared. The top-level report still
says the proof is running; `run/whisperkit-proof.json`, first-turn captures and
`events.jsonl` establish partial success, not overall completion.

## First-fixture comparison

Both baseline and hybrid consumed byte-identical actual mel tensors:

```text
45989a5ad4d363d2afd85d91170bbbac97fffbb45d92ca4af6c5bad632588049
```

Both returned `Yesterday I went to the supermarket.`, language `vi`, with exactly:

```text
[50258,50278,50359,50363,56,4690,286,1437,220,1353,220,3322,25180,13,50257]
```

Canonical encoder tensors contain 1,920,000 finite FP16 values. Float32-widened
comparison against the current phone Core ML baseline:

| Metric | Value |
| --- | ---: |
| Maximum absolute difference | 0.6015625 |
| Mean absolute difference | 0.0032055893 |
| RMSE (Float64 accumulation) | 0.0053676719 |
| Exactly equal elements | 4.923177% |
| Core ML range | -10.734375 to 28.9375 |
| Core AI range | -10.7265625 to 28.9375 |

No encoder numerical tolerance was selected after seeing these values. These are
measured differences, **not bit-exact encoder parity** or a corpus-quality pass.
The prior decoder-logit diagnostic tolerance does not apply to encoder tensors.

The Core AI encoder output SHA-256 is
`cdf3c3f5300103ad2b0a23e414b070041d21e7f7c0f77f18ce32bc52824957ae`,
identical to the earlier successful Core AI encoder checkpoint. This is useful
reproducibility evidence independent of its differences from Core ML.

## Timing and memory

| Stage | Seconds |
| --- | ---: |
| Verification | 2.667 |
| Core AI encoder specialization, verified miss | 22.032 |
| Core AI function load | 0.048 |
| Tokenizer/config | 0.257 |
| WhisperKit decoder prewarm | 57.096 |
| Total prewarm | 57.177 |
| Subsequent model load | 0.109 |
| Total instrumented preparation | **82.528** |
| First complete transcript | **4.353** |
| Second transcript | **Unavailable** |

Core ML cache state was not independently observed or explicitly reset. Its
prewarm timing is a model-load-call duration, not separately traced compilation.
The earlier all-Core-ML baseline took 226.944 s to prepare and 1.868 s for its first
transcript. These single samples have different cache histories and are not a
controlled speedup distribution. This hybrid run does **not** meet 15-second
readiness, and preparation alone does not include its deferred first inference.

Sampled footprint rose from about 1.967 GB after model loading to 3.502 GB after
encoder inference, then 3.526 GB after the first transcript / before turn two.
The scoped log records `Received memory warning.` between encoder completion and
first-transcript completion. Recorded process-lifetime RSS peak was 2,022,522,880
bytes; it is a separate OS metric, not a continuous device/driver-memory peak.
Recorded thermal state was nominal throughout.

## Implementation and validation

`App/MuralApp.swift` adds explicit `--coreai-hybrid-invalidate-encoder`, valid only
with `--coreai-whisperkit=hybrid --coreai-fixture=001.wav` and
`--coreai-hybrid-fresh-encoder`. It verifies the original source digest before
invalidation, requires the expected cache hit, records before/after state, and
allows at most one invalidation attempt per process. It never calls
`deleteEntries(for:)` or `deleteAll()`. Normal Talk is unchanged.

The same SDK encoder cache directory was repopulated after specialization:

```text
coreai-cache/24A435/com.kevintruong.mural.dev/
  e10a76a007043a451767ff2a9950cd23451c7ed144e0549c5796cdbf10aa1251/
    3EED337528B9C2FCA4B6816CDCDED1FEC0A9E9EBA265A286147FA655E86F35B1/
```

The cache-root inventory changed only that directory's modification timestamp;
other listed entries remained. No other cache was explicitly invalidated.
Ordinary runtime preparation may manage its own derived caches.

- Release build/install passed; only the existing missing-AppIntents warning.
- Actual Swift argument/layout checks passed, including rejection of invalidation
  without fresh mode and duplicate/malformed invalidation flags.
- Evidence assertions verified one deletion, hit-to-miss transition, successful
  function load, one completed transcript, identical actual mel/text/language/
  tokens, finite encoder tensors, and absence of overall completion.
- Whitespace checks passed. Incoming work preserved; no Core AI decoder run,
  precision/model/backend change, dependency install, cloud request, full corpus,
  toolchain update, commit, subagent or publication.
- Owned Mural-only capture exited. No Mural process remains. No termination signal
  was sent to the vanished process. No broad device log archive was collected.

Device: Kevq, iPhone 17 / iPhone18,3, UDID `00008150-000D25942278401C`, iOS 27.0
`24A435`, Core AI `h18p`. Xcode 27.0 `27A5252f`. Installed in place as
`com.kevintruong.mural.dev`.

Executable SHA-256:
`fe918c08a8624293773c9bb4d7e2706d26854b5f00063947f59d4dba7f907e48`.

Evidence: `.build/verification/coreai-hybrid-invalidation/`, especially
`encoder-cache-backup/`, `backup-files.json`, `run/`, `comparison.json`,
`runtime.log`, cache/crash/Jetsam inventories, build/install and cleanup records.

## Next review gate

The useful next investigation is **second-turn memory/lifetime and termination**,
not another cache reset. Preserve the newly working specialization and the old
backup. Do not rerun the invalidation launch unchanged, broaden to the corpus or
integrate into Talk. First-transcript success is real progress, but repeat-turn
stability, full quality, usable startup, coexistence and lifecycle acceptance
remain unproven.

## API sources

- [AIModelCache](https://developer.apple.com/documentation/coreai/aimodelcache)
- [deleteEntry(for:options:)](https://developer.apple.com/documentation/coreai/aimodelcache/deleteentry(for:options:))
  specifies exact model/options deletion and rejects entries still referenced by
  a live `AIModel`. The probe releases the lookup model before deletion.
