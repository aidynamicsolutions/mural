# Hybrid ASR memory checkpoint

Date: September 16, 2026.
Status: **Hybrid startup and fixture parity demonstrated; ordinary repeated-turn memory failure isolated; production integration not yet approved.**

## Scope

This checkpoint records the bounded Core AI encoder plus existing WhisperKit/Core ML decoder investigation on fixture `001.wav`. The frontend, tokenizer, FP16 weights and decoding settings remained unchanged. Normal Talk remained on WhisperKit/Core ML.

Device: Kevq, iPhone 17 / `iPhone18,3`, iOS 27.0 `24A435`, Core AI `h18p`, bundle `com.kevintruong.mural.dev`.

No corpus expansion, model or precision change, backend sweep, toolchain update or additional cache invalidation was performed during this memory investigation. The earlier invalidation run called `AIModelCache.default.deleteEntry(for: encoderURL, options: .default)` exactly once; this checkpoint does not authorize repeating it.

## Baseline and hybrid timing

The all-Core-ML baseline measured:

- Preparation: **226.944 s**
- Encoder prewarm: **185.172 s**
- Decoder prewarm: **34.760 s**
- First/repeated transcription: **1.868 / 1.688 s**

The first complete hybrid run after the approved encoder cache invalidation measured:

- Encoder specialization: **22.032 s**
- Function load: **0.048 s**
- Decoder prewarm: **57.096 s**
- Total preparation: **82.528 s**
- First transcription: **4.353 s**

A later ordinary cached hybrid run measured:

- Cache hit with zero specialization
- Preparation: **8.149 s**
- First transcription: **1.902 s**

These are individual samples with different cache histories, not a controlled speedup distribution. They demonstrate a promising startup reduction, not a final cold-start or p95 result. The hybrid runs did not establish the 15-second readiness target.

## Transcription parity

Every completed fixture-001 hybrid turn returned:

```text
Yesterday I went to the supermarket.
```

Detected language was `vi`. The token sequence was:

```text
[50258,50278,50359,50363,56,4690,286,1437,220,1353,220,3322,25180,13,50257]
```

The actual mel input was byte-identical to the accepted baseline:

```text
45989a5ad4d363d2afd85d91170bbbac97fffbb45d92ca4af6c5bad632588049
```

The Core AI encoder output was reproducible across the hybrid runs and matched the earlier Core AI checkpoint:

```text
cdf3c3f5300103ad2b0a23e414b070041d21e7f7c0f77f18ce32bc52824957ae
```

The Core AI hidden tensor was not bit-identical to the Core ML encoder tensor. The measured maximum absolute difference was `0.6015625` and RMSE was `0.0053676719`. No post-hoc numerical tolerance was selected. Therefore the evidence supports **no observed transcription regression on fixture 001**, not full accuracy parity across the corpus.

## Failure and lifetime finding

The ordinary cached hybrid run was `B3E8E007-5FDC-47BE-BB48-6C938AAC7282`. It completed the first turn and began turn two, then the kernel reported:

```text
Mural [42791] exceeded mem limit: ActiveHard 3376 MB (fatal)
killing_specific_process ... (per-process-limit ...) 3471810KB
```

RunningBoard/SpringBoard reported:

```text
RBSProcessExitStatus domain:jetsam(1) code:per-process-limit(7)
```

This is confirmed for that run as a kernel per-process memory-limit termination explicitly labeled Jetsam/per-process-limit. It was not an app-thrown Swift error or a captured SIGABRT.

A one-turn lifetime diagnostic (`EAB73896-B455-4674-AF00-AAB0E43E3881`) then released `WhisperKit` models, replaced the hybrid encoder with the baseline encoder, dropped the hybrid references and waited two seconds:

- Footprint after first turn: `3,525,576,832` bytes
- Footprint after release: `55,134,168` bytes

This large drop shows that the retained Core AI encoder and WhisperKit model resources are releasable and directly account for the high footprint. It does not identify a lower-level allocation site or prove a Swift retain cycle.

The release-and-recreate diagnostic (`554F4732-3E35-4993-9982-81B4AE6F4C49`) loaded a replacement cached encoder before turn two and completed both turns exactly:

- Replacement reload: `0.173836 s`
- Turn 1/2: `3.641500 / 1.657224 s`
- Footprint after release: `56,739,824` bytes
- Footprint after replacement reload: `3,249,670,152` bytes
- Footprint after turn-two encoder: `3,528,591,416` bytes
- Footprint at proof completion: `3,430,025,200` bytes

The run recorded two memory warnings but no kernel memory-limit kill, Jetsam exit, SIGABRT or app error before proof completion. This demonstrates that explicit release and recreation was sufficient for two turns in one bounded fixture run. It does not establish long-running stability or production readiness.

## Evidence

- Cached run: `.build/verification/coreai-hybrid-memory/cached-startup-20260916-095610/`
- Lifetime run: `.build/verification/coreai-hybrid-memory/lifetime-release-after-first/`
- Release/recreate run: `.build/verification/coreai-hybrid-memory/recreate-between-turns/`
- Consolidated result: `.build/verification/coreai-hybrid-memory/result.md`

Each run contains the retrieved phone report, flushed events, raw WhisperKit results, tensor captures and scoped runtime/system/kernel logs. The evidence directories are ignored build artifacts and are not part of the source commit.

## Decision

The work achieved a credible hybrid proof of concept: startup preparation can be much shorter and the frozen fixture transcript remained exact. It did not achieve a production-ready ASR implementation because the ordinary retained-resource path can be killed on the second turn, and the lifecycle workaround has only one two-turn sample.

The next work should validate the lifecycle design and full-corpus quality before changing normal Talk. The production plan is in [hybrid-production-plan.md](hybrid-production-plan.md).
