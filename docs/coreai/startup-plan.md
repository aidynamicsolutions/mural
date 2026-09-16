# PhoWhisper Core AI startup investigation and proposed plan

Status: both bounded checkpoints completed, execution blocked. See the [full-prefix diagnostic result](decoder-diagnostic-checkpoint.md) and the [stateful result](stateful-decoder-checkpoint.md). The separately approved stateful one-token candidate passes Mac PyTorch checks but aborts on its first phone inference. Stopped for review; no fixture transcript, full-corpus run or production integration. The [stateful handoff](stateful-decoder-handoff.md) and [original incoming handoff](decoder-diagnostic-handoff.md) are historical; later gates remain in force.
Reviewed: `8e80058`, `865c374`, `cedc4a6`, and the relevant `c3e6b1b` changes.
Source checkout: `cedc4a6dc918bb561e763edfd10d66e7c3835165`.

## Recommendation

Continue Core AI, but treat the next milestone as **a correct, executable decoder**, not another loading benchmark. AOT has demonstrated a substantial reduction in model/function loading cost. It has not demonstrated a 12-15 second usable recognizer.

The likely production design is the existing accepted frontend/tokenizer, a Core AI encoder, and a bounded, fixed-shape Core AI decoder with KV state. Keep the exact merged FP16 weights. Keep WhisperKit/Core ML as the working path until the replacement passes transcript, latency, resource, and lifecycle gates.

The bounded diagnostic checkpoint below is approved. Stop at its evidence/review gate; do not automatically advance to production integration.

## What the commits actually establish

| Checkpoint | Evidence | Limit |
| --- | --- | --- |
| `8e80058`: monolithic export/AOT loading | Three controlled cache misses: 11.734, 12.314, 14.816 s. Three cache hits: 5.349, 5.597, 5.784 s. | Stops after `loadFunction("main")`; no inference. Cache-cold is not proof of a freshly rebooted device or cold filesystem. |
| `865c374`: split encoder/full-prefix decoder | Reuses the accepted 80-mel model and PhoWhisper tokenizer; introduces a corpus runner. | Different graph/lifetimes from the monolithic loading experiment; its timing must be measured separately. |
| `cedc4a6`: mel fix and sequential/process-isolated tests | Encoder output finite, FP16 handoff bit-exact. Cached encoder load 1.382 s; execution/copy 0.697 s for fixture 001. | Finite output and a lossless copy do not establish encoder numerical parity. |
| Latest decoder-only phone run | Language detection returns token 50278 in 12.878 s, then a subsequent ANE request aborts. | No completed transcript. Exact failing decoder prefix length is not logged. Language token not independently validated. |
| `c3e6b1b` | Conversation controls/session lifecycle changes. The ASR-engine diff changes a diagnostic label. | Does not fix or introduce the historical model-specialization cost. |

The committed [sequential report](sequential-loading-checkpoint/report.md) establishes **zero completed fixtures**, not 22 failed transcript comparisons. It also rules out encoder/decoder co-residency as the sole cause.

Earlier local evidence in `.build/verification/coreai-mel-fix/report.md` is important:

- Default execution produced an ANE allocation failure.
- GPU-preferred AOT with default runtime options still entered ANE and failed.
- GPU-preferred runtime plus a frequent-reshape decoder aborted during resource allocation at preparation.
- Those changes were removed and the original pair restored. Do not repeat them as an untried fix.

## First-principles diagnosis

### Startup work and speech work are different budgets

```text
prepare = asset verification + specialization + function/weight loading
first transcript = prepare + deferred runtime setup + mel + encoder
                 + language detection + token generation
```

The historical 215.2 s report breaks down into approximately 2.85 s verification, 205.98 s prewarm, and 6.33 s load/tokenizer. The bottleneck is overwhelmingly in prewarming, not microphone capture, tokenization, or UI controls. The exact encoder/decoder split of that ANE-capable run is not established.

WhisperKit prewarming loads and discards each Core ML model to trigger specialization with lower peak memory. The subsequent load benefits from that work. Removing the prewarm call does not eliminate required specialization; it can move the cost and change peak memory. See `App/LocalConversationEngine.swift:507-552` and the pinned [WhisperKit loading implementation](https://github.com/argmaxinc/argmax-oss-swift/blob/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d/Sources/WhisperKit/Core/Models.swift#L12-L30).

Apple documents that AOT moves expensive compilation to the Mac, while leaving some on-device specialization. That is a sound mechanism for the observed loading improvement, not just hiding a spinner.

### The current decoder is a diagnostic graph, not an efficient speech runtime

`Tools/CoreAI/export_phowhisper_split_coreai.py:61-75,210-226` exports `use_cache=False` with prefix length 1 through 448. Every token recomputes the prefix, including cross-attention work. It also projects logits for every prefix position, though the app only consumes the last row.

`App/MuralApp.swift:291-315,337-355,393-411` runs length 1 for language detection, then length 4 and growing prefixes, with default specialization options. Apple explicitly documents extra per-shape optimization under the default dynamic-shape policy.

This gives two related hypotheses, not a proven root cause:

1. **Shape-dependent compilation/execution or resource allocation:** length changes select new paths or allocations that fail in the ANE/MPSGraph runtime.
2. **Export/runtime correctness or resource defect independent of the transition:** a multi-token graph could fail even when it is the first invocation.

A fresh decoder-only crash makes 'just unload the encoder' insufficient. A SIGABRT is not a Swift error that a production `catch` can recover from. More retries or an automatic in-process fallback are not a solution to this crash.

Apple's own current [legacy Whisper runner](https://github.com/apple/coreai-models/blob/7359dbcf6c3babb4fbfadfd015ffcc1cb6d87420/swift/Sources/Tools/speech-recognizer/SpeechRecognizerMain.swift#L295-L314) notes that its monolithic FP16/FP32 export decodes incorrectly on the default compute path and uses a CPU preference. This is relevant corroboration, not proof that Mural has the same defect or that CPU is an acceptable product backend.

### Quality must be proven independently of unchanged weights

Changing graph decomposition, attention kernels, device placement, or accumulation order can change FP16 logits enough to change greedy token selection. Same weights are necessary, not sufficient.

The new handwritten decode loop also does not literally reproduce all pinned WhisperKit behavior:

- The probe suppresses all in-range IDs from `generation_config.json`; pinned WhisperKit's [filter construction](https://github.com/argmaxinc/argmax-oss-swift/blob/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d/Sources/WhisperKit/Core/TextDecoder.swift#L872-L915) filters this list to IDs below `specialTokenBegin`.
- The probe defaults to 224 new tokens with a 448-token context bound. Pinned WhisperKit has a 224-token internal context constant and different loop/termination conditions. Equal nominal '224' settings do not establish equal stopping behavior.
- The exporter leaves attention implementation selection implicit, whereas the original Python benchmark explicitly uses eager attention. Record the actual resolved implementation and compare it before attributing drift to Core AI alone.
- `App/MuralApp.swift:438-470` can silently skip a NaN or choose positive infinity in `argmax`. It does not enforce the documented finite-logit gate.

These are parity risks, not explanations for the native crash. Resolve them in the probe before accepting it as an oracle.

## Proposed checkpoints

### 1. Bounded decoder diagnosis and trustworthy comparison

Scope: the development probe/export tools only. Normal Talk stays on WhisperKit.

1. Freeze source, support assets, fixtures, baseline outputs, resolved Python package versions/attention implementation, AOT options, Xcode/Metal toolchain, iOS build, architecture, and artifact hashes. Reuse the existing merged weights with SHA-256 `264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a`; do not merge again.
2. Use the accepted WhisperKit outputs as the behavioral baseline and the frozen PyTorch model as the numerical reference. Audit language detection, control-token order, suppression, EOS, and token limits against the actual pinned code, not just prose descriptions.
3. Extend the existing one-fixture/checkpoint probe to persist run identity and before/after markers for each decoder call: prefix length, cache policy/options, elapsed time, output shape/type, finite checks, and memory. Bind checkpoints to audio/model hashes, not only filename and sample count. Preserve reports per run so an aborted run cannot be mistaken for an earlier result.
4. Reuse fixture 001's encoder checkpoint. Test a small discriminating matrix: repeated length 1, length 4 first in a fresh process, and length 1 followed by length 4. Stop each variant at its first failure. This distinguishes repeated-call resource behavior from a shape transition or an inherently failing multi-token graph.
5. If necessary, compare one or two decoder steps using documented `.cpuOnly` specialization of the source `.aimodel`, with a finite diagnostic time budget. Compare identical hidden states and teacher-forced tokens to PyTorch. CPU is a diagnostic control, not the proposed shipping solution. This Mac runs macOS 26.6.2, so Core AI Swift runtime checks require the iOS 27 phone or a separate supported host, not an assumed Mac execution path.
6. Only if the results implicate dynamic shape handling, export fixed-length 1 and 4 diagnostic functions with unchanged FP16 weights. Compile only the test architecture and compare outputs. Do not create hundreds of per-prefix assets or perform an unrestricted backend/export sweep.

Use raw finite logits, top candidates, and winner margins to locate the first divergence. For end-to-end drift, compare in order: accepted mel, encoder output, language logits, teacher-forced decoder logits, generated tokens, and detokenization. Compare tensors using identical inputs; comparing different mel frontends would confound the result.

**Deliverable:** one evidence-backed cause category and either a completed first fixture or a minimal isolated failing decoder invocation. No full-corpus run until the first fixture completes. If a toolchain/runtime defect remains, preserve a minimal reproducer and request review before an OS/toolchain change or external bug submission.

**Stop gate:** one bounded run per diagnostic variant; no repeated launch of an unchanged crashing configuration. Swift cancellation must not be presented as a guarantee that an in-flight driver operation can be interrupted.

### 2. Establish full transcript parity

If the full-prefix path becomes executable, use it to run the frozen corpus before optimizing. Required: **22/22 normalized matches**, raw text differences retained, all relevant raw outputs finite, and no crash.

The frozen replay covers 21 scored scripted recordings plus diagnostic 017. It does **not** contain isolated Yes, No, or silence. Preserve that distinction and use separately identified regression checks for those cases. Keep the existing normalization: NFC, case, punctuation, and whitespace only; Vietnamese accents and lexical content remain significant. Do not change normalization, thresholds, expected prompts, or output text to manufacture a pass.

If the full-prefix graph is intrinsically blocked on the phone, do not make its success an endless prerequisite. Return for approval to validate the fixed-step candidate directly against the accepted reference, first with teacher-forced steps and then the same 22-file corpus. This changes the engineering sequence, not the quality gate.

### 3. Build the production-shaped Core AI decoder

Use fixed-shape one-token execution with position/mask inputs and bounded KV state. Process the standard control prefix through the same step function; a separate large prefill engine is unnecessary for four control tokens.

- Preserve the exact FP16 model, 80-mel frontend, local tokenizer and accepted decoding policy.
- Cache decoder self-attention keys/values and, where supported, the encoder cross-attention projections rather than recomputing them every token.
- Keep dimensions stable across steps, including masks and cache storage. A growing position-ID array would reintroduce dynamic shapes.
- Return only the logits needed for the next token. Use native Core AI state/output buffers; do not copy whole caches through Swift on every token.
- Feed each prefix token exactly once, consume the last prefix step's logits for the first generated token, and handle language detection without contaminating or duplicating decoder state.
- Reset all per-turn state on a new recording and after cancellation. Reuse loaded functions during an active conversation; the current load/unload-per-fixture sequencing is diagnostic only.
- Reuse existing library primitives where they fit, but do not adopt Apple's stock CoreAISpeech pipeline wholesale: its default frontend/control tokens target Large-v3, not this accepted Large-v2-derived model.

KV caching is reuse of mathematically repeated work, not quantization or a new acoustic model. It still requires numerical and transcript verification. With 32 layers and width 1280, full FP16 self/cross caches at 448/1500 positions are roughly 319 MB before runtime overhead. Memory success must be measured, not assumed.

Repeat the complete parity gate after this change. If compiler/runtime behavior remains unsafe, do not integrate it into Talk.

### 4. Validate actual startup UX, then integrate

Measure the **final split/stateful artifact**, not the earlier monolithic artifact:

- Three explicitly verified specialization-cache misses and three fresh-process cache hits; report every sample, median, and range, not an unsupported p95.
- Separate asset verification, specialization, function load, first encoder/decoder execution, first complete transcript, and subsequent turn latency.
- Proposed objectives for review: approximately <=15 s cold ASR readiness with assets already installed, approximately <=6 s cached readiness, and no material first/warm transcription regression against matched-waveform WhisperKit measurements. These are targets, not established results.
- Count any representative warmup inside preparation. A fast Ready label followed by a long first Send does not meet the objective. Keep model download time separate and visible.
- Measure peak memory and thermal behavior through preparation and repeated turns, including coexistence with the local tutor/TTS. No crash, Jetsam, or stale output is acceptable.
- Recheck offline relaunch, Stop during preparation/decoding, background/foreground resume of the same conversation, and a new turn after cancellation. Retain the lifecycle behavior from `c3e6b1b`.
- Only then connect the validated runtime to `LocalConversationEngine`, keeping its single-owner/cancellation discipline. Preserve the installed bundle and learning data. Engineer builds/installs; user performs live speech/listening acceptance.

Use architecture-matching AOT assets and matching compile/runtime specialization options. Retain a recoverable local source/AOT asset for offline cache invalidation; `.persistent` does not make OS-version invalidation impossible. Do not rely on prewarming earlier in onboarding as the primary fix.

## Contingency: Core AI encoder + existing WhisperKit decoder

This is technically plausible using the existing `WhisperKitConfig.audioEncoder` / `AudioEncoding` injection point. Convert the Core AI `[1,1500,1280]` output to the accepted decoder's `[1,1280,1,1500]` layout and keep the existing tokenizer/sampling path. It provides a useful encoder-parity isolation experiment without a WhisperKit fork.

It is **not a promised 15-second solution**. The historical GPU-encoder phone trace includes 34.319 s of Core ML decoder prewarming by itself. That is not a new cold measurement, but it shows why replacing only the encoder might leave a substantial first-use cost. Use the hybrid as a separately measured fallback if full Core AI is blocked, not as an assumed equivalent result.

## Out of scope

No quantization, palettization, new model, LoRA remerge, VAD/silence fix, transcript replacement, production provider framework, new dependency, background compute entitlement, hosting rollout, or automatic retry after a native abort. Known baseline recognition errors remain accepted errors, not opportunities to silently change behavior during runtime migration.

## Sources and verification performed for this review

- Committed [loading handoff](../../coreai_asr_handoff.md), [latest report](sequential-loading-checkpoint/report.md), and [earlier-attempt summary](sequential-loading-checkpoint/README.md).
- Local original JSONs under `.build/verification/coreai-load-probe/`; failure reports under `.build/verification/coreai-mel-fix/` and `.build/verification/coreai-sequential/`; `.build/coreai/frozen-source-replay.json`.
- Historical phone component timings: `.build/verification/local-mvp-phase-2/phowhisper/fp16-gpu-profile-v1/recovered-asr.log` and `mvp_plan.md`.
- Apple: [AOT compilation](https://developer.apple.com/documentation/coreai/compiling-core-ai-models-ahead-of-time), [specialization/caching and variable shapes](https://developer.apple.com/documentation/coreai/managing-model-specialization-and-caching), [compute preference semantics](https://developer.apple.com/documentation/coreai/specializationoptions/init(preferredcomputeunitkind:)). GPU preference is not a GPU-only restriction.
- Apple [iOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes) list fixes affecting dynamic-shape inference, specialization caching, and older AOT artifacts. They do not identify this exact crash; record/test exact toolchain/OS pairs rather than assume an upgrade fixes it.

During this review, the existing mel-reader check passed; AOT shell syntax checks and `git diff --check` passed. Existing artifact reports and library source were inspected. No fresh phone inference, model export, app build/install, cache deletion, or production source change was performed. This document is the only intended repository change.
