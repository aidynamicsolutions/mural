# Conservative VAD trimming - 2026-09-19

## Policy and scope

Candidate base: `6867ff912c7eb940ec444ae836adafaa46d3d7cd` plus the working diff.
The tested whole-turn policy from `04f6fbdab2227838921547818ed91b394d321d17`
is unchanged: the three strongest probabilities must average at least 0.85.
The existing FluidAudio Silero pass supplies both qualification and segmentation.

- Only complete, valid evidence in gate mode can trim or reject.
- An active 4,096-sample window (`p >= 0.30`) retains 8,192 preceding samples
  (512 ms) and 16,384 following samples (1,024 ms), clamped to captured PCM.
- Padded regions merge, including intervening gaps smaller than 32,768 samples
  (2,048 ms). Small leading/trailing removals are also suppressed. Thus an
  internal inactive span shorter than 3.584 seconds remains intact.
- Keep regions in original order, without overlap, duplicated samples, crossfade,
  synthetic padding or amplification. A final partial window retains only real samples.
- An already-qualified turn needs only one active window for each local onset.
  A second consecutive 256 ms window is not required: that could lose a brief
  negation or number after a pause. The whole-turn gate still rejects noise spikes.
- Off and observe preserve original PCM. Missing/invalid/incomplete VAD evidence
  or inference errors fail open to original PCM. Cancellation instead throws and
  drains; it never submits abandoned audio. Evidence and recurrent state are local
  to each call, with no new persistent segmentation state.

Codictate snapshot `f1edad475eed9a807e94de5213ddbab761be3026` was read-only
inspiration for pre-roll, onset, hangover, reset, fail-open and separate durations.
Mural already buffers the complete bounded turn, so it needs ranges, not a streaming
ring buffer or another detector. Codictate's two approximately 30 ms onset frames,
450 ms offline tail and streaming-specific profile are not copied. Mural uses
256 ms windows, its existing whole-turn qualification, and more conservative tails.

FP8 packed-v3 Core AI encoder, PAL8 Core ML decoder, prewarm always, capture bound,
tutor, transcript storage and TTS behavior are unchanged. The frontend still pads
input to its fixed model shape; fewer retained samples alone do not establish
less encoder computation, faster Send-to-final or energy savings.

## Diagnostics

`asr_vad_audio` records original/retained/removed sample counts and seconds,
region count, configured padding/minimum removal, trimming-applied, failed-open
and rejection flags. `asr_vad_region` gives half-open boundaries in the original
16 kHz PCM. Existing per-window probabilities and final gate diagnostics remain.
Rejected turns have zero retained samples but `trimming_applied=false`: gate
rejection is not silence trimming. Durations include padding, not just voiced words.
`capturedSeconds` and `asr_trial_final.captured_seconds` still measure full capture.

## Verification

Using the project-local `verify-mural` skill. Simulator cannot qualify the retained
h18p encoder; the physical iPhone 17 is required.

- `swift test`: 86 passed, including 21 policy checks (8 new focused checks).
- `python3 Tools/CoreAI/test_asr_final_review.py`: 11 passed.
- Retained Release build and `git diff --check`: passed. Only the previously known
  interruption, WebRTC async-alternative and AppIntents warnings appeared.
- Synthetic 20-second speech/pause example retains 12.8 seconds including padding.
  This is sample-policy evidence, not a measured speech-accuracy result.
- User authorized in-place installation and saved-recording replay after review.
  Final executable SHA-256:
  `069c9d3ae495d4f3fccb157bb27be38d66cfda7fd344346275b6d448be6b16f1`.
  Release includes `MURAL_COREAI_TALK` and the existing `MURAL_COREAI_W8`
  development probe condition. Bundle remains `com.kevintruong.mural.dev`.
  Phone: iPhone 17 (`iPhone18,3`), iOS 27.2 (`24B5084k`), h18p.
  Actual launch/preparation events identify FP8 packed-v3 and PAL8 support.
- The small development-only `--asr-vad-replay` branch reuses the actual Talk
  recognizer, VAD analysis and decoder for all 22 existing saved WAVs. It decodes
  original PCM, then retained PCM only when bytes changed; identical PCM needs
  no duplicate inference. It stops on failure, cancellation, background or memory
  warning. The existing probe uses an in-memory store. Private per-file PCM hashes,
  counts, regions and both transcripts are saved only in its unique run directory.
  Launch the development build with `--coreai-asr-probe --coreai-asr-auto --asr-vad-replay`;
  keep the phone unlocked and foregrounded. The report is `vad-replay.json` beside
  the existing probe report under `Documents/CoreAI/PhoWhisper/Runs/<runID>/`.

### Saved recordings and first phone batch

Initial executable: `efff5eb036bdf2d3ac49fe5e18f2201fbd21409570c8ffefb0d806644c9debdb`.
This used the same padding but a 1,024 ms minimum removal.

- Completed all 22 saved WAVs through the retained recognizer, with no memory
  warning in the probe report. Twenty inputs were byte-identical and decoded once.
  Files 018 and 022 were each decoded both original and trimmed: **raw transcripts
  matched exactly**. Removed 1.024 s of leading silence from 018 (9.4375 to 8.4135 s)
  and 1.4165 s of trailing silence from 022 (14.4725 to 13.056 s).
- Historical fixture 017 remains an excluded diagnostic, not a scored speech item.
  This establishes no new transcript loss on these recordings, not universal accuracy.
- User completed the requested five-turn live batch and reported **all passed**:
  long internal pause, quiet Yes, quiet No, room silence, and a short pause before
  negation/numbers. Logs confirm the silence gate rejected before staged ASR.

| Live turn | Captured seconds | Retained seconds | Send-to-final seconds |
|---|---:|---:|---:|
| Long internal pause | 15.600 | 10.752 | 4.014 |
| Quiet Yes | 2.800 | 1.776 | 3.615 |
| Quiet No | 1.700 | 1.700 | 3.385 |
| Room silence, rejected | 3.700 | 0 | 0.044 |
| Short pause before negation/numbers | 7.800 | 6.400 | 2.573 |

Despite correct transcripts, the logs did not meet the requested expectation that
only the long-pause speech turn lose PCM: Yes lost modest leading silence and the
number phrase lost modest trailing silence. The minimum removal was therefore
increased to **2,048 ms**, rather than treating that expectation as passed.

### Final conservative policy

- Replayed the 27 logged native probability sequences (22 saved plus 5 live)
  through the final production policy with identifiable PCM. All 22 saved inputs
  remain unchanged. Quiet Yes, No and the short-pause number phrase also remain
  unchanged; room silence rejects. Only the long-pause speech turn trims, from
  15.600 to 12.016 s. This is deterministic policy replay, not another ASR decode
  or a second full live batch on the final executable.
- Rebuilt and installed the final executable in place. One targeted live recording
  included a five-second pause before a sentence containing fifteen, not and fifty.
  User confirmed **all words and numbers survived**; digit formatting was explicitly
  accepted. Logs show **208,000 samples / 13.000 s captured**, **146,560 samples /
  9.160 s retained**, and **61,440 samples / 3.840 s removed** (29.5%).
- Retained half-open original ranges: `[0, 90112)` and `[151552, 208000)`.
  The cut is entirely internal, with no overlap or duplication. Gate score 1.0;
  `trimming_applied=true`, `failed_open=false`, `minimum_removed_samples=32768`.
  `captured_seconds` remains 13.000. Send-to-final was 3.633 s.
- No memory warning or ASR turn failure appeared in either scoped live capture.
  Tests, final-review checks, Release build and diff checks passed again after
  the minimum-removal adjustment.

**Focused accuracy qualification passed**, combining the saved-audio comparison,
logged-evidence replay and human-confirmed final internal-pause recording. No
material accuracy loss was observed in these checks. Different live utterances
and cache/prewarm conditions prevent a controlled latency comparison; no energy
saving is claimed. Broader speakers/quiet speech, real End/background cancellation,
new offline testing and sustained memory/thermal behavior remain unqualified.
The earlier unresolved memory-warning cause is unchanged.

Evidence: `.build/verification/vad-trimming-20260919/`. Both owned scoped captures
were stopped. The final app is left installed for normal use. No publication,
uninstall, store reset, model transfer, manifest edit or cache deletion.

### Paired iPhone timing

The existing private replay gained a small `--asr-vad-timing` mode. It runs VAD
once per input, then alternates original/retained ordering for five serial pairs
through the actual Talk recognizer. Its timer surrounds transcription through
return and decoder unload; these are replay timings, not UI Send-to-final.

The successful bounded run used one warm-up, a clearly labeled constructed input
(`008.wav`, 5.000 seconds of inserted zeros, then `008.wav`) and unchanged natural-
pause control `019.wav`. The constructed input includes negation and English/Vietnamese
code-switching; the control includes code-switching and a number. All five raw
original/retained transcript pairs matched exactly for both inputs.

| Input | Original | Retained | Reduction | Original median | Retained median | Median paired retained-original |
|---|---:|---:|---:|---:|---:|---:|
| Constructed pause | 18.670 s | 14.062 s | 4.608 s / 24.68% | 2.330369 s | 2.364504 s | +0.017676 s / +0.775% |
| Unchanged control | 11.5075 s | 11.5075 s | 0 | 2.792702 s | 2.817259 s | +0.012046 s / +0.427% |

The five constructed-input paired differences were +1.237247, +0.017676,
+0.011466, +0.024549 and -0.036744 seconds. The unchanged-control differences
were +0.029611, -0.003022, +0.024557, +0.012046 and -0.002268 seconds. Positive
means the retained arm was slower. VAD itself took 0.014031 seconds for the
constructed input and 0.007202 seconds for the control, outside the primary timer.
The constructed original/retained native encoder medians were 0.560927/0.560116
seconds, consistent with the fixed-shape frontend rather than less encoder work.

One 17.458800-second warm-up was reported separately. The first measured retained
arm still incurred residual startup cost and remains included above. Thermal state
was nominal through 17 measurements, changed to fair near the end and stayed fair
for the final pair. There were zero memory warnings and no native error. Two earlier
constructed candidates stopped after their first pair because transcripts differed;
their timings are excluded rather than treating altered content as comparable.

**Conclusion: no demonstrated speedup.** The median paired difference for the
trimmed input was effectively the same size and direction as unchanged-control
run noise. Five pairs do not establish p95 or universal performance. No energy
saving is claimed. Evidence, including all private pairs and component logs:
`.build/verification/vad-trimming-timing-final3-20260919/`. Executable SHA-256:
`be717c375ce3ff8c02b1721bd5f3e826c90108f1919d9a657a4f7830e08fe52c`.
