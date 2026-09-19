# ASR precision comparison: FP16, PAL8 and PAL4

Date: 2026-09-18

## Decision

For the tested mixed English/Vietnamese conversation path, **PAL8 is the preferred UX compromise over PAL4**. PAL4 is materially smaller and lower-RSS, but the user's repeated 12-sentence assessment found more content errors. The original FP16 configuration remains a historical comparison reference. It was not run on this exact live batch, so this batch does not establish an FP16 quality ceiling.

This is a finding for the experimental Talk path. It does **not** change normal/default Talk, default prewarm, VAD/silence behavior, caches, warning latches, accepted artifacts or native-drain behavior.

## What the names mean

| Label | Tested configuration |
|---|---|
| FP16 reference | Original FP16 encoder with the original `phowhisper-cs-fp16-v1` Core ML support/decoder, not the separate PAL8 support artifact. There is no PAL16 artifact. |
| PAL8 | FP8 Core AI encoder + PAL8 Core ML decoder. This is arm A. |
| PAL4 | Fresh PAL4 Core AI encoder + existing PAL4 Core ML decoder. This is arm C and requires explicit PAL4/PAL4 opt-in. |

PAL8 is not an FP8 decoder. PAL4 changes both encoder and decoder in the current user-facing comparison.

## Repeated 12-sentence user assessment

The PAL8 and PAL4 runs used the same fixed script and the same sentence-by-sentence interview. `Formatting only` means the spoken content was preserved despite punctuation, capitalization or numeric formatting differences.

| Configuration | Accurate | Formatting only | Wrong content | Content preserved |
|---|---:|---:|---:|---:|
| FP16 reference | Not run on this exact 12-sentence batch | - | - | - |
| PAL8 | 7/12 | 3/12 | 2/12 | 10/12 |
| PAL4 | 5/12 | 3/12 | 4/12 | 8/12 |

PAL8 improved the exact-accurate count by two and reduced content errors by two. PAL4's content errors were M01 (`siêu thị` -> `city`), M04 (`borrow and lend` -> `boring and learn`), M09 (`siêu thị` -> `siêu thịt`) and M11 (`not` -> `non`). PAL8 retained content errors on M01 and M09, while M04 became accurate and M11 became formatting-only.

This is a small, user-classified live sample, not a statistically powered accuracy benchmark. It is nevertheless the most relevant evidence for the requested UX choice because it uses the exact sentences and real microphone path.

## Saved-corpus quality reference

The historical saved-corpus figures are not the same as the new 12-sentence microphone batch:

| Configuration | First 16 WER | Follow-up 5 WER | Saved-corpus note |
|---|---:|---:|---|
| FP16 reference | 4.6875% | 2.89855% | FP16 reference |
| Historical PAL8 | 6.25% | 2.89855% | 19/21 normalized outputs matched FP16; known 006 and 007 differences retained |
| Current PAL4 C | Not converted to a ground-truth WER in this report | Not converted | C versus PAL8 differed on five scored fixtures in the current corpus triplets; live assessment above is the quality decision |

The historical PAL8 WER is evidence that compression can introduce quality differences. It is not a claim that PAL8 is worse than PAL4 on every speech set, and the current live batch points in the opposite direction for this user's mixed-language UX.

## Resource and performance comparison

### Matched current PAL8 versus PAL4 corpus

This is the best controlled resource comparison between the current arms. It uses three matched corpus triplets, retained caches, fresh processes and `prewarm=always`. The full staged timer is a lab-harness interval, not UI Send-to-final.

| Metric | PAL8 A: FP8/PAL8 | PAL4 C: PAL4/PAL4 | PAL4 versus PAL8 |
|---|---:|---:|---:|
| Native encoder seconds | 0.560 | 0.516 | -7.72% |
| Encoder function load seconds | 0.288 | 0.142 | -50.55% |
| Decoder seconds | 1.204 | 1.149 | -4.50% |
| Full staged harness seconds | 2.685 | 2.459 | -8.42% |
| Decoder-loaded footprint | 1,264,686,129 B | 807,348,640 B | -36.16% |
| Process-lifetime RSS peak | 1,449,421,483 B | 821,673,984 B | -43.31% |

PAL4 clearly wins the resource comparison. The live quality assessment is why that resource win is not sufficient for the preferred UX decision.

### Live microphone timing

| Configuration | Batch | Send-to-final mean | Memory coverage |
|---|---|---:|---|
| PAL8 | 12 completed sentences | 3.433 s | Decoder-loaded footprint mean 1,281,528,621 B; RSS peak 1,415,413,760 B |
| PAL4 | 9 completed captures in the valid live block | 2.464 s | No per-turn memory instrumentation in that live block; no memory warning reported |

The PAL8 and PAL4 live timing blocks were not the same process, thermal window or exact capture count, so their live timing is directional only. The controlled corpus table is the stronger PAL8/PAL4 performance comparison. Separately, historical FP16 phone replay had a warm median of 4.36 s, approximately 2.55 GB footprint and approximately 4.02 GB lifetime RSS peak. Those values came from an earlier build/path; the replay duration is not a measured live Send-to-final mean or a matched three-way result.

### Storage context

The historical full runtime accounting reported approximately 3,101,573,848 B for FP16, 1,655,763,645 B for PAL8 and 891,738,051 B for the earlier 4-bit runtime candidate, excluding manifests and caches. The current PAL4 C report's logical AOT plus used TextDecoder sum is 879,312,701 B. These are asset accounting scopes, not physical RAM measurements.

## Updated recommendation

Retain **packed-v3 FP8 Core AI encoder + PAL8 Core ML decoder** for the final bounded iPhone validation, with `prewarm=always`. PAL4/PAL4 achieved resource savings but lost more content in the repeated live comparison. PAL6 and PAL4 qualification reports remain historical evidence, not instructions to restart optimization.

The FP16 figures remain a historical reference, not proof of a quality ranking on the untested live batch. This small sample establishes neither universal FP8/PAL8 equivalence to FP16 nor universal PAL4 failure. No quantization, model-conversion, default-promotion or silence/VAD work is authorized by this conclusion. See the [current ASR index](README.md).

Raw audio, private stores and device logs remain local under the ignored verification directories. Only this sanitized comparison is committed.
