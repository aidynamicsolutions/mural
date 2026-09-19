# Local-agent handoff: iPhone 17 silence qualification

## Scope and safety

Work only on `aidynamicsolutions/mural`, branch `mvp`, starting from the published
VAD qualification commit. Read `silence-vad-qualification-20260919.md` first.
The prior FP8/PAL8 audit/phone validation is complete; do not reopen quantization.
This VAD candidate is **default off and not yet device-qualified**.

Keep packed-v3 FP8 Core AI encoder + PAL8 Core ML decoder, prewarm always, the
current FluidAudio 0.15.7 exact pin and existing local tokenizer/model assets.
No alternate recognizer, threshold bundle, new VAD dependency or package upgrade.
Preserve the existing app installation/data/signing. Never uninstall or clear
private stores/caches to make a test pass. Keep all recordings, raw device logs,
screenshots and stores local in an ignored verification directory.

## Checkout, host and build checks

Run from the user's real checkout, preserving unrelated edits:

```sh
git status --short
git fetch origin mvp
git switch mvp
git merge --ff-only origin/mvp
git rev-parse HEAD
git status --short
swift test --filter SpeechActivityPolicyTests
swift test
git diff --check
xcodebuild -list -project Mural.xcodeproj
xcrun devicectl list devices
```

Stop on conflicts/divergence; do not reset, stash somebody else's work, force push
or silently test a stale parent. Record the tested SHA. Confirm Package.resolved
still has FluidAudio revision `41540ea237350afe5117a082b5c28eda642d0612`.
Run the applicable existing ASR safety/source-contract checks without conversion
or quantization experiments. Preserve/report pre-existing harness failures.

Use the repo's existing pinned Xcode/signing build procedure for an ordinary
Release build (no new Swift compilation conditions). First discover the actual
connected iPhone 17 and scheme rather than reusing a historical UDID. Prior
qualification used `com.kevintruong.mural.dev` with the existing signing override;
reuse the user's valid local configuration. Build/install in place, record build
warnings, executable identity, iOS build, model manifests and app settings. Do not
claim this task's Linux syntax check was an Xcode build.

For every measured launch retain these ASR arguments and add exactly one VAD mode:

```text
--coreai-w8-v3-encoder=fp8
--coreai-w8-v3-decoder=pal8
--coreai-w8-v3-prewarm=always
--speech-vad=off
```

Replace only the final argument with `--speech-vad=observe` or `--speech-vad=gate`
for the later conditions. Confirm actual startup logs/model identity, not merely
the intended command. Use normal Talk, On-device, English learning/Vietnamese
support. Keep optional meaning support, audio route, phone distance and room
conditions fixed when comparing latency. Let the greeting finish before Record.

## VAD preparation and identity

Prepare once online in observe mode. Require an `asr_vad_prepared` event naming
`silero-vad-unified-256ms-v6.2.1.mlmodelc`. If preparation is unavailable/fails open,
report failure and stop qualification; do not mislabel the ASR fallback as a VAD
acceptance. No repeated download/repair loop.

The separate asset lives under the app's Application Support directory at
`FluidAudio/Models/silero-vad/`. Record a sorted inventory of model-relative paths,
byte counts and SHA-256 digests locally; a sanitized model inventory/digest is
safe to include in the eventual report. Confirm identical actual model bytes
for all conditions and any Mac/phone fixture comparison. The package pin does
not pin Hugging Face `main`; do not call unmeasured bytes verified.

Turn both Wi-Fi and cellular off after preparation. Verify observe and gate work
without network. Later End, terminate/relaunch the app, and Prepare again offline
with the intact cache. Do not count a fail-open turn as offline VAD success.

## Measurement order — no tuning before observation

A. Run the existing behavior with `--speech-vad=off` as the control.

Observation. Run `--speech-vad=observe`: ASR always runs, including when the
proposal is noSpeech. Record every probability window and the actual displayed
transcript locally. Review separation across ALL no-speech and must-accept cases.
The 0.30 rule is only a candidate. Missing quiet Yes/No is a failure even if the
observe mode still displayed them because it did not enforce the proposal.

B. Only after this review, run the SAME frozen candidate in `--speech-vad=gate`.
Re-run the complete matrix. Do not enable Whisper noSpeechThreshold at the same
time. If Silero alone cannot meet the matrix, keep default off and report the
specific failure before proposing C (Whisper-only) or D (combined).

Predeclare three attempts per row per condition. These are planned replicates,
not retry-until-pass. Retain every attempted turn, including wrong/rejected words,
fail-open results, cancellations and failures. Do not select only the best take.
A separate second-room/microphone-noise run is useful; label it separately.

## Batched human interview — present before recording

Give the user the entire next block before starting it. For EACH speech row show
its exact phrase **before** the user presses Record. No new interview form,
question, confirmation or overlay may appear between Record and speaking.
Collect responses in one batch after the turns, using IDs to correlate them.
Do not replace prescribed quiet speech with louder repetitions after a miss.

For silence, use these literal instructions:

**N01:** Press Record. Remain silent for 1 second. Press Send.

**N02:** Press Record. Remain silent for 3 seconds. Press Send.

**N03:** Press Record. Do not speak for 3 seconds in normal room noise. Press Send.

**N04:** Press Record. Do not speak for 3 seconds with normal fan noise. Press Send.

**N05:** Press Record. Breathe normally and make a small movement without words
for 3 seconds. Press Send.

For speech, display the quoted phrase, then instruct: **Press Record. Say the
phrase once at the specified volume. Press Send.** Wait for Ready before the next
turn. Do not ask the user to hold still/speak loudly just to help the detector.

| ID | Volume | Exact phrase |
|---|---|---|
| Q01 | Quiet | Yes. |
| Q02 | Quiet | No. |
| S01 | Normal | Yes. |
| S02 | Normal | No. |
| Q03 | Quiet | I need a little more time. |
| Q04 | Quiet | Mình cần thêm một chút thời gian. |
| S03 | Normal English | I went to the market this morning. |
| S04 | Normal Vietnamese | Sáng nay mình đi chợ mua rau. |
| S05 | Normal mixed | Hôm nay I went to siêu thị to buy some milk. |
| S06 | Quiet short Vietnamese | siêu thị |
| S07 | Normal, numbers | I need fifteen, not fifty, tickets. |
| S08 | Normal, negation | Mình không muốn hủy vé. |

Add clearly labeled planned variants of Q01/Q02 spoken immediately after Record
and near Send after initial silence. This checks window-edge/short-burst behavior
without substituting for the original attempts. No auto-gain, artificial amplitude
floor or per-phrase model prompt is allowed.

## Deterministic audio, kept private

If the existing local audio/ASR probe accepts saved input, also use exactly 16,000
and 48,000 zero Float32 samples for true digital silence. Microphone "silence"
contains a device/room noise floor and is not identical. Save consented fixed
speech/noise takes locally, with sample counts and hashes, and replay the exact
same 16 kHz mono PCM through the pinned Silero API and retained FP8/PAL8 ASR.
Do not re-record only failing phrases or normalize quiet examples independently.
Do not substitute a different Silero/ONNX version or a different ASR for these
comparisons. No recording needs to be added to Git.

## Turn ledger and actual savings

Capture, locally, for every relevant attempt:

```text
case ID and replicate; tested commit/build/mode; capture UUID
sample count / duration; all VAD probabilities; proposal; actual reject/accept/fail-open
speech-active chunks / estimated duration / first and last boundaries
EXACT displayed transcript if accepted; exact notice if rejected
new saved user fragment? tutor reply started? TTS started? Ready restored?
Send-to-final; VAD runtime; first tutor-audio time if any
phase footprint; process lifetime peak (separate); memory warning / crash / native abort
End/background/cancel result; perceived delay, responsiveness, warmth and UX
```

Join `asr_vad_window/result/footprint` with `asr_trial_capture/send/final/audio`
using the actual UUID, not timestamps from an interview form. Preserve error and
cancellation rows; exclude them only from successful-latency summaries, with
counts reported. Numeric window logs can compute min/mean/max afterward.
`active_seconds_estimate` is a coarse window metric, not measured phoneme duration.

For each rejected silence turn verify no per-turn staged mel/encoder work,
`asr_staged_turn_begin`, decoder prewarm/load/decode completion, new tutor reply or
TTS startup. Confirm no user fragment appears or survives End/relaunch. The greeting
and its speculative decoder warmup are not a turn saving and must be excluded.
Check the visible notice is **No speech recognized. Try another recording.**
and the app returns cleanly to **Ready · Tap Record**.

Report matched control-versus-gate Send-to-final and footprint differences for
no-speech, and genuine-speech overhead for observe/gate versus off. Separate first
prepared turn from warm turns, report valid counts, median/range, and any materially
worse UX. No p95, energy, cold-cache or model-only RAM claim from a small sample.
Source-level skipped operations are not a measured millisecond/memory saving.

## Lifecycle and negative tests

Check End and background during recording, immediately after Send, during observed
VAD activity where timing permits, and during accepted native ASR. Include a long
recording for cancellation between VAD windows. Await native drain before another
Prepare/Record; no late transcript/reply/TTS or leaked state may appear. Clearly
label when the intended phase was too fast to hit, rather than claim coverage.

Test silence -> speech -> silence, fresh session, End/Prepare, background/return,
and offline cold-process Prepare. Confirm the existing memory-warning latch still
stops the session without fallback. Do not induce an uncontrolled memory-pressure
crash on a personal device; report simulator/injected-warning coverage separately
from naturally observed phone warnings. Any new memory warning/native abort fails.

## Decision and publication

Pass requires rejection of intentional silence with no fabricated/saved user text,
no tutor/TTS, clean Ready/notice, successful quiet Yes and No, low-volume English
and Vietnamese, preserved normal bilingual/numbers/negation, valid offline/cache
behavior, safe lifecycle/drain and no new memory warning/native abort. Rejection
of quiet speech is a FAIL, not a microphone sensitivity "improvement".

Review every failure critically. Make only a narrow evidence-driven correction,
rerun the affected cases AND the complete must-accept block, and retain original
failures in the report. Keep default off until all acceptance evidence passes.

Commit a sanitized result report: tested build/model inventory, counts, controlled
content outcomes, aggregate timings/footprint, warnings/crashes, lifecycle coverage,
remaining limitations and the explicit promotion decision. Never commit recordings,
private transcripts, stores, screenshots or broad raw device logs.

Immediately before publishing, fetch/check the remote head and preserve others'
commits. Publish a single-parent descendant of the current head, fast-forward only;
no force update. Re-fetch `mvp` and verify its resulting SHA. Report both the tested
SHA and any later report/promotion commit; rerun after runtime changes. Do not claim
this handoff itself is iPhone evidence or a completed silence fix.
