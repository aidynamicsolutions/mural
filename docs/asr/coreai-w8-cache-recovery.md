# W8 v2: recover from AOT cache-identity aliasing

Date: 2026-09-17. Reviewed `mvp` head: `4e80f464551141a1a93e3eb0971efe9209323858`.

**Status: candidate remediation implemented in offline tooling and a reusable Swift verifier. Host checks passed. Apple export/AOT, the Core AI Swift extension, native cache isolation, speech quality and latency are NOT tested here. The installed v1 compressed candidates stay blocked.** This is the next execution plan; it supersedes repeating the original v1 exports. Preserve the implementation checkpoint and candidate JSON as historical evidence.

## Diagnosis from the committed evidence

Read `coreai-w8-implementation-checkpoint.md` and `coreai-w8-candidates.json` first. The local work is useful and should not be reverted wholesale:

- Both FP8 and INT8 compressed all 194 eligible encoder tensors and ran on the phone at least once with finite outputs.
- Their source `.aimodel` hashes differ. After `coreai-build 3600.83.1`, both AOT bundles have the reported same `main.hash`: `14b1d7cc210fb36aee5c885ff13c8256e0daa8e9c9e66d3e75d4f6fee7de0f8f`.
- A subsequent request for FP8 returned a cache hit and exactly the INT8 output, not the earlier FP8 output. This invalidates attribution, not all previous encoder work.
- The failure is localized to AOT identity/cache behavior. The internal Apple root cause is not established. In particular, distinct source hashes do NOT support claiming that Python merely retained the old source hash.
- The FP8 AOT bundle is 640,470,615 bytes; INT8 expanded to 1,273,955,343 bytes. These are storage facts, not RAM or speed proofs. The FP8 representation is worth pursuing first after identity is trustworthy.
- Genuine FP8 output had greater error than INT8 in one saved comparison (FP8 max/mean absolute error 17.083008/0.017781, cosine 0.998791). Finite values and high cosine do not pass transcription quality.
- No compressed-encoder decoder/corpus or combined PAL8 gate completed. The 0.471-second misattributed FP8 request is NOT a valid FP8 speed result. All other timings are single samples with unlike cache/install states and include diagnostic overhead.

The phone is now iOS 27.2 (24B5084k), not the older iOS 27.0 baseline. The user independently uninstalled Mural after a storage warning. Do not claim old history survived or request another uninstall. The restored required assets and current data must be preserved.

## First-principles remediation

A valid model-file fingerprint proves which file we selected; it does not prove which cached executable/weight resources we received. We need both storage integrity and executable identity.

`rebuild_w8_identity.py` uses a fresh `TorchConverter` and its public `entrypoint_name` parameter (present in the installed v0.4.1 source). It re-exports the exact frozen encoder, rather than copying/relabeling the v1 compiled bundle. It adds a second, observable read-only Int32 output:

- Named entrypoint includes source/configuration/exporter/toolchain identity.
- FP8, INT8 and the FP16 control have different marker output names AND shapes (8, 9, 16 Int32 values). Therefore they have intentionally different public signatures, not just different filenames or comments.
- Marker values encode the recipe digest. The speech output itself receives no additional arithmetic: same FP16 `[1,1500,1280]` values before quantization.
- Export/AOT inspection must retain this signature. `w8_identity.py` independently rehashes artifacts and rejects duplicate compiler-produced function hashes, the recorded v1 identity, altered manifests and mismatched controls.
- The Swift verifier rejects the wrong public function or marker before accepting embeddings. It does not load a model or own task scheduling.

**This is a testable workaround, not a demonstrated Apple compiler fix.** Public naming is supported; Apple does not promise that names alone control all native cache keys. The differing observable output shapes are deliberate structural separation. Native repetition and numerical evidence remain mandatory because a valid marker could coexist with incorrect internal weight-resource reuse.

No `.hash` bytes, private runtime cache paths, signing, entitlements or quantization internals are patched. No no-op multiply/add is relied on: an optimizer could erase it. No marker is used to improve a transcript. The frozen bilingual weights, mel frontend, tokenizer, decoding policy and original exports are unchanged.

## Implemented tools

- `Tools/CoreAI/w8_identity.py`: deterministic identity, signed digest marker, read-only native-hash inventory and pair audit. The new v2 fingerprint covers hidden files too; do not compare it interchangeably with the old helper which skipped them. The manifest distinguishes a hash file's SHA-256 from its native contents. The recorded v1 value is checked against both representations without assuming how the old report derived it.
- `Tools/CoreAI/rebuild_w8_identity.py`: exclusive-output tiny or encoder export, FP16/FP8/INT8, matched controls, coverage audit, public named entrypoint, retained marker, optional AOT, source immutability checks. Lazy Apple imports; `--help` is available without Core AI.
- `Tools/CoreAI/W8IdentityVerifier.swift`: reusable specification/function/marker validation. Its Core AI extension reads the marker using physical strides. It is under Tools, NOT silently linked into normal Talk; wire it into the bounded development probe locally.
- `Tools/CoreAI/test_w8_identity.py`: nine host tests, including the observed equal-key failure pattern, artifact mutation, ambiguity, malformed markers, controls, and actual PyTorch wrapper/export output preservation.
- `Tools/CoreAI/test_w8_identity_swift.py`: compiles and exercises the actual portable Swift verifier. Its pass is not an Apple/Core AI compilation claim.

The previous compressor, its pins, the old exporter, the v1 runtime stop guard and all historical reports remain untouched. This commit does not fabricate new model fingerprints or enable untested assets.

## Gate 1: small synthetic assets before another large model

Use the existing separate Python 3.11 compression environment and the exact installed pins. Do not install into the accepted exporter environment. Read command help first and record Xcode/SDK/compiler/OS versions.

```sh
python Tools/CoreAI/test_w8_identity.py
python Tools/CoreAI/test_w8_identity_swift.py

# Run one at a time; stop if any command fails. Never overwrite an output directory.
python Tools/CoreAI/rebuild_w8_identity.py --kind tiny --format fp16 --output-dir .build/coreai/w8-id-v2/tiny-fp16 --aot
python Tools/CoreAI/rebuild_w8_identity.py --kind tiny --format fp8  --output-dir .build/coreai/w8-id-v2/tiny-fp8  --aot
python Tools/CoreAI/rebuild_w8_identity.py --kind tiny --format int8 --output-dir .build/coreai/w8-id-v2/tiny-int8 --aot
python Tools/CoreAI/w8_identity.py .build/coreai/w8-id-v2/tiny-fp16/manifest.json .build/coreai/w8-id-v2/tiny-fp8/manifest.json .build/coreai/w8-id-v2/tiny-int8/manifest.json
```

The tiny graphs intentionally have different weights AND bias, not only markers. Three saved vectors (zeros, ones, a bounded ramp) expose accidentally reused arithmetic. A predeclared max absolute error 0.05 applies ONLY to these sparse synthetic outputs; expected format outputs are separated by much more. It is not a speech/logit threshold or permission to change an observed failure into a pass.

Do not advance solely because the static audit passes. Integrate a narrow loading/inference probe using these manifests with pinned artifact identities and the supplied verifier. Build/compile that native path before user interaction. No decoder, microphone, TTS, tutor or personal data is required for the tiny gate.

Run FP8 -> INT8 -> FP8 -> INT8 sequentially in one bounded probe with all native function scopes fully returned between models. Then use a fresh process and reverse the order; repeat a cache-hit-required load. Keep caches and files intact. Validate expected entrypoint, output names/shapes, marker and the three numerical vectors on EVERY run. Preserve exact output digests and compare repeated identical inputs; report instability rather than automatically loosening tolerance. Correlate cache hit/miss, loaded model identity, input digest and numerical output. At most one active native inference owner. A failure ends that candidate sequence.

If current compiler output is still aliased, stop the large-model path. A bounded tiny comparison using the source `.aimodel` with explicit specialization can help isolate AOT lowering from runtime lookup, but is not an uncached workaround or a product latency solution. A newer supported compiler is a separate changed-toolchain experiment with its own FP16 control. Do not blindly upgrade everything. Preserve a minimal synthetic vendor reproducer; no user audio or multi-GB weights are necessary. Do not edit native hash files or delete the implicated cache to manufacture a pass.

## Gate 2: rebuild the frozen encoder, not a new model

Only after Gate 1 native isolation passes, run the same exporter with `--kind encoder --model-dir <verified-frozen-merged-directory>` for FP16, FP8 and INT8, each into a new directory, using `--aot` and the actual h18p device. The script verifies `model.safetensors` SHA-256 `264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a` and the original 80-mel/1280-width/32-layer/51865-vocabulary configuration. It keeps only encoder ownership after loading the frozen model to avoid unnecessarily retaining decoder weights on the host.

A fresh uncompressed control is required even with the same compiler: this is a changed export wrapper/path. Compare it with the original accepted encoder on saved mel inputs. Do not silently label a changed reference as equivalent. The host sine fixture is only a wrapper/capture check, not bilingual validation. No native macOS execution is required or claimed on the unsupported host OS.

Repeat the pair audit, inspect actual AOT sizes and compression operations, then run one-fixture encoder-only on the phone. Repeat relevant identity checks with full assets: small-test success cannot establish large-model resource isolation. Compare original/FP16-v2/FP8-v2/INT8-v2 hidden outputs on several distinct recorded mel inputs; preserve actual errors and hashes. Never infer quality solely from cosine or compensate with expected-text prompts.

## Exact local integration points

The new identity ABI is intentional. Do not weaken the old `main` checks globally.

1. Add the verifier to the development probe target using the repository's source/project-generation process, preserving signing overrides. Inspect the generated diff; no unrelated package or language-mode changes.
2. Keep `CompressionCandidate.resolve()` rejecting all old fp8/int8 v1 artifacts. Add a separate v2 specification only AFTER actual new hashes and the static gate exist. Pin entrypoint, input/output contracts, recipe digest, marker, AOT fingerprint and support manifest together. Do not accept an arbitrary runtime URL or unverified manifest as a product model.
3. `CoreAIPhoWhisper.loadAsset`, its descriptor helpers and staged encoder paths currently assume `main`. Add an explicitly named v2 path that calls `spec.requireModel(model)` BEFORE `loadFunction(named: spec.entrypoint)`. Missing name is a hard failure, never a fallback to main or the original model.
4. Require returned Int32 marker validation before copying/handing out `encoder_hidden_states`. Then validate finite FP16 `[1,1500,1280]` and use the existing stride-correct bridge. Match the marker output descriptor too where the SDK exposes it. The source inspector and returned-array verifier are not a substitute for each other.
5. Keep the existing owner, generation checks, warning guard, cancellation drain and sequential encoder-before-decoder lifetime. Do not unload native functions in flight, make a timeout falsely clear busy state, or admit overlapping A/B operations.
6. For Talk, resolve the v2 specification once per prepared owner, not from changing external preferences during a turn. Both greeting prewarm and Send load must use the same decoder. Keep normal Release/default routing unchanged until qualification and explicit promotion.

`W8IdentityVerifier.swift` is not a manifest authentication system: the caller must hash/pin the complete manifest and artifact. Its marker is diagnostic, not a guarantee that the entire cached neural body is correct. That is why numeric replay, ordering tests and actual transcripts are independent gates.

## Gate 3: quality and the latency improvement

After trusted full-encoder loading, resume the original planned combinations: original encoder + PAL8 control; compressed encoder + FP16 decoder; best compressed encoder + PAL8 decoder. Preserve the 21 scored WAVs and diagnostic 017. The existing PAL8 006/007 exceptions remain accepted for a bounded trial, not for arbitrary new encoder regressions. Report raw/normalized differences against human references and the correct baseline, including both switching directions and short answers. No new training, Qwen, Parakeet or stateful Core AI decoder migration.

Once corpus quality is acceptable, use the interview workflow for live speech. Measure first Send-to-final, decoder prewarm/load, native encoder run separated from dump/copy time, decoder first prediction/loop, token count, physical footprint samples, lifetime RSS peak, warnings, storage and thermal state. Matched repeated Release samples are necessary; do not reuse the aliased v1 0.471s figure. Stop tensor dumps during timing trials or report their overhead separately. Prewarm may hide latency without reducing total work; measure both.

The observed historical cold stall was largely decoder preparation. Correct FP8 identity is an enabling fix, not itself a promised latency reduction. The saved PAL8 decoder is the next supported lever after identity/quality. INT8's AOT expansion currently weakens its storage case but does not by itself establish runtime performance. Retain FP8 as the first full candidate, and use INT8 as an informative comparator, not an automatic winner from lower hidden error.

## Source and evidence map

- Local report: `docs/asr/coreai-w8-implementation-checkpoint.md` at reviewed head; full device tensors/logs remain in the user's `.build/verification/coreai-w8-20260917/`.
- Public converter parameter (reviewed v0.4.1): https://github.com/apple/coreai-torch/blob/v0.4.1/coreai_torch/converter.py ; API description: https://github.com/apple/coreai-torch/blob/799d990deb85af350aa6a4aa23c85f211f2207ad/docs/api/TorchConverter.md
- Public quantizer source: https://github.com/apple/coreai-optimization/blob/71258d9e425decd7c57b8fe50335ff05577891f6/src/coreai_opt/coreai_utils/passes/weight_quantization.py . This does not document the proprietary AOT/cache hash algorithm.
- Cache and specialization semantics: https://developer.apple.com/documentation/coreai/managing-model-specialization-and-caching
- Model function inspection/lifetime: https://developer.apple.com/documentation/coreai/aimodel
- AOT still requires device specialization: https://developer.apple.com/documentation/coreai/compiling-core-ai-models-ahead-of-time

No exact vendor-confirmed fix for this reported FP8/INT8 AOT collision was found in the reviewed public material. This commit instead provides a bounded, testable isolation workaround and guards against false performance claims.

## Verification performed by the remote agent

Linux host: Python 3.13 / PyTorch 2.10.0 CPU, not the production conversion environment. Nine Python tests passed, including exported-wrapper replay. The actual portable Swift guard compiled and rejected wrong identities. Python syntax and CLI help checks passed. No Core AI authoring package, Apple compiler, Xcode build, original corpus/weights or iPhone was available. Native Swift extension and the entire conversion/AOT/device sequence remain local gates, not remote passes.
