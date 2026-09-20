# FireRed development probe: provenance and notices

No weights, recordings, compiled libraries, signing material, or full inference
logs are committed. The adapted C API example's license is retained in
[LICENSE-APACHE](LICENSE-APACHE). This is a local evaluation, not a model/runtime redistribution
approval. Preserve upstream license texts and applicable notices in any future
binary/source distribution, and resolve audio rights separately.

| Component | Inspected provenance | License/notice |
|---|---|---|
| Official FireRedASR2-AED checkpoint | Hugging Face `FireRedTeam/FireRedASR2-AED`, revision `2304afed56eacfee6256dee5937ed22ffa0b64ec` | Model card explicitly declares Apache-2.0. Snapshot has no separate LICENSE/NOTICE file. This conclusion is not inferred solely from the code license. |
| Official AED inference | `FireRedTeam/FireRedASR2S`, `4e7d9aaf4482a47cec1724807026b9b151926eb5` | Apache-2.0; Copyright 2026 Xiaohongshu; retain source notices. Only AED instantiated, not the system pipeline or LLM. |
| AED ONNX conversion recipe | `csukuangfj/FireRedASR2S`, `5febe49b840d976a52aaa8e50d5f49df14e550e8`, `fireredasr2s/fireredasr2/export_aed_onnx.py` | Apache-2.0 repository license; Copyright 2026 Fangjun Kuang (Xiaomi Corp.). |
| Released INT8 package | sherpa `asr-models` asset `sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26.tar.bz2` | README attributes the official ModelScope FireRedASR2-AED checkpoint. No separate license/notice bundled. Retain official model license and conversion attribution; resolve redistribution packaging before shipping. |
| sherpa-onnx | `a5b4a944c5186a68bcdc0ac3011e4c541781ac84` (1.13.8) | Apache-2.0; C API example Copyright 2025 Xiaomi Corporation. `Probe.mm` follows its API/ownership sequence, adding validation, UIKit lifecycle, repeated replay, and metrics. |
| ONNX Runtime | Maintained `csukuangfj/onnxruntime-libs` static iOS 1.28.2 package | Microsoft MIT license plus upstream `ThirdPartyNotices.txt` at `microsoft/onnxruntime/v1.28.2`. |
| Kaldi native fbank, Kaldi decoder, kaldifst, OpenFst, simple-sentencepiece | Pinned sherpa CMake downloads and their checked hashes | Apache-2.0; retain each source package's copyright/license text. |
| KissFFT | Pinned sherpa CMake download | BSD-3-Clause; Copyright 2003-2010 Mark Borgerding. Retain COPYING and LICENSES/BSD-3-Clause. |
| Eigen | 5.0.1, pinned sherpa CMake hash | MPL-2.0 primary license; retain COPYRIGHT/COPYING notices and source-availability obligations for covered files. No local Eigen modifications. |
| nlohmann JSON | Pinned sherpa CMake download | MIT; Copyright Niels Lohmann. |
| hclust-cpp | Pinned sherpa CMake download | BSD-2-Clause; Copyright Daniel Müllner and Christoph Dalitz. |

Authoritative links:

- [Official model card](https://huggingface.co/FireRedTeam/FireRedASR2-AED/blob/2304afed56eacfee6256dee5937ed22ffa0b64ec/README.md)
- [Official code license](https://github.com/FireRedTeam/FireRedASR2S/blob/4e7d9aaf4482a47cec1724807026b9b151926eb5/LICENSE)
- [Conversion recipe](https://github.com/csukuangfj/FireRedASR2S/blob/5febe49b840d976a52aaa8e50d5f49df14e550e8/fireredasr2s/fireredasr2/export_aed_onnx.py)
- [sherpa license](https://github.com/k2-fsa/sherpa-onnx/blob/a5b4a944c5186a68bcdc0ac3011e4c541781ac84/LICENSE)
- [ORT license](https://github.com/microsoft/onnxruntime/blob/v1.28.2/LICENSE) and [third-party notices](https://github.com/microsoft/onnxruntime/blob/v1.28.2/ThirdPartyNotices.txt)

The export recipe commit postdates the package upload on the same day. The
release is hash-pinned and its v2 AED metadata, architecture, dictionary and CMVN
were inspected against the official checkpoint. No claim is made that the recipe
was independently rerun or that the publisher attested an exact build commit.
Upstream example audio has not received an independent transcript/accent or
redistribution-rights review. Do not republish it or count it as a qualified corpus.
