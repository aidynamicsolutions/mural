# iPhone 17 bilingual ASR: current-model optimization overview

Updated 2026-09-17 against `f51fb58d7653330abbfabb80eae52fa07485a1c9` on `mvp`.

**Current instructions:** [Core AI 8-bit optimization plan](coreai-8bit-optimization-plan.md), then [local implementation/interview handoff](local-agent-handoff.md). These supersede the old decoder-only sequence and the earlier Qwen-first priority. This documentation change does not install a compressed model, fix memory recovery, or establish any new phone measurements.

## Decision

Investigate compression of BOTH components of the exact existing PhoWhisper bilingual model. Export new Core AI FP8-weight and INT8-weight encoder candidates, with FP16 activations and the existing FP16 feature handoff, then test the strongest candidate with the saved PAL8 Core ML decoder. The original mixed FP16/PAL8 comparison remains a useful control, not the final mandatory configuration.

The saved decoder is **PAL8, not FP8**. Matching bit width is not an interoperability requirement. Apple documents a direct compression route from an uncompressed `.aimodel` and explicitly excludes FP8 from its Core ML export path; see the primary sources and compatibility checks in the detailed plan. Uniform FP8 across both components would require a separate decoder-runtime migration, which is not this experiment.

Keep Qwen, new Parakeet work, new bilingual-adapter training, and unchanged native-crashing Core AI decoder variants deferred. The [adapter/data feasibility note](whisper-bilingual-adapters.md) remains longer-term research, not the local agent's next action.

## Frozen identities

Preserve the original assets. Recover and verify local files rather than treating these historical paths as proof they exist on the current Mac.

| Artifact | Identity |
| --- | --- |
| Base | `vinai/PhoWhisper-large` at `b9136a44b5f2ca664bd0b8f74baecf1715f6eeeb` |
| Adapter | `rinhoooo/phowhisper-large-vien-cs-asr` at `a98f55e0f42b2c4f1e71b3348a2b917fac0a7328` |
| Merged model | `phowhisper-cs-fp16-v1` |
| Merged `model.safetensors` SHA-256 | `264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a` |
| Original support manifest SHA-256 | `7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52` |
| Original GPU encoder AOT fingerprint | `f783c9b539d90a589e1449e514599e240ce6036b3bab6c298858e49bba112829` |
| Saved `pal8-g16-v1` manifest SHA-256 | `430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336` |

The current source requires 80 mel bins, model width 1280, 32 encoder and 32 decoder layers, and vocabulary size 51865. Do not substitute a v3 processor, tokenizer, model, or unmerged base. The decoder receives the accepted encoder's feature representation, not arbitrary same-shaped features.

Historical Mac evidence is under `/Users/tiger/tmp/mural-asr-benchmark/`, including `phowhisper-conversion/merge-fp16/model` and `phowhisper-conversion/pal8-g16-v1/`. Accepted Core AI source exports were under `.build/coreai/split-export/`. Do not overwrite these or repeat the completed PAL4/6/8 conversion ladder.

## Recorded PAL8 evidence, not new measurements

| Measure | Original FP16 | Saved full Core ML PAL8 pair |
| --- | ---: | ---: |
| Runtime bytes, excluding manifest/caches | 3,101,573,848 | 1,655,763,645 |
| First 16 scored clips, WER | 4.6875% | 6.25% |
| Five follow-up clips, WER | 2.89855% | 2.89855% |
| Normalized agreement with FP16 | Reference | 19/21 |
| Compressed iPhone resource qualification | Not applicable | Not previously established |

Calculated file-size saving is 46.62%; it is not a measured RAM reduction or speedup. PAL8 Mac preparation/first-file/warm-median times were 59.978 / 7.126 / 2.640 seconds, not matched current-phone comparisons. Do not attach these figures to a new Core AI encoder/PAL8 decoder combination.

There are **21 scored** clips, 001-016 and 018-022. Fixture 017 is a separate diagnostic. The 22-file conversion suite is not 22 correct human references.

| Fixture | FP16 output | PAL8 output | Current disposition |
| --- | --- | --- | --- |
| 006 | `Em không biết từ này.` | `Em complete từ này.` | Lexical/meaning regression, accepted by user for this bounded optimization trial. |
| 007 | `seal tea` | `seoul tea` | Both wrong for `siêu thị`; accepted known-error variation. |

Do not reinstate exact FP16 agreement as a blanket admission rule. Keep these exceptions visible; do not waive arbitrary new encoder/combined-model errors or rewrite reference text. Review additional differences with the user and measure ground-truth accuracy separately from conversion parity.

## Repository evidence to preserve

Read `mvp_plan.md` for compression history and the newer files in `docs/coreai/` for current status, particularly `gpu-talk-checkpoint.md`, `first-turn-readiness-prewarm-plan.md`, and `stateful-decoder-checkpoint.md`.

The staged GPU-preferred encoder has limited positive phone evidence; the different ANE-backed cache/load failures were not established as memory corruption. The separate stateful Core AI decoder aborted at first native inference. Neither failure is permission to delete caches or retry an unchanged crashing graph.

Historical staged Release first Send-to-final was 46.87 seconds versus warm 5.54/5.84 seconds, with encoder scope returning around three seconds after Send. Later greeting-start prewarm exists already. Diagnose the current timeline rather than promising that encoder weight compression removes decoder preparation.

Memory metrics around 2.12 GB in the earlier GPU corpus are event samples, not continuous peaks. The historical eager all-Core-ML comparator warned before transcription; do not repeat it unchanged as a baseline. Current warning handling latches preparation unavailable: safe recovery is a separate lifecycle patch, not achieved by changing weight precision.

## Execution and promotion

The next local session implements and qualifies the narrow FP8/INT8 encoder experiments and informative decoder combinations in the linked handoff, using the user's build/log/interview workflow. It does not stop at another generic research plan when the required tools/assets are available.

No default switch occurs automatically. A candidate needs repeatable operational benefit, acceptable bilingual differences, safe model ownership, and subsequent offline/lifecycle/thermal qualification. Preserve finalized learning history and original assets. The earlier 92-model licensing inventory remains incomplete; it is not a prerequisite to this same-model compression experiment or a claim of blanket clearance.
