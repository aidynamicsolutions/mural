# Is there a smaller FireRed model than Mural currently uses?

Review date: 28 September 2026. Mural anchor: `mvp` at `a73d8163355fb2137d552196677c1b722840d9df`, also the branch head returned during this review.

## Decision

**The AED described in the user's quotation is already Mural's model family.** It is smaller than the 8B+ LLM, not a newly discovered smaller alternative to the installed AED. The installed package is additionally INT8. Renaming/reinstalling the same AED cannot remove weights, sessions or workspace. The unquantized official checkpoint would not be a memory-reduction substitution.

There is a separate, materially smaller **CTC-only export derived from FireRedASR2-AED**. This is worth one host quality comparison because it can use the existing sherpa/ORT CPU stack. It is not equivalent to retaining AED recognition quality. Do not replace the app default before that comparison.

The native memory STOP remains valid. The latest warning preceded decode; much of the footprint returned after teardown, but the cause is not established. Neither a leak nor another app's responsibility is proved. Do not dismiss warnings, invent a safe process limit, reduce safety coverage or retry unchanged models to seek a pass. [Mural handoff][handoff]; [Apple warning guidance][apple].

## Findings and confidence

| Candidate | What is established | Decision |
|---|---|---|
| Official FireRedASR2-AED | The official report distinguishes AED (1B+) from LLM (8B+). Mural's pin already names AED and its released INT8 graphs. | No model-family swap. |
| Same AED unquantized checkpoint | Mural's reviewed source checkpoint is 4,731,558,506 bytes; installed ONNX package is 1,234,657,933 bytes. Different formats/payloads, not equivalent RAM metrics. | Not an optimization. |
| sherpa FireRedASR2 CTC INT8 | Maintainer documentation lists a single approximately 740 MiB graph and explicitly excludes the attention decoder. Actual byte counts/hashes not obtained here. | Host-only candidate, then decide whether quality justifies integration. |
| OpenASR AED Q4 | Community card lists 1.06 GB `.oasr`, 1.27 GB reported peak, but Q4 latency and transcript-drift entries are `n/a`. | Interesting alternate-runtime lead, not verified iPhone evidence. |
| CrispASR GGUF Q4 | Community card advertises 919 MB and explicitly describes CTC decoding despite AED in the title. | Not proof of preserved AED decoding; not a drop-in ONNX package. |
| MLX Swift FireRed | Swift package declares iOS support. Inspected loader/default generation is not an established smaller quantized equivalent. | Separate runtime/quality project, not initial swap. |

Mural's exact installed file identities remain unchanged:

- `encoder.int8.onnx`: 817,286,833 bytes; SHA-256 `54048d66b6e8f3c80ea7ce95efe794587b0fd81d7271651d0decd3803852ae82`.
- `decoder.int8.onnx`: 417,291,928 bytes; SHA-256 `b840ce7196ae4a14d05ae84bbf56082b6b61ccec5610fda907dddbcea37354ff`.
- `tokens.txt`: 79,172 bytes; SHA-256 `1bc613de2112d257e61a349c3e72d1b1a9cf19c33d3ca954197ad2171e5ea07b`.

These are from the [actual repository pin][pin], not an inference from model naming. Managed activation and native qualification are separate states.

## Why CTC is a reasonable discriminator, not an automatic recommendation

The pinned CTC loader constructs **one ORT session** from `config.fire_red_asr_ctc.model`; the AED path uses encoder and autoregressive decoder sessions. CTC does not need that attention decoder's model residency and token-by-token self/cross-attention cache execution. This gives a causal change relevant to a warning before decode: some live model resources no longer exist. It is stronger than hoping a new filename reduces memory. [Pinned CTC implementation][ctc-source].

The approximate serialized-size reduction is on the order of one third versus the current two-graph package, based on the published rounded listing. It is not an expected percentage drop in Mach footprint. Encoder live activations, allocator/prepack effects, recording, VAD, tutor, voice, OS accounting and load transients remain. A CTC candidate may still warn.

**Quality is the primary risk.** Removing the attention decoder changes how acoustic evidence becomes a transcript; the positive native-Mandarin feedback applies to the existing AED system. Code-switches, short replies, proper names and numbers can behave differently. A matching output on one clip, or a benchmark quoted for the parent AED, does not establish CTC accuracy. Keep raw recognition output and existing scoring rules; never repair the text.

**Runtime support:** sherpa 1.13.8 at `a5b4a944c5186a68bcdc0ac3011e4c541781ac84` contains the CTC implementation, Python factory example and C API `SherpaOnnxOfflineFireRedAsrCtcModelConfig`. The C API exposes `model_config.fire_red_asr_ctc.model`; only that model-family subconfiguration should be populated. This requires neither a new custom decoder nor a switch to Core ML/vLLM. Actual iOS static-library linkage and the release graph's ORT 1.28.2 operator coverage still need verification. Source availability alone is not binary/runtime qualification. [C API][c-api]; [Python example][ctc-example].

The loader requires graph metadata `model_type=fire-red-asr-2-ctc`, normalization metadata and valid vocabulary/output shapes. It can terminate the process on invalid metadata, so do the local ONNX metadata/operator inspection **before** allowing native construction. The supplied pin verifier checks bytes, not graph semantics.

Expected tradeoffs remain hypotheses: fewer resident weights and no autoregressive decoder may improve preparation/decoding, but quality may regress. A lower inference burden may help heat/energy, but device measurements are required. This is an offline turn recognizer proposal, not a claim of native streaming.

## Lower-bit community leads: what they do and do not establish

OpenASR uses a GGUF-backed `.oasr` container and a different runtime, describing mmap and reusable graph buffers. Its memory figure is an author's isolated-process measurement, not Mural on iPhone. The model card's Q4 quality/latency gaps prevent adopting its marketing description as evidence of matched quality. A future investigation must pin the actual artifact/runtime revisions and demonstrate iOS loading, inference, memory, cancellation and quality. [OpenASR card][openasr].

CrispASR's card explicitly says CTC decoding; the AED name is insufficient to infer attention-decoder preservation. The card's claimed identical test output has insufficient corpus/phone coverage for this product. [CrispASR card][crisp].

At MLXAudio Swift commit `01dec7c9bdce3088a6b6b7ab9f2e403458195efb`, the package targets iOS 17+, but the inspected FireRed loader directly loads/sanitizes tensors without a quantized-module conversion step. Default generation uses beam 3 rather than Mural's greedy configuration. Its referenced HF checkpoint listing is approximately 4.57 GB. Therefore neither “MLX” nor “iOS target” establishes smaller resident memory or AED-equivalent behavior. [Package][mlx-package]; [loader][mlx-loader]; [checkpoint][mlx-weights].

vLLM does implement FireRedASR2, but framework/model support does not establish every advertised AWQ/GPTQ artifact or compatibility with Mural's native iOS path. Even a hypothetical 8-billion-weight model stored entirely at four bits requires 4 billion bytes for raw weight bits alone, before scales and runtime state. That is not a smaller starting point than the current 1.235 GB disk package. [vLLM implementation][vllm]; [official report][paper].

Hugging Face provided concrete leads. Searches of Reddit/LocalLLaMA and speech-related forums did not produce a reproducible physical-iPhone FireRed result usable for qualification. No specific forum named “Vara Speech” was identified confidently. This is a search limitation, not a claim that no community experiment exists.

## Implementation delivered, and what remains

Patch 01 extends **the existing** `Tools/ChineseASR/run_reference.py` with explicit `firered-ctc-onnx`. `firered-onnx` remains AED. It adds a host-only verifier/factory and a deliberately non-runnable pin template. CTC requires independently reviewed manifest and artifact hashes, CPU/one-thread/greedy configuration, and the named sherpa version. The CLI refuses missing pin identity, cross-backend pin arguments and an invented export `--revision` for the CTC archive. The report identifies actual pinned bytes rather than claiming a reproducible producer revision.

The new backend does not download, extract, convert, activate, change managed assets, link a new app backend, rewrite transcripts or fall back to AED. It shares the established corpus/audio/report path. It preserves the native synchronous lifetime through each decode. The version check does **not** independently verify linked ORT provenance; the local build receipt remains required. A 30-second input bound is not a native-call watchdog.

Patch 02 records this decision and the local handover. There is **no app model switch patch**, because the newly identified CTC package has not yet passed artifact/quality gates and no direct-file managed download identity was established here. Claiming a ready-to-build model swap would bypass the existing managed package safety contract.

Next local implementation paths, after host success: `Core/SpeechPackage.swift`, `Core/SpeechPackageCatalog.swift`, `App/FireRedEnglishRecognizer.swift`, `scripts/generate_project.py` and the existing device runner/test identities. Use a distinct compile-gated research variant and package ID; preserve baseline. Do not feed the archive URL to a downloader expecting raw ONNX. Resolve reviewed immutable direct-file sources, or separately review the required acquisition change before phone activation.

See `firered-smaller-model-handover.md` for the complete sequence, rollback and bounded device gate. No remote branch, model package or phone was modified by this review.

[handoff]: https://github.com/aidynamicsolutions/mural/blob/a73d8163355fb2137d552196677c1b722840d9df/docs/asr/chinese/firered-memory-research-handoff.md
[pin]: https://github.com/aidynamicsolutions/mural/blob/a73d8163355fb2137d552196677c1b722840d9df/Tools/ChineseASR/FireRedProbe/pin.json
[paper]: https://arxiv.org/abs/2603.10420v1
[apple]: https://developer.apple.com/documentation/xcode/responding-to-low-memory-warnings
[ctc-source]: https://github.com/k2-fsa/sherpa-onnx/blob/a5b4a944c5186a68bcdc0ac3011e4c541781ac84/sherpa-onnx/csrc/offline-fire-red-asr-ctc-model.cc
[c-api]: https://github.com/k2-fsa/sherpa-onnx/blob/a5b4a944c5186a68bcdc0ac3011e4c541781ac84/sherpa-onnx/c-api/c-api.h#L932-L941
[ctc-example]: https://github.com/k2-fsa/sherpa-onnx/blob/a5b4a944c5186a68bcdc0ac3011e4c541781ac84/python-api-examples/offline-fire-red-asr-ctc-decode-files.py
[openasr]: https://huggingface.co/OpenASR/firered-aed-l-v2
[crisp]: https://huggingface.co/cstr/firered-asr2-aed-GGUF
[mlx-package]: https://github.com/Blaizzy/mlx-audio-swift/blob/01dec7c9bdce3088a6b6b7ab9f2e403458195efb/Package.swift
[mlx-loader]: https://github.com/Blaizzy/mlx-audio-swift/blob/01dec7c9bdce3088a6b6b7ab9f2e403458195efb/Sources/MLXAudioSTT/Models/FireRedASR2/FireRedASR2Model.swift
[mlx-weights]: https://huggingface.co/mlx-community/FireRedASR2-AED-mlx/tree/main
[vllm]: https://docs.vllm.ai/en/v0.18.1/api/vllm/model_executor/models/fireredasr2/

Published rounded CTC/AED file listings (moving documentation, not artifact pins):
https://csukuangfj.github.io/sherpa/onnx/FireRedAsr/pretrained.html
