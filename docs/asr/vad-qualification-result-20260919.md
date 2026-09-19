# Silence VAD qualification result - 2026-09-19

## Disposition

**INCOMPLETE. KEEP DEFAULT OFF.**

The opt-in Silero gate prevented the known hallucinated silence turn in the bounded gate check and preserved one quiet short answer. It did not satisfy the complete qualification: observation classified the prescribed fan-noise and breathing/movement cases as speech, the second quiet short answer was not run, and lifecycle/offline coverage was stopped at the user's request. No threshold, Whisper heuristic, ASR precision, decoder policy, model, package, or default-mode change was made.

## Source and build identity

- Prepared patch base: `8c09e10a26cadae527d4ac73d860029207974e6d`.
- Intervening remote candidate reviewed: `7f69b09ff259b23868c00c4426eb62398f339afc`.
- Phone-tested implementation: `e545ee6fc2c6d43b1dc1aeda7cba663f71b1d99b`.
- Tested selected executable SHA-256: `3eabcd9cdf7b3e11836ed473f9451fb8f14ab95e0bf661171e3ddb8d64afb5ec`.
- Bundle: `com.kevintruong.mural.dev`, installed in place without uninstall or data/cache reset.
- Phone: iPhone 17 (`iPhone18,3`), iOS 27.2 (`24B5084k`), arm64e.
- Retained ASR: packed-v3 FP8 Core AI encoder + PAL8 Core ML decoder, prewarm always.
- Launch ASR arguments were unchanged across arms; only `--asr-vad=off|observe|gate` changed.
- Actual compiler invocation contained both `MURAL_COREAI_TALK` and `MURAL_COREAI_W8`.
- Actual Xcode checkouts: FluidAudio `41540ea237350afe5117a082b5c28eda642d0612` (0.15.7), argmax-oss-swift `1e2a163736dfa5a198e637ae44c114e1c6d5cc2d` (1.1.0).

Ordinary Release and retained FP8/PAL8 Release builds passed. Existing warnings remained limited to the interruption API deprecation, WebRTC async-alternative suggestion, and missing AppIntents metadata dependency.

## VAD artifact identity

The phone prepared `silero-vad-unified-256ms-v6.2.1.mlmodelc`. All regular files, including hidden paths if present, were copied from that exact app-container model directory only and inventoried as sorted UTF-8 rows:

```text
relative-path<TAB>bytes<TAB>file-sha256<LF>
```

SHA-256 of the complete row stream: `11924cda2c126851cff8f07353dfe39edc30cfd183965ce0bc2a3a2845647024`.

The inventory contained five files and 1,063,425 bytes. This identifies tested bytes; it does not make the package revision a remote model pin.

## Host checks

- `swift test`: 77 passed, including 12 `SpeechPresencePolicyTests`.
- Delivered fixture integration: 14 passed. These are fixtures, not Apple inference tests.
- Final-review, Talk opt-in, product-residency, cached-load, hybrid-layout, bounded-hash-memory and probe-contract checks passed.
- Ordinary and selected Apple Release builds passed.
- `test_mel_reader.py` retained its known extraction failure because the generated helper references `PhoWhisperStagedEncoder` out of scope.
- `test_w8_runtime_identity.py` was blocked because the previously documented pinned Torch environment was no longer present. No package was installed or upgraded. The final-review identity/source checks still passed, but this blocker is not relabeled a pass.

## Phone observations

The candidate threshold remained `p >= 0.30` in any complete valid window.

| Arm | Attempts | Result |
|---|---:|---|
| Off control | 1 | One prescribed silent turn produced the known hallucinated user text, tutor reply and TTS. |
| Observe, no-speech block | 5 | Pure/room silence cases N01-N03 proposed rejection. Fan noise N04 and breathing/movement N05 proposed speech and would pass to ASR. Observe intentionally ran ASR; all five produced the known hallucinated turn. |
| Observe, speech blocks | 13 | All 13 proposed speech, including quiet Yes/No and quiet English/Vietnamese. Human report: short English S05 had one lexical error; S09 and known short `siêu thị` coverage had minor/known lexical errors; the number contrast retained meaning with digits. |
| Gate | 3 logged | Two complete low-probability attempts were rejected before ASR. One human-labeled quiet Yes was accepted and completed normally. The user stopped before quiet No; one rejected attempt was not separately labeled and remains retained rather than reassigned. |

For the human-labeled gate silence case, logs show:

- complete evidence, maximum probability `0.098633`, actual rejection;
- Send-to-final `0.042449 s`;
- no per-turn staged encoder/decoder events, tutor start, or TTS start;
- zero-character result and clean return to usable Record;
- no new user message or unsolicited reply was observed.

The required notice was not visible in the user's viewport. A narrow follow-up moves the existing notice directly below conversation status and adds `conversation-notice` accessibility identity. It passed `swift test` and selected Release compilation but was not installed or phone-retested, so it is not part of the tested executable above.

### Timings

These are unmatched microphone turns, not same-byte benchmarks. No p95, energy, cold-cache, or model-only memory claim is made.

- Observe VAD runtime: 18 valid, median `0.026617 s`, range `0.006140-0.056634 s`.
- Observe Send-to-final: 18 valid, median `3.406281 s`, range `2.417088-4.454109 s`.
- Gate VAD runtime: 3 valid, median `0.016442 s`, range `0.012909-0.030657 s`.
- Gate rejected Send-to-final: `0.028152-0.042449 s`; accepted quiet Yes: `2.876909 s`.
- Initial online observe Prepare: `9.836934 s`, including separate VAD availability. Later cached observe/gate Prepare samples were `2.050041-2.167505 s`; the off Prepare sample was `1.990285 s`.

No memory-warning or native-abort event appeared in the scoped Mural captures. This does not substitute for the unrun lifecycle/soak tests.

## Missing evidence and decision

Not run or incomplete: quiet No in gate, full gate matrix, boundary speech, End/background cancellation, fresh cached offline launch/Prepare, deterministic same-byte FP8/PAL8 replay, and promoted-default replay. Radios were not deliberately disabled for a recorded offline arm. The existing local facility was not shown to provide the required same-byte retained-pipeline replay, so deterministic replay is not claimed.

The initial threshold cannot reject the prescribed fan and breathing/movement cases. Raising it was not attempted because no complete corrected-threshold matrix was authorized or run. Default remains off. The gate is useful as an explicit experiment for ordinary silence, but this result is not approval for ordinary-use promotion.
