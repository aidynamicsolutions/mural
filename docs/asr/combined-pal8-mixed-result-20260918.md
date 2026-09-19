# PAL8 mixed English/Vietnamese exercise - sanitized result

Date: 2026-09-18

Script: `docs/asr/combined-pal4-mixed-exercise.md`

This is the same fixed 12-sentence batch as the PAL4 run. The selected arm was **A: FP8 encoder + PAL8 decoder**. It was launched with:

- `--coreai-w8-v3-encoder=fp8`
- `--coreai-w8-v3-decoder=pal8`
- `--coreai-w8-v3-prewarm=always`

The runtime log repeatedly identified `mural_v3_encoder_fp8_packed_6ac300f97511fb8879a6.h18p.aimodelc` and `phowhisper-cs-pal8-g16-v1`. It did not use PAL4. The first partial process and the later complete process were retained locally; the complete 12-turn performance summary is process 11697. Audio and raw device logs remain under `.build/verification/combined-pal8-mixed-20260918-194056/` and are not committed. The three-way FP16/PAL16, PAL8 and PAL4 finding is summarized in [the precision comparison](precision-comparison-20260918.md).

## Accuracy classification

The user classified each finalized transcript through the sentence-by-sentence interview.

| ID | Classification | User-reported finalized text or note |
|---|---|---|
| M01 | Wrong content | `Hôm qua I went to the city but I forgot my ví.` (`siêu thị` became `the city`) |
| M02 | Formatting only | `Tomorrow mình có a meeting lúc 9 giờ so I need to leave early.` |
| M03 | Accurate | - |
| M04 | Accurate | `Can you explain sự khác nhau giữa borrow and lend.` |
| M05 | Accurate | - |
| M06 | Formatting only | `I need 15 not 50 because the bus is late.` |
| M07 | Accurate | - |
| M08 | Accurate | - |
| M09 | Wrong content | `Sau giờ làm, mình đi silty rồi về nấu cơm.` (`siêu thị` changed) |
| M10 | Accurate | - |
| M11 | Formatting only | `The address is số 24, not số 42.` |
| M12 | Accurate | - |

Summary: 7/12 accurate, 3/12 formatting-only, 2/12 wrong content, and 0 retries. Content was preserved in 10/12 items when formatting-only results are included. The content-error items were M01 and M09.

## PAL4 comparison

The preceding PAL4 run classified 5/12 as accurate, 3/12 as formatting-only and 4/12 as wrong content. On this one repeated batch, PAL8 improved the exact-accurate count by two and reduced content errors by two. M04 and M11 improved from content errors to accurate/formatting-only; M10 improved from formatting-only to accurate. M01 and M09 remained content errors. This is a useful paired indication, not a statistical accuracy benchmark: microphone delivery, decoding state and the user's classification are still sources of variation. The full PAL16/FP16, PAL8 and PAL4 comparison is recorded in [the precision comparison](precision-comparison-20260918.md).

## Performance and memory

These are the 12 completed PAL8 turns from the complete process. `Send-to-final` is the user-visible recognition interval. Footprint values are sampled process footprint observations, not allocations; RSS is the process-lifetime peak.

| Metric | Mean | Median | Range |
|---|---:|---:|---:|
| Send-to-final seconds | 3.433 | 3.391 | 3.048-3.970 |
| Staged turn end-to-end seconds | 3.415 | 3.366 | 3.034-3.950 |
| FP8 encoder native seconds | 0.523 | 0.519 | 0.510-0.547 |
| Decoder prewarm seconds | 0.811 | 0.938 | 0.407-1.070 |
| Decoder load seconds | 0.103 | 0.098 | 0.086-0.133 |
| Decoder decode seconds | 1.085 | 1.090 | 0.873-1.331 |
| Decoder-loaded footprint bytes | 1,281,528,621 | 1,260,330,016 | 1,203,652,760-1,362,135,144 |
| Process RSS peak bytes | 1,415,413,760 | - | process peak |

The logged thermal state was 0 for turns 1-8 and 1 for turns 9-12, so the timing mean includes a mild late-session thermal change. No staged memory-warning event was logged.
