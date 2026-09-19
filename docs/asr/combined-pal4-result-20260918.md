# Combined PAL4 qualification - REAL sanitized result

Date: 2026-09-18
Original supplied delivery base: `374a7b3abecc87c9f5b78959f3ab1e48084e18ae`
Source commit under test: `0218a01b6bd58507627d97917f2b911884633c39`
Source local-diff hash: `796df08b9f5522b0f17e0644615fd1838e3d64d682218ec4150a14c2c4d014a3`
Release executable SHA256: `107e29550bf461cac4ef820d526098c594e1a4a81c9f5d299a1d830ea72c97dc`

Status: native and corpus gates completed; one valid PAL4/PAL4 live block completed; lifecycle is user-reported but not independently correlated to the PAL4 log; no prewarm-policy comparison. No normal/default Talk promotion.

Device: iPhone 17 (`iPhone18,3`), iOS 27.2 (`24B5084k`), h18p. Xcode 27.0 (`27A5252f`), Swift 6.4. The Release build used the existing `com.kevintruong.mural.dev` bundle with `MURAL_COREAI_TALK` and `MURAL_COREAI_W8`.

## A, B and C

- A: explicit FP8 encoder + PAL8 decoder. Safe control.
- B: explicit FP8 encoder + PAL4 decoder. Fixed-encoder control for the combined trial.
- C: freshly generated PAL4 encoder + the existing PAL4 decoder support. It requires the explicit `--coreai-w8-v3-combined=pal4-pal4` opt-in.

C is a new PAL4 encoder generated from the frozen merged FP16 weights. It is not an old PAL4 encoder and was not derived from FP8. The recipe used Core AI 1.0.0b2, `n_bits=4`, grouped-channel granularity with group size 16, scalar FP16 LUTs and packed UInt4 indices. This is native PAL4 storage through the Core AI path, not a claim of FP4 arithmetic. The decoder was the exact existing `phowhisper-cs-pal4-g16-v1` support artifact; it was admitted under the user's PAL4 override and not rebuilt.

## Exact artifact identity

All device artifacts were pinned by complete manifest SHA. No accepted artifact was overwritten and no cache was deleted. The historical PAL4 support manifest says `FAILED SAVED-CORPUS QUALITY; NOT INSTALLED`; that failure is retained here and was not erased by the device trial.

| arm | encoder manifest / source / AOT | runtime entrypoint | used decoder / support | AOT + used TextDecoder bytes |
|---|---|---|---|---:|
| A: FP8/PAL8 | manifest `73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13`; source `df7f666667918bbd21b874ff63c5009f970675b1d9ad5fd7336517803a1ec720`, 640,125,893 B, native `b9754ecc845a0c5da63234a289a83a31593c618a198daf938e230cfdc450bd89`; AOT `c5c7d3264c7256fc50c37e4e4a3471ec69c278397f1887cca65b96a6ee796c65`, 640,483,375 B, native `e7f2444e520608250ec7e8e11d820af9b1b19e3b813021b2e5acd700dee33485` | `mural_v3_encoder_fp8_packed_6ac300f97511fb8879a6` | PAL8 manifest `430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336`; used TextDecoder 991,764,466 B | 1,632,247,841 |
| B: FP8/PAL4 | same FP8 encoder as A | same FP8 entrypoint | PAL4 manifest `bbdee2a57bbb29e538389364969e75f731dd4f0baf2dd977830f966857095702`; used TextDecoder 556,059,184 B | 1,196,542,559 |
| C: PAL4/PAL4 | manifest `96c7c788ec49b76aa8a4d52ac961a1f93869676d05fcb5109eeb8be581bf765f`; source `53ba512d9473640b6278e45a7196f785ba7ca818d6052713c9a1e811f69a25ed`, 322,946,615 B, native `d497f9917f94448a700560c0eb03c55601b78615ff7bcaa55732a9c420796608`; AOT `f5d9a29d1cbe0f9e1e10ceeb38a2dc55881c043d188194f57378a70192c4c4d1`, 323,253,517 B, native `650677b31df35180b19723274811405a3f50ed89233d6dc11fa23a2f46cef162` | `mural_v3_encoder_pal4_packed_929ba0c6ad9cee6b808c` | same PAL4 support as B | 879,312,701 |

The logical component sum is AOT plus the used TextDecoder only. C is 46.13% smaller than A and 26.51% smaller than B by this measure. Full support inventories include unused AudioEncoder and MelSpectrogram files and are not RAM measurements.

## Native fixture-001 gate

Each arm ran in a separate fresh process with retained caches, `prewarm=always`, staged GPU mode and two turns of fixture `001.wav`. The first C run hit the expected required cache miss. The exact PAL4 encoder-only specialization recovery then completed with no warnings and repeatable hidden output, after which the full C gate completed. The initial cache-confounded comparisons were excluded from the performance conclusion.

The matched warm runs were:

| arm | run ID | result |
|---|---|---|
| A | `690A163C-BD77-48D4-9D65-878206B3E6A3` | 2/2 exact `Yesterday I went to the supermarket.`; terminal, idle, zero errors/warnings |
| B | `C5146F7C-F61B-4E78-AFDA-BBFDFEDE9E63` | 2/2 exact; terminal, idle, zero errors/warnings |
| C | `F2FE6A21-8ACD-4741-A6B7-F43BE35AF159` | 2/2 exact; terminal, idle, zero errors/warnings |

A and B repeated the same FP8 hidden hash. C repeated its changed PAL4 hidden hash within C. All runs verified h18p, the named entrypoint, cache hit, zero specialization during inference, the expected packet width (`1,920,040` for FP8 and `1,920,064` for PAL4), 1,920,000 hidden elements and the decoder handoff shape. No fallback to `main`, crash, memory warning or ownership/drain failure occurred.

The following are means across the two warm native turns. They are gate observations, not a statistical benchmark.

| metric | A | B | C | C vs A | C vs B |
|---|---:|---:|---:|---:|---:|
| staged full seconds | 2.840 | 2.633 | 2.140 | -24.64% | -18.71% |
| replay pipeline seconds, not Send-to-final | 0.805 | 0.775 | 0.768 | -4.54% | -0.86% |
| native encoder seconds | 0.494 | 0.510 | 0.482 | -2.25% | -5.47% |
| encoder function load seconds | 0.636 | 0.651 | 0.293 | -54.01% | -55.04% |
| decoder prewarm seconds | 0.520 | 0.269 | 0.175 | -66.27% | -34.73% |
| decoder seconds | 0.792 | 0.759 | 0.754 | -4.80% | -0.70% |
| decoder-loaded footprint B | 1,217,538,116 | 840,525,892 | 815,319,096 | -33.04% | -3.00% |
| decoder text-end footprint B | 1,256,360,148 | 820,660,436 | 820,586,708 | -34.69% | -0.01% |
| process-lifetime RSS peak B | 1,436,794,880 | 1,431,371,776 | 798,900,224 | -44.40% | -44.19% |

## Paired corpus

Three complete matched triplets were run in order A-B-C, C-A-B and B-C-A. Every arm completed all 22 fixtures with terminal reports, idle state, zero errors and zero memory warnings. Fixture 017 remained diagnostic and was excluded from the 21 scored fixtures. Values below are the mean of each arm's three per-run 21-scored-turn means. Repeated triplets were not pooled as independent turns.

| metric | A | B | C | C vs A | C vs B |
|---|---:|---:|---:|---:|---:|
| AOT + used TextDecoder logical bytes | 1,632,247,841 | 1,196,542,559 | 879,312,701 | -46.13% | -26.51% |
| native encoder seconds | 0.560 | 0.567 | 0.516 | -7.72% | -8.91% |
| encoder function load seconds | 0.288 | 0.275 | 0.142 | -50.55% | -48.32% |
| validation/copy seconds | 0.00849 | 0.00897 | 0.01069 | +25.86% | +19.19% |
| decoder prewarm / load seconds | 0.158 / 0.113 | 0.126 / 0.109 | 0.155 / 0.113 | -2.27% / -0.05% | +23.21% / +2.89% |
| decoder seconds | 1.204 | 1.113 | 1.149 | -4.50% | +3.24% |
| full staged harness seconds, not UI Send | 2.685 | 2.557 | 2.459 | -8.42% | -3.85% |
| encoder-response footprint B | 418,384,097 | 416,024,570 | 287,932,160 | -31.18% | -30.79% |
| post-release footprint B | 220,930,389 | 212,878,324 | 182,678,969 | -17.31% | -14.19% |
| decoder-loaded footprint B | 1,264,686,129 | 834,165,606 | 807,348,640 | -36.16% | -3.21% |
| decoder text-end footprint B | 1,244,386,534 | 806,477,347 | 816,267,959 | -34.40% | +1.21% |
| process-lifetime RSS peak B | 1,449,421,483 | 1,442,146,987 | 821,673,984 | -43.31% | -43.02% |
| warnings / errors | 0 / 0 | 0 / 0 | 0 / 0 | - | - |

C versus A differed on the scored normalized transcript in 5 of 21 fixtures in every triplet: 003 (`learn` versus `lent`), 006 (`Em không biết` versus `Em complete`), 011 (`to` versus `thru` in the English span), 019 (`mình` versus `vận`) and 021 (`My` versus `Mai`). Fixture 017 also differed diagnostically. Some of these are existing PAL4 decoder errors already present in B, not new C-only failures.

C versus B had three retained differences in every triplet: 003 had the same normalized text but a different token sequence, 011 changed `through` to `thru`, and 019 changed `mình` to `vận`. No new negation, number or content deletion was observed in this contrast. These are real differences, not waived or hidden in the aggregates.

## Real app and human feedback

The first live attempt is excluded because the app was later relaunched from the ordinary icon and its log identified the ordinary FP16 selection. The valid PAL4/PAL4 retry used the explicit encoder, decoder, combined and `prewarm=always` flags; the log recorded the PAL4 named function and `phowhisper-cs-pal4-g16-v1` support.

The valid live log contained nine completed captures even though the planned interview block contained six turns. All nine timing rows are retained locally. The six-turn user feedback was: mostly accurate, with the final Vietnamese `siêu thị` not recognized correctly; no visible error; Ready after each reply; no unusual wait in this retry; and no extra heat. The user did not provide exact displayed text for each row, so no invented transcript is published.

| live Send timing | first capture | remaining captures | all 9 |
|---|---:|---:|---:|
| Send-to-final | 2.334 s | mean 2.481 s, median 2.490 s, range 1.897-3.037 s | mean 2.464 s, median 2.453 s, range 1.897-3.037 s |
| Send-to-first-tutor-audio | 5.693 s | mean 4.560 s, median 4.313 s, range 3.646-6.869 s | mean 4.686 s, median 4.362 s, range 3.646-6.869 s |

These are app monotonic timers. No interview or browser delay was subtracted. There is no matched live A/B timing claim. The Mural log contains some existing TTS/audio-queue underflow notices, but no ASR failure or memory warning; the user reported no visible audio problem.

The user also reported that a prior End/background/fresh-turn check worked and declined a duplicate optional check. That is recorded as user feedback, not as an independently correlated PAL4 lifecycle gate. No prewarm `once` comparison was run.

## Tests, build and failures

Final host validation passed: 79 combined/decoder/runtime-identity tests, Python compilation, product residency, hybrid layout, cached-load and Talk opt-in checks. Release build passed with the required Core AI flags. The executable hash matched the earlier installed Release binary.

Recoverable attempts retained locally included the pre-install staging loss, the wrong `PhoWhisper` staging path, the C cache miss and encoder-only specialization, the stalled initial corpus A attempt, the invalid `--display 1` entitlement invocation, and the excluded accidental FP16 live attempt. No unchanged crash was relaunched, no reference or hash was edited, no cache was cleared, and no private recording or full device log is committed.

## Evidence hashes

Raw device reports, events, app logs and recordings remain private under the ignored evidence root `.build/verification/combined-pal4-20260918-local-v3/`.

| local evidence | SHA256 |
|---|---|
| PAL4 encoder manifest | `96c7c788ec49b76aa8a4d52ac961a1f93869676d05fcb5109eeb8be581bf765f` |
| static PAL4 admission | `0551337c8745837fcf1b5d8d7d96a923d5eea7e9fd4554668fe02f9bfe6a2aec` |
| warm native C vs A | `31b95b28ab8aff00c6dcf5f3db3913f474691cc53c41dd44408579f59f35ebc7` |
| warm native C vs B | `6ec253f8b54bd5c4eda394023158727825f648cbe4b96174d86529aaa3ca4a17` |
| three-triplet corpus C vs A | `3ca64d477976a3624d263d3474e6c8f9e0359a7739e561ff3cea583dd06e7ba4` |
| three-triplet corpus C vs B | `c4670c4f03dcd0c16d107c32f772b88eee1106ba3ee70194476fd50d104cdb3f` |
| valid PAL4 live timing | `e45c62d468f8eccd20b5fae58d80960bc382db18754d2723e63e3dad7a376aa7` |
| final host tests log | `2de76bed3c1b0346c6d09dff4b08047b19b37f6a8e67facd93e904a59011c3d9` |
| final Release build log | `4374c9f6003c0fed93c9ea23da78fada3fd750f9db6c78630cdaa760ea71c905` |

## Disposition

The resource-only disposition from the original PAL4 qualification is superseded for user-facing UX by the repeated mixed-language microphone batch. **PAL8 A (FP8 encoder + PAL8 decoder) is now the preferred experimental Talk compromise over PAL4 C (PAL4/PAL4).** PAL4 remains the resource winner, but the user classified only 8/12 PAL4 results as content-preserved versus 10/12 for PAL8, with four PAL4 content errors versus two for PAL8.

PAL16/FP16 remains the quality and compatibility reference. The three-way precision comparison, including the historical FP16 baseline and its measurement limits, is recorded in [the precision comparison](precision-comparison-20260918.md). Normal/default Talk, default prewarm, silence/VAD, caches, warning latches, accepted artifacts and native-drain behavior remain unchanged.
