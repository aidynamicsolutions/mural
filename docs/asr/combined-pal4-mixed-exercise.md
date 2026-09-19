# PAL4 mixed English/Vietnamese speech exercise

This is a reusable, sanitized microphone script for the explicit PAL4/PAL4 lab build (C). It contains no private recordings or device logs. Record the prompts in order and keep each first attempt. If a prompt is unclear or the app does not finalize it, retry that prompt once and retain both attempts.

## Recording protocol

1. Launch the explicit PAL4/PAL4 build and open the local speech-recognition probe.
2. Select the PhoWhisper speech model and wait until it is ready.
3. For each item, tap **Record**, read the prompt exactly once at a natural pace, then tap **Send recording**.
4. Wait for finalized recognition before starting the next item. Do not edit the displayed transcript.
5. Save the displayed transcript locally with the item ID if the app offers an export or copy action. Do not upload audio or transcripts.
6. A future rerun should use the same order and wording, while retaining first attempts and any one-time retries.

Do not speak the item ID, quotation marks, or the punctuation. The expected text is a content reference, not a requirement that the recognizer preserve capitalization or punctuation.

## Prompts

| ID | Say this | Coverage | Expected normalized content |
|---|---|---|---|
| M01 | Hôm qua I went to the siêu thị, but I forgot my ví. | Vietnamese diacritics inside an English sentence; known `siêu thị` stress case | `Hôm qua I went to the siêu thị, but I forgot my ví.` |
| M02 | Tomorrow mình có a meeting lúc chín giờ, so I need to leave early. | English/Vietnamese switching; time phrase | `Tomorrow mình có a meeting lúc chín giờ, so I need to leave early.` |
| M03 | I ordered phở không hành, but they gave me thêm hành. | Food vocabulary; repeated Vietnamese words | `I ordered phở không hành, but they gave me thêm hành.` |
| M04 | Can you explain sự khác nhau giữa borrow and lend? | English question with a Vietnamese noun phrase | `Can you explain sự khác nhau giữa borrow and lend?` |
| M05 | Nếu trời mưa, I will stay home and làm việc. | Vietnamese conditional with English continuation | `Nếu trời mưa, I will stay home and làm việc.` |
| M06 | I need fifteen, not fifty, because the bus is late. | English control; near-confusable numbers and negation | `I need fifteen, not fifty, because the bus is late.` |
| M07 | Mẹ em said nhớ mang áo khoác, but I left it at home. | Family phrase; imperative embedded in English | `Mẹ em said nhớ mang áo khoác, but I left it at home.` |
| M08 | How do I say ngại làm phiền in English? | Translation-style question; Vietnamese idiom | `How do I say ngại làm phiền in English?` |
| M09 | Sau giờ làm, mình đi siêu thị rồi về nấu cơm. | Vietnamese control with diacritics and `siêu thị` | `Sau giờ làm, mình đi siêu thị rồi về nấu cơm.` |
| M10 | No, em chưa sẵn sàng, give me one minute. | Short interruption; negation and code-switch | `No, em chưa sẵn sàng, give me one minute.` |
| M11 | The address is số twenty-four, not số forty-two. | Mixed-language numbers; word order | `The address is số twenty-four, not số forty-two.` |
| M12 | Please remind tôi to call my sister after lunch. | English request with a Vietnamese object | `Please remind tôi to call my sister after lunch.` |

## Review checklist

For each item, compare the finalized transcript with the expected content and mark:

- exact enough: meaning and code-switching preserved;
- content drift: a word, number, negation, or language segment changed;
- formatting only: capitalization or punctuation differs but the spoken content is intact;
- retry needed: recording or finalization was interrupted.

The script is intentionally fixed so later runs can compare recognition quality without changing the spoken data. Keep each run's private results under ignored local evidence; commit only this sanitized script or aggregate findings with no audio, raw transcript, or personal metadata.
