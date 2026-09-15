# Core AI ASR handoff — transcript parity checkpoint

## Controlling status

Core AI AOT loading is **accepted for continuation**.

Tested prior commit:

```text
8e80058df135b6032c7d57e5c0c28193c4b3a751
```

Physical device:

- iPhone 17 / `iPhone18,3`
- iOS 27.0 (`24A435`)
- Core AI architecture `h18p`

Frozen source:

```text
/Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/merge-fp16/model
```

Weights:

```text
3,086,759,768 bytes
SHA256 264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a
```

Frozen-source ASR replay: **22/22 normalized matches**.

## Loading evidence

Monolithic FP16 Core AI artifact:

- `.aimodel`: 3,087,059,590 bytes
- matching `.aimodelc`: 3,087,114,272 bytes

Controlled physical-phone timings:

| Run | Cache | Specialization | loadFunction | Total |
|---|---:|---:|---:|---:|
| Cold 1 | miss | 7.585 | 7.209 | 14.816 |
| Cold 2 | miss | 6.188 | 5.523 | 11.734 |
| Cold 3 | miss | 6.218 | 6.077 | 12.314 |
| Cached 1 | hit | 0 | 5.346 | 5.349 |
| Cached 2 | hit | 0 | 5.594 | 5.597 |
| Cached 3 | hit | 0 | 5.782 | 5.784 |

This is a ~17x improvement over the historical ~215 s first Core ML/ANE
prepare. Missing the former cached <=5 s goal by ~0.35–0.78 s is not a blocker;
the remaining cached cost is almost entirely `loadFunction`.

No correlated Mural crash, Jetsam, memory-pressure termination, or thermal
warning was reported. One launch failed only because the phone was locked.

A nonfatal Core AI/MPSGraph message mentioned no ANE hash / GPU-only / wrong
target. Actual compute placement remains unproven and must not be inferred from
that message alone.

## What this commit adds

This checkpoint adds a **parallel transcript-parity path only**:

1. split Core AI encoder exporter;
2. simple full-prefix Core AI decoder exporter;
3. split AOT compilation helper;
4. Release-build iPhone corpus probe;
5. reuse of the accepted Core ML 80-mel frontend;
6. reuse of the exact existing PhoWhisper tokenizer/control-token contract;
7. JSON per-fixture timing/transcript evidence.

Normal Mural on-device conversations remain on WhisperKit/Core ML.

## Why the old mel frontend is reused

Apple's stock CoreAISpeech Whisper frontend is currently v3-oriented and uses
128 mel bins. PhoWhisper Large-v2 requires 80.

Rather than introduce a new mel implementation and a new encoder/decoder
runtime in the same experiment, this checkpoint reuses Mural's already-accepted
`MelSpectrogram.mlmodelc`.

That isolates transcript differences to the Core AI encoder/decoder path.

## Exact next action

1. Pull the latest `mvp` commit.
2. Read `Tools/CoreAI/README.md`.
3. Confirm clean checkout.
4. Build Mural Release immediately. Fix only narrow compile/API issues caused by
   the new probe if Xcode 27's Core AI surface differs.
5. Reuse the exact frozen merged source above.
6. Run `export_phowhisper_split_coreai.py`.
7. Run `compile_split_aot.sh`.
8. Stage the architecture-matching encoder + decoder `.aimodelc` pair.
9. Preserve the installed accepted PhoWhisper Core ML support directory.
10. Stage the same frozen 22 audio fixtures.
11. Launch `--coreai-asr-probe --coreai-asr-auto`.
12. Retrieve `Documents/coreai-asr-probe.json`.
13. Compare exact outputs to the accepted baseline using the same normalization.
14. Stop and report. Do not implement KV cache or change the normal conversation
    path in the same session.

## Gate

PASS only when:

- 22/22 normalized transcripts match the accepted FP16 baseline;
- no new code-switch regression;
- no app termination;
- all files produce finite valid outputs.

Latency is measured but is not yet a hard pass gate because this first decoder
deliberately recomputes the prefix.

## Report back

```text
Commit tested:
Local diff:
Xcode/macOS:
iPhone/iOS:
Core AI architecture:

Encoder .aimodel bytes:
Decoder .aimodel bytes:
Encoder matching .aimodelc bytes:
Decoder matching .aimodelc bytes:

Split prepare:
  mel model:
  tokenizer:
  encoder cache/specialize/loadFunction:
  decoder cache/specialize/loadFunction:
  total:

Corpus:
  passed normalized:
  failed normalized:
  exact mismatches:
  per-file JSON:

Representative latency:
  English:
  Vietnamese:
  forward switch:
  reverse switch:
  Yes:
  No:
  silence:
  long turn:

Crash/Jetsam/thermal/memory notes:
Core AI/MPSGraph messages:
PASS/FAIL:
```
