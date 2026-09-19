# W8 v3: repair the diagnostic ABI and continue qualification

Date: 2026-09-17. Reviewed `mvp` head: `f5dbbf98f847fe2c8665bf767259eb9c728ce5d4`.

**Status:** new exporter, runtime-identity helper, native tiny-probe wiring and portable tests are implemented. Portable checks pass. Apple conversion/AOT, Xcode type-checking of the changed native probe, native cache isolation, full PhoWhisper accuracy and iPhone speed/memory remain unverified here. Actual generated manifest pins must be installed locally before the probe loads anything. This is not a default model change.

This is the current execution plan. It supersedes the v2 instruction that changing the marker representation requires stopping for review. Preserve both previous reports and their failed artifacts as historical evidence. Do not revert the useful prior implementation.

## What failed, and what did not

The latest report, `coreai-w8-v2-local-result.md`, says:

- Tiny FP16, FP8 and INT8 static/AOT identities are distinct.
- The FP16 control fails device specialization with a return-operand memory-space mismatch: `memref<16xsi32>` versus `memref<16xsi32, "MTLBuffer">`.
- One source-versus-AOT diagnostic fails with the same message.
- No function load or inference is reached; no compressed computation, corpus or latency comparison runs.
- The device is iPhone 17 / h18p, iOS 27.2 (24B5084k), with compiler 3600.83.1 and the preserved authoring environment.

Therefore the immediate blocker is the **diagnostic marker return**, not evidence that FP8 inference cannot work. The prior v1 identity collision remains unresolved on-device; distinct static v2 identities do not close that gate.

The v2 wrapper introduced by the prior remote change does `return hidden, self.identity_words.clone()` with constant Int32 words. Apple's pinned `coreai-torch` v0.4.1 operator table describes `clone.default` as an identity in the absence of memory-format changes. A host clone is not a promise of a device-buffer copy. MLIR memory spaces are part of memref types, so the reported types are different even though their dimensions and integer elements match. This supports a constant-return placement/lowering hypothesis; it does not identify an exact private compiler pass or establish that all integer outputs are unsupported.

Preallocating `outputViews` at `function.run` is not the primary remedy: this failure occurs during specialization, before there is a loaded function to run. Nor is source loading an uncached workaround. Do not repeat those unchanged v2 attempts.

## The implemented change

Keep the identity invariant, change its representation.

V3 takes the original audio/features input plus a separate small FP16 `identity_challenge` tensor. The wrapper computes:

```text
hidden = original_encoder(input_features)
response = runtime_challenge + recipe_digest_bytes
packet = concatenate(flatten(hidden), response)
```

The default `packed` mode returns **one computed FP16 tensor** instead of a separate constant Int32 return. The `split` alternative returns the unchanged hidden tensor and the same computed FP16 response separately. It is an explicit diagnostic/build choice, not a production fallback.

The caller supplies integer-valued challenges in 0...31. Digest bytes are 0...255, so all sums are at most 286 and exactly representable in FP16. The full 32-byte digest is represented; repeated bytes create distinct 32/40/48-value interfaces for FP16/FP8/INT8, not extra entropy. The host checks exact challenge/response equality, not a loose cosine threshold. The identity includes source, format, transport, exporter/helper hashes and toolchain. Named functions, actual bundle pins and native hash separation remain mandatory.

The challenge is a real tensor input. It is not `input * 0`, an unused argument, or a new constant that an optimizer can eliminate. Host tests change the challenge after Torch capture. Phone checks repeat the same numerical input with different challenges and require identical hidden values but the correct changed response.

Packing does not perform arithmetic on hidden states. Host replay verifies exact equality before quantization. The full encoder still supplies the same FP16 `[1,1500,1280]` features after the verified packet is unpacked. **The wrapper changes the exported ABI**, so the native caller must use v3 descriptors and unpack explicitly. Do not point the old `main`/`encoder_hidden_states` reader at a packed model.

Packing may introduce an approximately 3.84 MB full-encoder output copy; measure its cost. The added marker itself is only 64-96 bytes. This is not expected to erase hundreds of MB of weight savings, but no iPhone memory/latency claim is made. Once packed mode works, split mode can be an evidence-led alternative if that copy matters.

The marker is diagnostic identity information, **not cryptographic attestation of every internal weight resource**. Continue numerical oracles, cache-order tests and corpus checks. Do not remove those checks merely because a response matches.

## Files and responsibilities

- `Tools/CoreAI/w8_runtime_identity.py`: v3 identity, exact challenge/response, packed/split wrappers, capture/ABI checks, streaming fingerprints, actual artifact rehashing and trio separation audit. `--print-swift-pins` prints real generated manifest digests.
- `Tools/CoreAI/rebuild_w8_runtime_identity.py`: reuses the preserved v2 model/audit helpers, not its faulty wrapper; exports tiny or exact frozen full encoder candidates; validates multiple challenges before and after Torch capture; preserves compression coverage gates and AOT inspection.
- `Tools/CoreAI/W8IdentityVerifier.swift`: retains the v2 definitions and adds v3 validated extraction, exact response checks and stride-aware FP16 reading.
- `App/W8TinyProbe.swift`: uses the existing build-gated entry point, but loads from a new v3 directory and only with v3 manifest pins. Validates both runtime inputs and outputs, numerical results and repeated cache-hit results. One runtime attempt per process is retained.
- `Tools/CoreAI/test_w8_runtime_identity.py`: portable negative tests, real Torch export/replay and compiled portable Swift verification.

`MuralApp.swift` already routes `--w8-tiny`; the existing project already includes both Swift files, so this patch adds no project/signing changes. Normal Talk and the v1 blocked candidates remain unchanged. Empty v3 pins are intentional because this environment cannot generate Apple's AOT bytes; filling actual audited pins is a normal local build step, not a research blocker.

## Execution sequence: continue automatically through passed gates

Use the concrete commands and pin/staging procedure in `local-agent-handoff.md`.

1. Run existing focused checks plus the v3 portable tests. Build the tiny FP16 control first to inspect the new ABI, then the tiny FP8 and INT8 candidates. All three are small; no full model transfer yet.
2. Audit all three actual source/AOT bundles. Insert generated complete-manifest pins in the designated block of `App/W8TinyProbe.swift`. Stage manifests plus their source/AOT bundles under `Documents/CoreAI/W8TinyV3/packed/tiny-{format}`. Build the explicit W8 Release probe and install in place.
3. Run forward order FP16/FP8/INT8/FP16/FP8/INT8, then reverse order in a fresh process with caches retained. For each model load, run all three synthetic inputs with three different challenges. The probe requires hidden-output repeatability, exact identity response, the existing 0.05 numerical bound and required cache hits on repeated visits. These are cache-diagnostic bounds, not ASR accuracy criteria.
4. If the tiny native gate passes, do not stop just to report that milestone. Build the full v3 FP16 control and FP8 candidate from the exact frozen merged weights. Retain INT8 as a control; its previous AOT storage expansion may make it a less useful deployment winner. Record source and AOT bytes separately.
5. Audit the full trio and pin the actual artifacts before loading. Add a separate v3 selection to the existing staged/probe owner, retaining the v1 stop guard. Carry `{URL, pinned spec, decoder support}` together immutably for the session. Use the named function, send a bounded challenge, validate/unpack output, then bridge the owned hidden array to the existing decoder. Preserve mel hash, tokenizer and decoder settings.
6. Run full encoder-only checks on several saved inputs, then original encoder/PAL8 control, v3 FP8/FP16 decoder and v3 FP8/PAL8 decoder. Complete the retained corpus and the user's paired live tests without requesting another approval merely because a prerequisite passed.
7. Report actual accuracy/first-turn/warm latency/memory/reliability. Normal-default promotion, new training, paid compute or a different model family are not automatic next steps.

The known PAL8 006/007 exceptions remain accepted for this bounded trial. New differences are not silently waived or hidden by changing references. The 21 scored recordings and diagnostic-only 017 remain separate. The misattributed v1 0.471-second run is not FP8 speed evidence.

## Recovery policy: a failed attempt is not always a project blocker

The previous agent made useful narrow fixes already, including the unused transformers dependency and native probe wiring. It stopped consistently with the earlier handoff's strict marker/stop rules. The new policy authorizes responsible recovery rather than asking it to ignore warnings.

### Fix and continue without a new user approval

Missing test-only package, importer spelling, argument order, current public SDK type name, compiler JSON presentation, generated manifest pins, project reference, transfer path, stale report pointer, locked phone or a collected log gap: diagnose, make the smallest correction, rebuild/check, and continue. Preserve every failed result. Rediscover PIDs/containers; never reuse historical identifiers. Ask through the interview tool only for actual device actions or a decision outside scope.

These fixes may update versioned diagnostic ABI descriptions, wrappers and verifiers together. They must retain the underlying invariants: correct source/model identity, real numerical output, unchanged primary math before quantization, shape/precision validation, one owner and safe teardown. Changing the representation to satisfy a valid contract is not "manufacturing a pass." Removing the check or inflating the numerical tolerance just to pass is.

### Returned compiler rejection on a tiny diagnostic

Record the stage and exact error. If no inference is active, the failed native scope has returned, no warning/crash occurred, and the change addresses the error, continue with a changed hypothesis in a new process. For this particular family:

1. Try the implemented packed computed-FP16 route.
2. If rejection specifically implicates packing/reshape/return ABI, use the implemented dynamic split-FP16 route with new identity, manifests/pins and the same numerical/challenge gates.
3. If both fail, create a tiny named **hidden-only** control to distinguish basic numeric lowering from instrumentation. It is a diagnostic only, not an identity pass or a full-encoder authorization. Inspect final graph inputs/outputs; use supported documented APIs. A separately installed supported compiler may be compared only with matching fresh FP16/FP8/INT8 controls and unchanged old environment.

Do not keep retrying the same graph. Limit materially different hypotheses to three per failure class in a session; routine syntax/pin/path repairs do not spend that budget. Each hypothesis needs a predicted observation and a result in an attempt ledger. Exhausting this route does not prohibit independent, already-safe PAL8 work below.

A missing required cache hit is not proof of aliasing: record the storage/OS/cache circumstance, do not delete caches, and qualify a new explicit cache-populate/reload sequence if appropriate. Do not weaken the required-hit result and label the original sequence passed.

### Wrong identity, wrong numbers, native abort, or memory warning

Stop and quarantine that configuration. Do not feed it into ASR, clear the latch, unload a model while native work is active, or repeat the unchanged failure. Preserve evidence and finalized history. Source/artifact pin mismatch means recover the authorized artifact or correct a proven transfer/path fault, not accept unknown bytes. A distinct, safe route may proceed only after all native work/captures are confirmed drained and the phone has recovered. A repeated/system-wide instability ends device testing for the session, not offline diagnosis.

### Independent progress while the encoder route is quarantined

The old original-encoder + saved PAL8-decoder candidate is independent of the v3 marker. It was already implemented but not phone-qualified. The agent is now authorized to finish that controlled path in a separate, clean, fully drained process, using the accepted original GPU encoder and verified PAL8 support. Both greeting prewarm and Send loading must use PAL8. Do not load the old v1 FP8/INT8 models. This is a manual experimental selection, not automatic production fallback.

This route can establish a real 8-bit decoder result even while an encoder compiler issue remains. Label the encoder FP16 honestly; do not report BOTH-component compression. This avoids making all useful latency work depend indefinitely on a tiny diagnostic.

## Measurements and interview workflow

Build/probe/static prerequisites are agent-operated. The user operates microphone/UI and reports through the available interview skill/tool, one check at a time. The agent correlates each answer with bounded Mural-only logs before proceeding. No dictation is needed for tiny tests. Do not invent a skill/tool name.

Measure native `run` wall time separately from validation/copies/file writes; it includes native scheduling/allocation and is not pure GPU kernel time. Record asset checks, cache/specialization/load, encoder/decoder preparation, first prediction, token loop, full Send-to-final, token count, physical-footprint samples, RSS peak, warnings, thermal state and actual storage. Do not extrapolate tiny throughput, file size, or one run to phone speech performance. Do not call a fresh process with retained caches first-ever cold compilation.

Short human suite after machine gates: English->Vietnamese, Vietnamese->English, `siêu thị`, a number/negation, quiet Yes/No and short Vietnamese, silence, one first and two warm turns, End/drain/new distinct turn, focused offline confirmation. Keep learner speech verbatim. Preserve previous broader lifecycle acceptances without replaying them needlessly.

## Checks completed on the connector host

Eight portable tests passed on Linux using Python 3.13.5, Torch 2.10.0+cpu and Swift 6.2.1. They cover actual Torch capture/replay for packed/split wrappers across all format labels and changed challenges, exact hidden preservation before quantization, wrong/stale/non-finite response rejection, corrupted packets, compiler-contract rejection and static artifact/hash failures. The portable Swift verifier was compiled and executed. Python syntax, CLI help and Swift parsing of the probe also passed. This is not the pinned Apple conversion environment; rerun locally. The Core AI extension and probe were not natively type-checked here.

## Evidence-backed limitations and references

- Latest local failure: `coreai-w8-v2-local-result.md`; old true cache alias: `coreai-w8-implementation-checkpoint.md` and `coreai-w8-candidates.json`.
- Apple pinned converter ops (clone identity; add/cat supported): https://github.com/apple/coreai-torch/blob/v0.4.1/docs/api/supported-aten-ops.md
- MLIR memref memory spaces: https://mlir.llvm.org/docs/Dialects/MemRef/
- Apple NDArray layout and views: https://developer.apple.com/documentation/coreai/ndarray
- Native output views are inference-time values: https://developer.apple.com/documentation/coreai/inferencefunction/run(inputs:states:outputviews:)-mqfb
- Apple caching and source specialization: https://developer.apple.com/documentation/coreai/managing-model-specialization-and-caching
- Apple compression of Core AI programs: https://apple.github.io/coreai-optimization/utils/coreai_compression.html

No primary source located confirms a vendor patch for this exact marker memory-space rejection or the earlier alias. The proposed representation change is our source-and-error-based remedy to test, not an Apple-guaranteed fix. Host tests do not prove native placement, cache isolation or bilingual quality.
