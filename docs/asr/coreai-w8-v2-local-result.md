# W8 v2 local recovery: stopped before native inference

2026-09-17, `mvp` at `ab93c123f41fd354974fd6423631d10cd8d7c317` plus the local implementation diff. Origin fetched; checkout already contained the requested commit and was clean. No prior work reverted.

## Result

**Tiny static separation passed. Tiny native isolation did not pass. Full encoder, corpus and speech gates remain blocked.** The FP16 control failed specialization before a function could be loaded. One bounded source-versus-AOT diagnostic failed identically. No further model attempts were made.

Device compiler diagnostic, for both `.aimodelc` and `.aimodel`:

```text
unknownCompilerError: type of return operand 1 ('memref<16xsi32>')
doesn't match function result type ('memref<16xsi32, "MTLBuffer">')
in function @mural_tiny_fp16_189d01ff64e7a71d1708
```

This is an observed marker-output memory-space rejection, not a demonstrated fix or recurrence of the old cache alias. Neither numerical inference nor native marker validation was reached. Source specialization is not an uncached workaround; both attempts queried the default cache and recorded misses. No cache mutation/deletion or native hash editing was performed.

## Implementation

- `Tools/CoreAI/rebuild_w8_identity.py`: tiny export no longer requires metadata for the unused `transformers` package. The preserved compression environment has no transformers; the initial CLI failed before creating an output directory. Encoder exports still require it. No dependency installation or pin change.
- `App/W8TinyProbe.swift`: development-only, one attempt per process, pinned complete manifests and recursively hashed artifacts including hidden files. Supplied verifier runs before named function loading and before accepting hidden output. Checks descriptor contracts, all three finite synthetic vectors with the unchanged 0.05 bound, repeated output digests, required cache hits and serial returned native scopes. Cancellation/warnings stop progression; no decoder, microphone, tutor or main fallback. Scope return does not assert driver memory retirement.
- `App/MuralApp.swift`: routes explicit `--w8-tiny` to the bounded probe using the existing temporary-store/report surface. Refuses another run after a memory warning. `--w8-tiny-reverse` selects the fresh-process reverse sequence; `--w8-tiny-source` restricts the diagnostic to the FP16 source control.
- `scripts/generate_project.py`: adds the supplied `Tools/CoreAI/W8IdentityVerifier.swift` directly, without copying or weakening it. Generated project diff contains only two source references/build entries and group/source-list additions. Signing file SHA-256 unchanged; package versions and language mode unchanged.

No v2 speech candidate was enabled. Old v1 rejection, normal Release selection, single-owner Talk implementation, generation/drain safeguards and frozen model/frontend/tokenizer remain unchanged.

## Host evidence

Preserved Python 3.11.11 environment: coreai-core 1.0.0b2, coreai-torch 0.4.1, coreai-opt 0.2.1, Torch 2.11.0, NumPy 2.3.5, ml-dtypes 0.6.0. macOS 26.6.2 (25G83), Xcode 27.0 (27A5252f), iOS SDK 27.0, coreai-build 3600.83.1, Swift 6.4.

- Nine Python tests passed, including actual Torch wrapper/export replay; portable Swift verifier passed. Repeated after implementation.
- Fresh FP16, FP8 and INT8 tiny exports completed sequentially with AOT. All three passed compiler-inspected named input/output contracts and final `w8_identity.py` rehash audit.
- FP8/INT8 each compressed the one eligible 4096-element weight tensor; no eligible weight remained uncompressed. FP16 retained its weight. Each export preserved the host output before quantization and the required marker signature.
- Import warnings: unsupported scikit-learn conversion version, Torch version untested by coremltools, macOS distributed redirects, TreeSpec deprecation. Manifest quantization warning lists empty; AOT logs only report compilation.
- Signed Release probe builds passed against the public SDK without verifier API corrections. Actual compiler commands include `MURAL_COREAI_TALK` and `MURAL_COREAI_W8`. Existing LiveTransport async-alternative, audio-interruption deprecation and no-AppIntents warnings remain. A final host build also passed after adding an explicit post-specialization cancellation/warning check and removing the redundant zero-warning assignment. That final safety-only diff was not redeployed or rerun; the device remains on the source-diagnostic build.

| Tiny candidate | Source bytes | AOT bytes | Native compiler identity (raw hash bytes, hex) |
|---|---:|---:|---|
| FP16 | 9,713 | 20,476 | `c9f7a757901814cded9c9eb47dc302ba7550143f8d89703027609d36fbde267d` |
| FP8 | 5,769 | 17,302 | `e50bc5002c543fc9c6bb12690a70aa9fb053f0b4b62df2d271bf4036332c7cdf` |
| INT8 | 5,803 | 20,555 | `164498ed3ffbe586ada3d64b10a38af2cfaa8d8ed947ef7df052039cb6c90600` |

AOT fingerprints:

```text
fp16 fa9b67f448fdff12644133dd761bb99c5e4d0608026d0ee42e068736e0162a42
fp8  227baeae8238643179a13f037ce8c1506956e3115d20ceff297dbd6b38b2c43c
int8 05b1fa69857fc50d0415b356d0fbe7f46b3b615bbeb6b19661f23730460443d4
```

Complete manifest SHA-256 pins:

```text
fp16 1865b9c71d7836db912dd715152472f224773af4c470ae1e2f4d51394f8329cf
fp8  acc8df9b0f2cfad68045e299991eee0522097aedfb1b5fba84156f5d558e4287
int8 03cb5cc93ec1bb851392473d2a2d6d56cc9599419d2894684405ccac527bb3db
```

Authoritative manifests: `.build/coreai/w8-id-v2/tiny-{fp16,fp8,int8}/manifest.json`. Their identity recipes bind the actual exporter/helper hashes, toolchain, synthetic weights, quantization and marker. All retained assets are synthetic; no frozen speech weights were re-exported.

## Agent-observed device evidence

In-place installs preserved bundle `com.kevintruong.mural.dev`, existing app data and caches. iPhone 17/iPhone18,3/h18p, iOS 27.2 (24B5084k).

- AOT control run `FC0EB324-C3F1-482A-8B0E-BCA814D9BCE0`: manifest/artifact verification passed, cache miss, specialization failed. No function load or inference. Compressed sequence did not start.
- Source diagnostic run `EF9C6DE5-1B2D-4AC4-9E7A-309364AC1C45`: independently pinned source verification passed, cache miss, same specialization failure. No further attempts.
- Both reports record zero iOS memory warnings and event thermal state 1 (fair).
- Highest recorded physical-footprint event: AOT 18,843,344 bytes; source 25,282,376 bytes. Highest recorded process-lifetime RSS peak: AOT 66,584,576 bytes; source 78,200,832 bytes. AOT has no post-failure memory sample; these are not model peak-memory measurements.
- Source cache-lookup event to specialization-failure event: approximately 0.096 seconds, a failed compiler interval, **not inference latency**. No Send-to-final, token count, native inference, tensor copy/dump or speedup result exists.
- Actual host allocation for all tiny exports/manifests/logs: `du -sk` reported 228 KiB. Final phone `AmountDataAvailable`: 84,399,742,976 bytes. This is OS-reported free data storage, not app size; phone per-artifact allocation and cache growth were not measured. File-byte totals above are actual host artifacts, verified by fingerprint on phone.
- Both owned Mural-only syslog captures terminated in `finally`; cleanup records retained. No surviving idevicesyslog process observed. No device-wide archive, uninstall, cache deletion, memory exhaustion or latch reset.

## Human confirmation

Interview responses: phone ready/unlocked; first probe visibly failed with `CoreAIDelegates.AIModelError error 1`; source diagnostic visibly failed with the same error and the matching `EF9C6DE5...` report path. No dictation was requested. Human confirmation establishes visible failure, not native identity or speech quality.

## Blocked and next review

Not run: FP8/INT8 native vectors, alternating/reverse/cache-hit isolation, fresh full encoder exports, original-versus-v2 mel comparisons, PAL8/FP16 corpus combinations, live mixed-language/short-answer/silence/drain/offline checks, first/warm timings and long soak. No corpus differences can be reported. Existing accepted PAL8 exceptions 006/007 and diagnostic-only 017 remain unchanged. The misattributed v1 0.471-second FP8 result is excluded.

Next single action for review: use the retained synthetic reproducer to investigate the marker return memory-space rejection with Apple or a separately controlled supported compiler. Do not promote a default, alter marker semantics to manufacture a pass, or resume full encoders on static evidence alone.

Local evidence: `.build/verification/w8-v2-recovery/`, including both native reports/events/logs, complete manifests, manifest pins, static reviews, compiler commands, signing comparison, environment, interview feedback and implementation diff. All device logs remain local and uncommitted. `tiny-reproducer.tar.gz` preserves only the FP16 synthetic source/AOT/manifest and minimal native-call instructions, with no audio or speech weights. No commit or publication was made; return the local diff for review.
