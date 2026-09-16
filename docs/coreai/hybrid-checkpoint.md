# Core AI encoder + WhisperKit decoder checkpoint

Date: September 16, 2026.
Status: **Implemented; current Core ML baseline passed; hybrid blocked at encoder function loading. Stopped for review.**

## Scope and outcome

The user approved steps 1-2 of the proposed conservative alternative: a current
Core ML baseline and fixture 001 through Core AI encoder + existing WhisperKit
decoder. No corpus, compute sweep, prewarm removal, cache deletion or production
integration was performed. Normal Talk remains unchanged.

The baseline completed two serial fixture-001 transcriptions, preserving accepted
text, language `vi`, and all token IDs. The hybrid failed **before encoder inference
and before creating/loading WhisperKit**. `loadFunction("main")` in the existing
Core AI loading helper threw `Foundation._GenericObjCError error 0`. The scoped
runtime log identifies an existing cached encoder specialization and reports:

```text
CoreAIRuntime: Loading function 'main'
MPSGraphNDXRuntime.mm:603: Error, could not load model for cacheIdentifier
```

This is a **throwing encoder load failure**, not the previous Core AI decoder
SIGABRT. The app remained alive, reported the error, and produced no hybrid
encoder output, logits or transcript. The Mural crash inventory was unchanged.
No retry of the unchanged load was attempted.

## Implementation

`App/MuralApp.swift` extends the existing development-only probe with:

```text
--coreai-asr-probe --coreai-asr-auto --coreai-fixture=001.wav
--coreai-whisperkit=baseline|hybrid
```

These modes accept only the frozen fixture 001 and canonical installed assets.
Conflicting legacy decoder/stateful/encode-only/decode-only/path flags are rejected
before model loading. Each successful run is bounded to two serial turns, stopping
at the first text/language mismatch, thrown error or cancellation. The second
turn must also reproduce the first turn's token sequence.

- Baseline wraps the stock `AudioEncoder` to copy its actual input/output tensors;
  Core ML loading and predictions still use pinned WhisperKit code.
- Hybrid injects `AudioEncoding` via `WhisperKitConfig`, without a library fork or
  handwritten decoding. It does not conform to `WhisperMLModel`, so WhisperKit
  skips Core ML encoder loading. The existing encoder directory remains because
  the pinned loader still checks its existence.
- The adapter retains one Core AI function for both turns. Only owned arrays cross
  actor isolation; `nonisolated(nonsending)` bridges WhisperKit's non-Sendable
  protocol parameters/results without unchecked Sendable annotations.
- FP16 `[1,1500,1280]` output is copied to stride-aware Core ML
  `[1,1280,1,1500]` storage. Shape/type/finite guards remain at the boundary.
- Accepted manifest/file hashes and fixture hash are verified before inference.
  The hybrid additionally records the encoder tree fingerprint.
- Both use the existing mel frontend, tokenizer, suppression and exact current
  `LocalConversationEngine.WhisperRecognizer` decoding settings. Decoder compute
  remains `.cpuAndNeuralEngine`; mel remains `.cpuAndGPU`.
- The local kit is unloaded on success/error; the Core AI function is owned by
  the local adapter, not by a production singleton. No automatic fallback.

Reports retain UUID run identity, flushed before/after events, component timing,
thermal/memory samples, raw WhisperKit results, token IDs, canonical mel `.f32`
and encoder `.fp16` captures. Tensor captures add diagnostic copying overhead;
these are instrumented observations, not production latency distributions.

## Current phone baseline

Run: `8E2DFA30-2D91-4071-ACD7-BAD693F5F3BA`.

| Stage | Seconds |
| --- | ---: |
| Asset/fixture verification | 1.925 |
| Tokenizer/config | 0.278 |
| Total prewarm | 220.040 |
| Decoder prewarm | 34.760 |
| Encoder prewarm | 185.172 |
| Subsequent total model load | 4.693 |
| Decoder load | 3.060 |
| Encoder load | 1.624 |
| Total preparation | **226.944** |
| First transcription, 5.66-second fixture | **1.868** |
| Repeated transcription | **1.688** |

Prewarm fields measure model-load calls, not independently traced compilation.
Core ML cache state was not observed or reset. This is one fresh-process sample,
not a verified cold/cached distribution. The measured decoder prewarm independently
reproduces the earlier roughly 34-second concern. Removing only the Core ML
encoder cannot be claimed to meet 15-second readiness from this evidence.

Both turns returned `Yesterday I went to the supermarket.` with language `vi`
and these identical tokens:

```text
[50258,50278,50359,50363,56,4690,286,1437,220,1353,220,3322,25180,13,50257]
```

The two mel captures were bit-identical, as were the two encoder captures:

- Mel SHA-256: `45989a5ad4d363d2afd85d91170bbbac97fffbb45d92ca4af6c5bad632588049`.
- Core ML hidden SHA-256: `6a9faa519c3ad153cb1304f82d68c8ee82b167469754b72eb70db026846b5a2f`.

Largest sampled baseline footprint: 3,501,066,632 bytes. Process-lifetime RSS peak
reported at boundaries: 1,589,264,384 bytes. These are different OS metrics, not a
continuous driver-memory peak. All recorded thermal samples were nominal.

## Hybrid failure and limits

Run: `7110FA3C-D44F-448C-BFE8-18C5CACAA13D`, PID 42424.

- Accepted support manifest: `7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52`.
- Encoder tree: `b13ccaf3fa91098a21bc81786843e138ad2e6cde4a9fdcccece6d531b0f9d034`.
- Last flushed stage: `whisperkit-coreai-load-before`.
- Native log names the existing `coreai-cache/24A435/.../model.aimodelx` entry.
- The cache inventory and small cached manifest/ODIX were inspected read-only.
  They do not establish why MPSGraph could not load the model.

An in-place installation changed the data-container URL; the probe resolves the
current URL rather than passing an old absolute path. Internal cache relocation
or stale specialization is only a hypothesis, not an established cause. No
missing-file repair, cache deletion, source-model rewrite or backend change was
justified by the retained evidence.

**Unproven:** encoder numerical comparison on identical mel, hybrid transcript or
token parity, hybrid resource coexistence, startup timing, reset/cancellation on
phone, full corpus, and user microphone/listening acceptance.

## Validation and preservation

- Release build/install passed. Initial adapter concurrency warnings were fixed
  by keeping non-Sendable protocol values outside actor isolation. Final rebuild
  emitted only the existing missing-AppIntents metadata warning. No strict-Swift-6
  audit is claimed; project settings remain Swift 5 / targeted concurrency.
- `python3 Tools/CoreAI/test_hybrid_layout.py` passed: actual Swift bridge,
  independent layout checks, bit preservation, non-contiguous reads, invalid
  shape/type and non-finite rejection.
- Existing `test_probe_contract.py`, `test_mel_reader.py`, and whitespace checks
  passed. Historical decoder code and incoming untracked files were preserved.
- No model export, dependency install, toolchain change, Core AI decoder execution,
  cloud request, learning-data change, commit, subagent or publication.
- Both owned Mural-only log captures exited. The fresh hybrid process was
  identified and terminated; no Mural process remained. No broad logs collected.

Device: Kevq, iPhone 17 / iPhone18,3, UDID `00008150-000D25942278401C`, iOS 27.0
`24A435`, Core AI `h18p`. Xcode 27.0 `27A5252f`. Installed in place as
`com.kevintruong.mural.dev`.

Executable SHA-256:
`3f8cf49ecfd4dd74357628a9ec5da50f9cf14eb7c02478a052967a304000d09b`.

Evidence: `.build/verification/coreai-hybrid/`, including `starting-worktree/`,
`build-deployed.log`, `install-final.log`, `baseline-run/`, `hybrid-run/`, scoped
runtime logs, crash inventories, cache metadata, executable identity and cleanup.

## Review recommendation

**Follow-up executed:** the separately approved [fresh-path experiment](hybrid-fresh-encoder-checkpoint.md)
verified the original AOT copy but its new path still resolved to a cached
specialization. The guard stopped before function loading. The recommendation
below is historical; do not repeat it unchanged.

Do not retry the same cached encoder unchanged. A next bounded investigation
could load a separately staged, byte-verified copy of the original encoder AOT
under a new path, preserving all existing assets/caches. First establish whether
that produces an independent specialization and a loadable function; do not
assume it fixes this failure. At this initial checkpoint the follow-up was **not implemented or run**.
If approved and successful, resume the same one-fixture hybrid proof and compare
its actual mel/hidden tensors and tokens against the captured baseline. Full
corpus, compute selection and production integration remain later gates.
