# Local-agent handoff: repair the marker ABI and keep the W8 work moving

Updated 2026-09-17 after reviewing `f5dbbf98f847fe2c8665bf767259eb9c728ce5d4`.

Read `coreai-w8-v3-marker-recovery.md` and `coreai-w8-v2-local-result.md` first. This supersedes the older "stop for review before changing marker semantics" instruction. The actual invariants must remain; a tested versioned diagnostic ABI change is allowed. Do not revert prior useful work or repeat the unchanged v2 constant-Int32 graph.

## Mission and continuation authority

Implement/qualify the v3 repair through tiny identity, full encoder, corpus and paired physical-user checks. **Continue to the next stage whenever its prerequisites pass.** Do not return after each milestone just to ask permission to continue.

You may make narrow build/API/exporter/probe/manifest/staging fixes within this same session, update the versioned ABI consistently, and use the bounded alternative paths below. You may also finish the independent accepted-original-encoder/PAL8-decoder experiment if the encoder path is quarantined. Do not switch model family, train, spend on cloud compute, publish a vendor issue, change the normal default, delete user data/caches, weaken numerical checks or repeat a known crashing configuration without a meaningful correction.

Before edits, inspect branch, local work and remote. Fetch `origin/mvp`; fast-forward only when safe. No resets, force pushes, automatic stash, unrelated merges or destructive clean-up. Record the exact commit and local diff. Read the repository's current verify-mural/build procedures. Preserve signing, restored phone data, frozen assets and the existing environment. Native tests need the real rediscovered iPhone/container; do not reuse historical PIDs or container URLs.

## 1. Host checks and tiny exports

Use the preserved Python 3.11 compression environment, not system Python. The v3 exporter reuses `rebuild_w8_identity.py`'s reviewed model/audit helpers but NOT its constant marker. Tiny export does not require transformers. Check help and installed public API signatures; fix narrow version/argument issues from actual documentation, not guessed APIs.

```sh
python Tools/CoreAI/test_w8_runtime_identity.py -v
python Tools/CoreAI/test_w8_identity.py
python Tools/CoreAI/test_w8_identity_swift.py
```

Also run relevant existing product-residency/selection/Talk checks. A source test failing only because it asserts a superseded ABI must be updated to test the new invariant, not deleted; preserve real safety assertions.

Generate the small trio, starting with FP16. Use NEW directories; these example paths must be absent. Shell loops should stop on command failure so it is diagnosed, not hidden by the next successful command.

```sh
for fmt in fp16 fp8 int8; do
  python Tools/CoreAI/rebuild_w8_runtime_identity.py \
    --kind tiny --format "$fmt" --transport packed --aot \
    --output-dir ".build/coreai/w8-id-v3/packed/tiny-$fmt" || break
done
python Tools/CoreAI/w8_runtime_identity.py \
  .build/coreai/w8-id-v3/packed/tiny-fp16/manifest.json \
  .build/coreai/w8-id-v3/packed/tiny-fp8/manifest.json \
  .build/coreai/w8-id-v3/packed/tiny-int8/manifest.json --print-swift-pins
```

`--candidate-only` can inspect an initial FP16 artifact, but it is NOT a trio isolation pass. All trio manifests must share exporter/helper/toolchain controls. Inspect actual compression coverage and runtime input/output descriptions. If a common exporter/helper was fixed after a partial build, rebuild the trio in a new directory so its controls match. Do not repeatedly reconvert full models; these are kilobyte-scale diagnostics.

## 2. Pins, staging, build and tiny native tests

Insert the tool's exact printed `"packed:format": "sha256"` lines into the `BEGIN W8_V3_PINS` block in `App/W8TinyProbe.swift`. The initially empty pins are deliberate. **Do not stop because the pin block is empty; generating/pinning the actual local AOT artifacts is your build step.** Never substitute old v2 fingerprints or accept unverified artifacts.

Stage each full manifest and its source/AOT bundles under the app's:

```text
Documents/CoreAI/W8TinyV3/packed/tiny-fp16/manifest.json
Documents/CoreAI/W8TinyV3/packed/tiny-fp16/<source .aimodel>
Documents/CoreAI/W8TinyV3/packed/tiny-fp16/aot/<compiled .aimodelc>
```

Repeat for fp8/int8. Manifest absolute host paths are reduced to the final basename by the phone probe; preserve filenames/bytes. The recursive phone fingerprint includes hidden files. Do not confuse transfer errors with export or quantization failures.

The project already includes `App/W8TinyProbe.swift` and `Tools/CoreAI/W8IdentityVerifier.swift`; no regeneration is needed for just these edits. Build the existing explicit W8 Release configuration (`MURAL_COREAI_TALK` and `MURAL_COREAI_W8`), install in place and rediscover the running bundle. A CLI/SDK typing difference is a narrow fix to make and test, not a reason to abandon the plan.

Run `--w8-tiny --w8-tiny-transport=packed`. Keep logs bounded to Mural and collect the unique run report plus `tiny-events.jsonl`. Then, after complete scope/capture teardown, use a fresh process with `--w8-tiny --w8-tiny-transport=packed --w8-tiny-reverse`. Do not delete caches. The code checks three numerical vectors at three changing challenges per load, correct named functions, exact responses and repeated hidden outputs. Required cache-hit misses are distinct from wrong-model output and must be labeled accurately.

Use the interview tool only to ask for readiness/unlock and visible completion/error at this stage. Do not request speech before machine prerequisites pass. Source-only diagnostics remain labeled source-only; they cannot substitute for native AOT/cache isolation.

## 3. Recovery instead of premature whole-task stoppage

After an error, write a short attempt-ledger row: phase, exact failure, hypothesis, smallest changed variable, predicted result, actual result, next action. Preserve failed artifacts/logs. Then classify:

**Routine and recoverable:** absent test-only dependency, wrong import/SDK spelling, generated pins, staging path, locked phone, stale report, build syntax or exporter/inspector presentation. Correct and rerun the affected check. Request only genuine user actions through the interview tool. Do not ask the user to debug code.

**Returned tiny compiler rejection:** wait for the native scope to return, collect evidence, then make a changed hypothesis in a fresh process. If packed v3 fails specifically on output/concat lowering, rebuild the small trio using `--transport split`, audit/pin it, stage under `W8TinyV3/split/tiny-{format}`, and use `--w8-tiny-transport=split`. It preserves runtime FP16 challenge checks. No automatic switching inside app inference.

If both transports fail, use the hidden-only tiny control and separately controlled compiler diagnostic described in the recovery document. At most three materially different hypotheses per failure class; ordinary typo/path/pin fixes are not counted. No repeated unchanged graph or private runtime/hash patch. Preallocated inference output buffers cannot fix an error that already happened during specialization.

**Wrong identity/numerics, warning, native abort, unsafe ownership:** quarantine that configuration and stop its inference, never feed its output to the decoder. Confirm all native work/captures drained. Do not clear a memory latch or immediately run a heavier alternative. If the phone is stable, a distinct already-safe experiment in a fresh process can proceed under the independent path below. Repeated/system-wide instability ends device testing, while offline diagnosis may continue.

**Independent productive path:** if v3 cannot safely advance in this session, qualify the already implemented `original-pal8` route using the accepted GPU encoder and the saved PAL8 decoder, separately and with both prewarm/Send decoder identity verified. Its artifacts do not use the v2/v3 marker. Keep the v1 compressed encoder guard. Label it FP16 encoder/PAL8 decoder, not BOTH-component compression. Do not wait for a vendor fix before doing this useful independent work.

## 4. After tiny success, continue through real speech

Rebuild the exact frozen merged encoder as the full v3 FP16 control, FP8 and informative INT8 control. Reuse the successful transport and pinned environment. Use `--kind encoder --model-dir <verified frozen source>`, separate new output directories and the same export/audit sequence. Do not train, alter tokenizer/frontend/greedy policy, or use a new base model.

Pin the generated full assets and add a separate v3 selection inside the existing serialized staged/probe owner. Do not enable old v1 candidates. Carry the validated URL/spec/support identity together immutably; select only while idle. Check the named function and descriptors, supply the FP16 challenge, validate and unpack the returned packet using `W8RuntimeIdentitySpec`, and pass only the original-shape owned FP16 hidden array to the existing decoder bridge. Keep the mel-hash check, correct support files and single-owner cancellation/drain rules. The packed output is not directly consumable by the old hidden-only reader.

Proceed: full encoder-only checks on multiple saved inputs -> original-encoder/PAL8 control -> v3 FP8/FP16 decoder -> strongest v3/PAL8 combination -> retained corpus -> paired human checks. Do not stop simply because a prerequisite passed. A small new quality difference calls for documenting its extent and a justified precision/configuration comparison, not silently relaxing correctness or declaring all quantization impossible. Serious speech loss quarantines the candidate.

Keep 001-016 and 018-022 scored; 017 diagnostic. Retain exact old PAL8 exceptions 006/007 and show new differences separately. No expected-text prompts, tutor repair, reference edits or use of these regression clips as training/calibration data.

## 5. User testing, measurements and final report

Use the available interview skill/tool to give ONE instruction, accept my answer, correlate bounded Mural logs, then give the next instruction. You build/install/monitor; I use the mic/UI. Do not invent an interview-tool name, do duplicate UI automation, or ask me to repeat old corpus recordings.

After machine gates: both switch directions, siêu thị, number/negation, quiet Yes/No, short Vietnamese, silence, first plus at least two warm turns, End/drain/new distinct turn and focused offline check. Explain what to do in the interview, not a giant questionnaire. Keep human-confirmed recognition/UX separate from agent-observed build/log evidence.

Measure complete Send-to-final, decoder prewarm/load/first prediction/loop, encoder native-call wall time, validation/copy/file-I/O time, token counts, current footprint, separately labeled lifetime RSS peak, warnings, thermal state and actual storage. Tiny timing is not ASR timing; one sample is not p95; source size is not RAM. Exclude the invalid v1 0.471-second FP8 result. Stop every owned log capture at completion or error.

Return the commit/local diff, attempt ledger, source/AOT/pin manifests, static/native separation outcomes, corpus comparisons, paired-user feedback and actual latency/memory observations. State exactly which of FP8 encoder, 8-bit decoder, both, or neither is qualified. State blocked/unmeasured gates without inventing passes. Recommend the next measured-bottleneck change. Do not promote normal Talk by default or launch a long soak/training/new model-family project without review.
