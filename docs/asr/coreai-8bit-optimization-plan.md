# PhoWhisper CS: evidence-led Core AI 8-bit optimization

Updated 2026-09-17 against remote `f51fb58d7653330abbfabb80eae52fa07485a1c9`.

**Status: implementation plan, not a built or measured optimization.** No model, runtime, dependency, default, or recovery behavior changes with this documentation revision. The authoring environment has neither the developer Mac nor the iPhone. Execute the [local-agent handoff](local-agent-handoff.md) for implementation and physical qualification.

## Decision and scope

Compress the current Core AI encoder as well as evaluating the existing compressed decoder. Keeping the encoder FP16 was an isolation choice, not a technical requirement. Start with **FP8 weight-only and INT8 weight-only Core AI encoder candidates**, then combine the strongest candidate with the saved **PAL8 Core ML decoder**. Keep internal activations and the encoder/decoder handoff FP16 initially.

This document supersedes the earlier decoder-only sequence, including contradictory historical instructions in the overview. It builds on the encoder plan already committed at `f51fb58`, adding a direct `.aimodel` compression route, a verified FP8/Core ML limitation, toolchain controls, and executable device gates. Existing history and failures remain evidence.

Do not switch ASR families, train a new bilingual adapter, replace the original model, or revisit an unchanged native-crashing decoder. Future small/medium/v3 training remains documented in [the adapter note](whisper-bilingual-adapters.md), but is not this experiment.

## What encoder, decoder, and precision mean

The **encoder** turns the audio's log-mel features into a time-indexed representation of speech. The **decoder** uses that representation and previously generated tokens to choose the next token repeatedly. Tokens can be pieces of words, punctuation, or control markers. Both parts influence bilingual accuracy; the decoder is not a translator or a post-hoc word replacement system.

Mural's split exporter fixes FP16 input `[1,80,3000]` and FP16 output `[1,1500,1280]`. The Swift replay bridge rearranges that same hidden representation into `[1,1280,1,1500]` for the existing Core ML decoder. Preserve shape, layout, scaling, frontend, source lineage, and meaning of features. Matching dimensions alone does NOT make unrelated encoders/decoders interchangeable.

| Term | Meaning in this experiment |
| --- | --- |
| FP16 | 16-bit floating-point representation. |
| FP8 weights | Scaled 8-bit floating-point weight representation; start with the documented E4M3FN format. |
| INT8 weights | Scaled 8-bit integer weight representation. |
| PAL8 | 8-bit indices into learned lookup tables; Mural's saved group-16 decoder is this format, not FP8. |
| W8A16 | Shorthand for 8-bit weight representation with FP16 working activations; not a claim that every tensor is compressed. |
| W8A8 | Also quantizes activations; a separate, higher-risk performance experiment. |

File precision, activation precision, interface precision, and hardware arithmetic are different properties. An FP8 asset does not prove native FP8 execution or acceleration on this iPhone. Converting its output to FP16 does not recover information already lost in quantization; actual transcripts still decide quality.

The handoff tensor contains 1,920,000 values: **3,840,000 bytes at FP16** before copies/alignment. Making that tensor 8-bit saves only 1,920,000 bytes per copy. Large weight allocations and runtime temporaries are the higher-value first target. Compatible compressed halves do not need identical internal formats.

## Verified support, with boundaries

Apple documents direct weight compression of an existing uncompressed Core AI `.aimodel`, without PyTorch, using `coreai_opt.coreai_utils.quantize_weights`. Its FP8 and INT8 APIs justify this encoder experiment [S1, S2]. **Compress the source `.aimodel`, then build a new target-specific `.aimodelc`; do not edit the compiled bundle or merely change Swift's input dtype.**

Apple also explicitly states that its FP4/FP8 weight/activation export modes are Core AI-only and do not convert through `coremltools` [S3]. Therefore an FP8 encoder plus PAL8 decoder is a realistic hybrid target; making both halves FP8 would additionally require a Core AI decoder migration. Do not include a speculative Core ML FP8 decoder in the immediate plan.

Current online documentation does not establish compatibility with Mural's older pinned `coreai-core==1.0.0b2` / `coreai-torch==0.4.1` exporter environment. Test supported APIs in an isolated, version-recorded environment. Preserve old pins and artifacts. If a newer compiler is necessary, produce an uncompressed control with that same compiler to separate compiler drift from compression error.

The accepted encoder is GPU-preferred because a different ANE-backed specialization had load failures. Keep that placement preference initially. A supported dtype is not evidence of a fast GPU kernel, actual placement, or lower energy. Core ML performance guidance is useful for hypotheses, not a benchmark of Core AI on this phone [S4, S5].

## Small, informative candidate set

| ID | Encoder | Decoder | Question |
| --- | --- | --- | --- |
| A | Accepted Core AI FP16 | Accepted Core ML FP16 | Current staged reference, not the old warning-producing eager comparator. |
| A-prime | Uncompressed graph under new toolchain, only when needed | FP16 | Did toolchain changes alter correctness/performance? |
| B | Accepted Core AI FP16 | Saved PAL8 | What does decoder compression alone change? |
| C-F | New Core AI FP8 weights / FP16 activations | FP16 | Does encoder FP8 work and preserve useful recognition? |
| C-I | New Core AI INT8 weights / FP16 activations | FP16 | Is integer compression a better encoder tradeoff? |
| D | Best qualified compressed encoder | Saved PAL8 | Does compressing both components deliver the desired overall result? |

Run encoder-only gates before C-F/C-I. Do not run all combinations indiscriminately, load alternatives together, or infer D's quality from its components in isolation. B and C isolate causes; D is the combined product candidate, not a requirement to use an identical numerical scheme.

PAL8 encoder, finer blocks, alternative decoder INT8, and activation quantization are evidence-triggered follow-ups, not an automatic sweep.

## Implementation route

### 1. Freeze and inspect

Read the identity/evidence section in [the overview](iphone17-vien-research-plan.md). Recover the saved merged model, accepted source/AOT encoder, PAL8 decoder, corpus, and existing reports. Do not ask for replacement recordings or regenerate the completed PAL4/6/8 ladder.

Inspect `Tools/CoreAI/export_phowhisper_split_coreai.py`, `PhoWhisperStagedEncoder` and private `WhisperRecognizer` in `App/LocalConversationEngine.swift`, the existing probe, and current package pins. Keep the accepted exporter unchanged.

### 2. Prefer the direct graph route

Implement a separate offline helper, for example `Tools/CoreAI/compress_phowhisper_encoder.py`, using documented installed APIs. The following is the supported API direction, not a validated command for the developer's environment:

```python
from pathlib import Path
from coreai.authoring import AIModelAsset
from coreai_opt.coreai_utils import (
    CompressionGranularity, DType, QScheme, quantize_weights,
)

asset = AIModelAsset.load(Path(source_aimodel))
compressed = quantize_weights(
    coreai_program=asset.program,
    dtype=DType.FP8_E4M3FN,  # a separate invocation tests DType.INT8
    qscheme=QScheme.SYMMETRIC,
    granularity=CompressionGranularity.PER_CHANNEL,
    weight_num_threshold=1024,
    scale_dtype=None,  # retain source precision for scales; no extra MXFP change
    in_place=False,
)
compressed.optimize()
compressed.save_asset(Path(new_aimodel))
```

The helper must reject wrong source fingerprints, existing output paths, wrong component/contracts, and undocumented format options. Add source/license metadata and report actual versions, parameters, eligible/compressed/skipped weight counts and bytes, warnings, exported compressed ops, and output fingerprints. Source models and their merged adapter must not change.

Apple's helper only selects eligible constant consumers and can skip unsupported operations with warnings [S2]. A successful return is not proof of full weight coverage. Audit it; do not label a partly unchanged asset uniformly FP8. Fake quantization or smaller dtype labels without exported compression ops are not deployment proof.

Start with per-channel FP8 and INT8 using source-precision scales, not simultaneous activation/MXFP/grouping changes. If poor error distribution warrants it, compare a bounded per-block candidate. If surgical layer exclusions are needed and the direct API cannot express them, use the documented module/op-config PyTorch path from the same frozen source. Do not invent include/exclude arguments or patch private Apple runtime internals.

### 3. Validate at the runtime actually available

First run inexpensive API/graph checks, then host numerical simulation where supported. Compare the exact same accepted mel tensor, finite values, max/mean error and cosine, then identical-prefix decoder logits/top-k and free-running transcripts. Cosine alone is not an accuracy gate.

A Mac without a supported Core AI runtime cannot execute a converted `.aimodel` merely because authoring succeeded. Use source simulation if available and report that limit. After host/static prerequisites, obtain the missing native comparison in a bounded one-fixture **encoder-only** phone probe. Do not claim simulation proved target execution or block forever on an unavailable host runtime.

Compile each surviving encoder ahead of time using the installed supported `coreai-build` invocation, matching the rediscovered architecture and GPU preference. Use immutable distinct directories and manifests; preserve all original assets/caches. Record source and compiled sizes separately.

### 4. Integrate only the narrow experiment

Keep the existing single audio/ASR owner and staged release order. Add a closed, development-only candidate selection fixed before Prepare. Pin exact manifests; do not accept arbitrary unverified paths or change the normal default. Select source/support/encoder/decoder identities together.

Both greeting-time decoder prewarm and Send-time decoder load must select the SAME decoder. Log the selected encoder and decoder identities without speech content. Maintain prewarm drain -> encoder completion/release -> decoder load/decode/unload. Native cancellation is cooperative; never clear task handles or unload an in-use model to make a button appear ready.

Preserve the FP16 bridge, replay-mel check, original 80-bin frontend, 30-second limit, tokenizer, suppression, automatic language detection, transcription task and existing greedy settings. No forced English/Vietnamese, expected-text prompts, reduced vocabulary, or tutor-based transcript repair.

## Other optimization angles and when to use them

| Angle | Next justified experiment; limitation |
| --- | --- |
| Weight precision and granularity | Compare FP8/INT8 first. Use layer error and transcripts to select per-channel/per-block or small higher-precision exceptions. Smaller blocks add scale overhead and can affect kernels. |
| Sensitive layers and outliers | Compare identical-prefix logits to locate consequential errors. Consider output projection, attention projections or norms only as hypotheses, not automatic exemptions. Outlier-preserving mixed-bit compression has Whisper research support, but its extra path needs runtime support [S6]. |
| Calibration / quantization-aware adaptation | Use rights-cleared English, Vietnamese, both switch directions and varied accents separately from evaluation. Data-free weight compression does not require acquiring a training corpus. Calibration/QAT is a later bounded decision, not training on the 21 test clips. |
| Working activations | W8A8 or FP8 activations only after W8A16 works and profiling shows a supported benefit. Quantize/dequantize overhead can offset gains; Core ML guidance particularly warns about some CPU/GPU paths [S4]. |
| Decoder representation | Reuse PAL8 first; consider an INT8 Core ML decoder if PAL8 loading/lookup behavior remains costly. Do not equate PAL8 with FP8 or repeat failed Core AI decoder graphs for format symmetry. |
| Decoder state / KV cache | Inspect the actual pinned WhisperKit cache implementation. It already has a cached decoding architecture; do not confuse it with the abandoned full-prefix diagnostic. Stateful in-place Core ML cache export could reduce copying, but needs matching loader/reset tests. The WhisperKit paper supports investigation, not proof that Mural lacks it [S6]. |
| Cold preparation / specialization | Measure verification, prewarm, cache lookup, load and first prediction independently. Keep immutable compiled assets and matching prewarm configuration. Existing `.mlmodelc` does not guarantee no target specialization. Early prewarm hides latency; it does not prove less total work. |
| Duplicate work / host overhead | Profile repeated mel work, graph recreation, large array copies, logits handling and logging. Preserve the replay identity safeguard until an equivalent verified reuse design exists. Do not optimize a millisecond copy while ignoring seconds of compilation. |
| Residency and coexistence | Stage one native model at a time and schedule nonessential tutor/meaning work away from costly loads. Retaining a decoder might save load time but is a separate memory-risk experiment after compression, not a default shortcut. |
| Shorter windows / streaming | Changing the 30-second shape is not a drop-in optimization. Original encoder attention is bidirectional; removing padding/context can change all features and the fixed decoder bridge. Published silence caching used changed masks and self-distillation. Do not implement naive incremental encoder KV caching or slice hidden states to force compatibility [S6, S9]. |
| Silence and early feedback | A conservative VAD/silence gate can avoid unnecessary inference. Test quiet Yes/No, negation and switch boundaries. This changes recognition policy and is separate from weight compression. No hard cut at a language switch. |
| Speculative decoding / pruning | Later only: a verified draft model can reduce sequential decoder calls, but adds model work/memory and needs exact verification; unstructured sparsity has no automatic kernel speedup. Neither is the immediate low-risk 8-bit path [S6]. |
| Recoverability | Replace permanent memory lockout in a separate patch only after exact native-task drain and resource release, with explicit bounded retry/admission. Preserve finalized text and typed input. Compression alone does not establish safe recovery. |

## Measurement and acceptance

Approximate latency accounting: asset checks + non-overlapped preparation + encoder + decoder setup + token loop + teardown. Approximate staged memory is app/co-resident state plus the largest active phase and retained bridge/caches, not the sum of model file sizes. Driver/runtime allocations can outlive Swift scopes; measure rather than asserting release from a nil reference.

Historical first Send-to-final was 46.87 s with encoder scope returning about 3 s after Send; warm turns were 5.54/5.84 s. These are historical observations. Under the deliberately simplified assumption that everything else stays unchanged, removing that entire three-second portion would still leave about 43.87 s. Encoder compression alone cannot explain away a decoder cold-start bottleneck.

For each configuration report source/export/AOT bytes, cache state, load/prewarm, mel/encoder/decoder/first-token/loop/teardown, full Send-to-final, warnings, thermal state and energy where actually measured. Show both time and token count so shorter/wrong output does not appear to be a kernel improvement. Compare encoder outputs and same-prefix token timings for attribution, complete transcripts for product value.

Use Release without debugger for timing; collect profiling separately. Label fresh-process/cache-retained versus warm versus genuinely new specialization. Do not delete caches to manufacture cold starts. Start with a few matched runs; report all samples, median and range, not a credible p95 from three trials. Add larger repeated-turn/thermal tests only after short gates pass. A bounded 50-100 ms footprint sampler may help but can still miss spikes; label its sampling interval. Process-lifetime RSS peak, sampled physical footprint and driver/system-model memory are not interchangeable.

Keep 21 scored historical clips separate from diagnostic 017. The user accepts the saved PAL8 changes on 006 and 007 for this trial; report them, never relabel them correct. New encoder/combination differences require human review, not silent approval or an automatic demand for perfect baseline imitation. Non-finite outputs, missing speech, new serious semantic errors, warnings, native failures or overlapping ownership stop progression. A contained quality difference can be documented for user decision. No general accuracy percentage follows from 19/21 transcript agreement.

Proposed success decision: a repeatable operational benefit in memory and/or latency, acceptable measured bilingual quality, and no observed safety/lifecycle regression. Smaller files alone do not pass. Promotion to normal Talk needs separate sign-off after held-out speech, offline/cancellation and longer thermal/reload qualification.

## Research sources and their limits

Reviewed 2026-09-17. Publisher performance claims below are not Mural/iPhone measurements.

- **S1, Apple direct Core AI graph compression:** https://apple.github.io/coreai-optimization/utils/coreai_compression.html — `.aimodel` -> compressed AIProgram, without PyTorch.
- **S2, Apple quantize_weights API:** https://apple.github.io/coreai-optimization/api/generated/coreai_opt.coreai_utils.quantize_weights.html — eligible consumers, skipped-op warnings, FP8/INT8, scales and granularity.
- **S3, Apple backend compatibility:** https://apple.github.io/coreai-optimization/introduction/integration_coreai.html — FP8 export is Core AI-only, not coremltools/Core ML.
- **S4, Core ML quantization performance:** https://apple.github.io/coremltools/docs-guides/source/opt-quantization-perf.html — hardware-dependent weight/activation tradeoffs; not a Core AI/A19 speed guarantee.
- **S5, Core ML palettization performance:** https://apple.github.io/coremltools/docs-guides/source/opt-palettization-perf.html — grouped tables and backend behavior affect latency/memory.
- **S6, WhisperKit research, July 2025:** https://arxiv.org/html/2507.10860v1 — sections 2.1 and 2.2 discuss changed-mask/self-distilled encoders, stateful decoder cache, outlier-preserving compression and speculative decoding. Benchmarks use different weights/workloads and M3-family hardware, not this bilingual adapter. Check implementation availability before assuming a paper technique is in Mural's pinned SDK.
- **S7, Hugging Face publisher INT8 encoder example:** https://huggingface.co/pappa1337/kb-whisper-small-coreml — Swedish Whisper-small Core ML encoder paired with a differently compressed GGML decoder. Expected throughput and first-load claims are not a controlled PhoWhisper benchmark.
- **S8, Hugging Face Red Hat W8A8 recipe:** https://huggingface.co/RedHatAI/whisper-large-v3-quantized.w8a8 — evidence that calibrated Whisper compression can preserve benchmark accuracy. Different checkpoint/server runtime. Do not transplant English-only calibration/forced-English decoding into Mural; inspect actual module names before any output-head exception.
- **S9, Reddit caching discussion, November 2024:** https://www.reddit.com/r/LocalLLaMA/comments/1h2kvu2/whisper_whispercppwhisperkit_for_live/ — useful question about repeated encoder work; comments disagree, so architecture conclusions above rely on S6 and source inspection, not votes.
- **S10, Reddit project-author CPU report, October 2022:** https://www.reddit.com/r/MachineLearning/comments/yeyxlo/p_openai_whisper_3x_cpu_inference_speedup/ — quantization sped up some tested model sizes and slowed another; author lacked formal WER evaluation. Useful backend-dependence warning, not an iPhone recipe.
- **S11, Apple mixed-precision and comparison utilities:** https://apple.github.io/coreai-optimization/utils/mixed_precision.html and https://apple.github.io/coreai-optimization/utils/activation_comparison.html — inspect local versions for selective diagnosis.

No public source reviewed establishes a complete, low-memory FP8 PhoWhisper Large-v2 + this VI/EN adapter benchmark on the user's ordinary iPhone 17. The bounded experiment above is designed to establish that missing evidence without replacing the model.
