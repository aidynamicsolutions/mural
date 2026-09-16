# Hybrid fresh-path encoder checkpoint

Date: September 16, 2026.
Status: **Complete; fresh path did not establish an independent specialization. Stopped before function loading.**

The user approved the next experiment from [hybrid-checkpoint.md](hybrid-checkpoint.md):
stage a byte-verified copy of the original encoder AOT under a new path, preserve
all existing assets/caches, and resume the one-fixture hybrid proof only if the
independent encoder load succeeds.

## Result

Run `1425A1D3-EEAA-432D-9FAE-A3449B8043EA` verified the newly staged encoder against
the original Mac AOT, then `AIModelCache.default.model(for:options: .default)`
returned a non-nil cached model for the **new path**. The probe's fresh-path guard
stopped immediately:

```text
Fresh path already resolves to a cached specialization. Stop rather than retry the existing cache.
```

No `loadFunction`, specialization call, encoder inference, WhisperKit preparation
or decoding followed. No new native error or Mural crash report occurred. This is
a cache-isolation experiment result, **not a repeated encoder load failure**.

Changing the source directory alone is insufficient to obtain an independent
cache miss for this artifact on this device/toolchain. The lookup does not expose
which cache entry it returned, so the new run does not independently prove it
selected the exact same entry as the previous failure. It does not establish the
cause of that failure or whether fresh specialization would fix it.

## Assets and code

Original source, reused without export or recompilation:

```text
.build/coreai/split-aot/encoder/phowhisper-cs-fp16-v1.encoder.h18p.aimodelc
```

New phone destination, absent before staging:

```text
Library/Application Support/CoreAI/PhoWhisperHybridFresh/
  phowhisper-cs-fp16-v1.encoder.h18p.aimodelc
```

The source has 10 files totaling 1,276,875,669 bytes. Original file SHA-256 hashes
are retained in evidence. The app's actual recursive fingerprint helper was run
on the Mac source; the phone matched it **before cache lookup**:

```text
590fcca5d35ea07d31b361a7809ad239a9c985a91d945fda9887852b9b02ec67
```

This fingerprint differs from the older phone tree, which contains additional
runtime-derived files. Neither tree was modified or replaced by staging.
The accepted support manifest and frozen fixture hashes also matched.

`App/MuralApp.swift` adds the explicit `--coreai-hybrid-fresh-encoder` flag to
`--coreai-whisperkit=hybrid --coreai-fixture=001.wav`. It selects only the new
canonical directory, validates the original h18p tree digest, records the chosen
path and cache-lookup result, and refuses a cache hit before function loading.
No automatic retry, fallback or cache deletion was added. Baseline and historical
Core AI decoder paths remain unchanged. Normal Talk remains WhisperKit/Core ML.

`Tools/CoreAI/test_hybrid_layout.py` additionally runs the actual Swift argument
validator, including rejection of baseline+fresh, duplicate/malformed fresh flags,
legacy decoder/path flags and wrong/missing fixture selection. Existing layout,
bit-preservation, strided-read and finite/type/shape checks still pass.

## Validation and cleanup

- Release build/install passed; only the existing missing-AppIntents warning.
- Actual Swift argument/layout check and `git diff --check` passed.
- Existing assets, caches, learning data and incoming source work were retained.
- No model/backend/precision change, cloud request, dependency install, toolchain
  change, full corpus, commit, publication or subagent.
- The owned Mural-only capture exited. Fresh PID 42569 was rediscovered and
  terminated after the failed probe; no Mural process remained.
- Before/after Mural crash inventories were identical.

Device: Kevq, iPhone 17 / iPhone18,3, UDID `00008150-000D25942278401C`, iOS 27.0
`24A435`, Core AI `h18p`. Xcode 27.0 `27A5252f`. In-place installation retained
`com.kevintruong.mural.dev`; paths were resolved against the new data container.

Executable SHA-256:
`2973e57b08a4a052d7df3955f7c02341223fd8c3356610629d8af3ec8571be79`.

Evidence: `.build/verification/coreai-hybrid-fresh/`, including the incoming diff,
original file hashes and helper fingerprint, staging inventory, build/install
logs, fresh report/events, scoped runtime log, crash inventories and cleanup.

## Review gate

**Follow-up executed:** the separately approved [cache-invalidation checkpoint](hybrid-invalidation-checkpoint.md)
resolved encoder loading and completed the first hybrid transcript, then stopped
after a memory warning and second-turn process disappearance. The restrictions
below record the earlier checkpoint; do not repeat the fresh-path attempt.

Do not repeat this fresh-path attempt unchanged: it is known to hit a cache.
Further work needs a different, deliberately reviewed cache-isolation or narrowly
scoped cache-invalidation experiment. No cache invalidation was authorized or
performed here. The hybrid's encoder numerical comparison, transcript parity,
startup performance and lifecycle acceptance remain blocked and unproven.
