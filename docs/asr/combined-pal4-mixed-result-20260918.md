# PAL4 mixed English/Vietnamese exercise - sanitized result

Date: 2026-09-18

Script: `docs/asr/combined-pal4-mixed-exercise.md`

The user recorded the fixed 12-item batch in the explicit PAL4/PAL4 local speech-recognition probe and classified each finalized result through the sentence-by-sentence form. Audio and raw device logs remain local under `.build/verification/combined-pal4-mixed-20260918-191633/` and are not committed.

The app was relaunched with:

- `--coreai-w8-v3-encoder=pal4`
- `--coreai-w8-v3-decoder=pal4`
- `--coreai-w8-v3-combined=pal4-pal4`
- `--coreai-w8-v3-prewarm=always`

The scoped Mural log identified the staged Core AI backend. No app crash, memory-warning, or error line was observed in that capture.

## Results

| ID | Classification | User-reported finalized text or note |
|---|---|---|
| M01 | Wrong content | `Hôm qua I went to the city but I forgot my ví.` (`siêu thị` became `the city`) |
| M02 | Formatting only | `Tomorrow mình có a meeting lúc 9 giờ so I need to leave early.` |
| M03 | Accurate | - |
| M04 | Wrong content | `Can you explain sự khác nhau giữa boring and learn.` (`borrow and lend` changed) |
| M05 | Accurate | - |
| M06 | Formatting only | `I need 15, not 50 because the bus is late.` |
| M07 | Accurate | - |
| M08 | Accurate | - |
| M09 | Wrong content | `Sau giờ làm, mình đi siêu thịt, rồi về nấu cơm.` (`siêu thị` gained a final `t`) |
| M10 | Formatting only | `No em chưa sẵn sàng give me 1 minute.` |
| M11 | Wrong content | `The address is số 24 non số 42.` (`not` became `non`; numerals were normalized) |
| M12 | Accurate | - |

Summary: 5/12 accurate, 3/12 formatting-only, 4/12 wrong content, and 0 retries reported. The content-error items were M01, M04, M09 and M11. The script is unchanged and can be rerun in the same order for future comparison.
