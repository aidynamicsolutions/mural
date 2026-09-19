# Local-agent handoff: iPhone 17 silence qualification

## Boundary and expected starting point

Work on `aidynamicsolutions/mural`, branch `mvp` only. The candidate was prepared
against `8c09e10a26cadae527d4ac73d860029207974e6d`. The prior engineering audit and
final phone validation have committed PASS dispositions. Do not repeat the
quantization campaign or modify the retained ASR:

```text
packed-v3 FP8 Core AI encoder + PAL8 Core ML decoder
--coreai-w8-v3-encoder=fp8
--coreai-w8-v3-decoder=pal8
--coreai-w8-v3-prewarm=always
```

The preparation session could read GitHub but could not publish. Apply and build
the delivered guarded patch first; do not assume an implementation commit exists.
Its default VAD mode is off. Gate mode is not yet qualified. This document is a
work order, not a result report.

Preserve private stores, unrelated working-tree changes, installed app identity,
model manifests and compiled ASR assets. No uninstall, data reset, cache clearing,
package upgrade, different ASR model, extra VAD dependency or mass project
regeneration. Use the existing signing/build overrides and rediscover the phone.
Do not copy a remembered UDID, bundle, process ID or toolchain path blindly.

## Apply, build, and initial publication

Read the current branch and repository instructions. Inspect `git status` before
any edit. Prefer GitHub write actions when actually exposed. In the existing
trusted local checkout, verify the current remote and source before applying:

```sh
git branch --show-current
git status --short
git fetch origin mvp
git rev-parse HEAD origin/mvp
git ls-remote --exit-code origin refs/heads/mvp
python3 /path/to/mural-silence-qualification/apply.py "$PWD" --check
python3 /path/to/mural-silence-qualification/apply.py "$PWD"
git diff --check
git diff --stat
```

`apply.py` refuses another branch, a different local or remote head, modified
source blobs, ambiguous anchors or existing new-file targets. It changes only
working-tree files; it neither stages nor commits. It refuses rather than
replacing unrelated edits. A moved head requires a fresh review/adaptation of the
owned patch on current `mvp`, not a reset or force push. Review the resulting full
diff; the script's successful preflight is not an Apple build.

Verify the resolved dependency and actual Xcode checkout:

```text
FluidAudio 0.15.7 = 41540ea237350afe5117a082b5c28eda642d0612
WhisperKit / argmax-oss-swift 1.1.0 = 1e2a163736dfa5a198e637ae44c114e1c6d5cc2d
VAD = silero-vad-unified-256ms-v6.2.1.mlmodelc
```

Run `swift test` in the complete checkout, including the new 12 policy tests.
Build ordinary Release and the retained FP8/PAL8 Release with the established
`MURAL_COREAI_TALK` / `MURAL_COREAI_W8` configuration where applicable. Confirm the
running backend and exact retained manifests, not merely the launch arguments.
Run applicable existing final-review, Talk opt-in, residency and identity smoke
checks in the already pinned Mac environment. Do not rerun historical model
experiments. Do not hide the existing mel-reader harness limitation or claim the
Linux fixture checks are native tests. Treat new compile errors narrowly.

After Mac tests pass, publish the observation-capable candidate with its default
still off. Stage only the two application files, the new Core policy/test, and
these two documents. Do not stage the whole worktree or `.build`. Recheck the
remote head immediately before the write, create a child commit, and update
`mvp` fast-forward only. A normal push must not use `--force`, `--force-with-lease`,
a `+` refspec or a force ref API. On a moved head, stop publication and review.
Re-fetch the remote after a successful push and verify the exact created SHA.
Record that implementation SHA as the phone's tested source.

## Local-only evidence preparation

Use a new ignored `.build/verification/vad-<unique-run>/` directory. Confirm it is
ignored before collecting anything. Keep recordings, exact displayed transcripts,
raw process logs, stores and screenshots there only. Commit only a separately
reviewed sanitized result report. Collect a bounded Mural-only process log; do not
capture broad device logs or leave a capture process running after the block.

Record the source SHA, executable hash, actual phone/OS/build, bundle, selected
ASR pins, effective VAD argument, model filename, compiled VAD inventory/hash and
radio/cache conditions. The model is fetched separately during Prepare. Verify
`asr_vad_prepared` and its filename for observe/gate; any unavailable/error event
is a failed VAD qualification condition even though ASR deliberately stays usable.

Hash the actual compiled VAD bundle without reading application stores. Inventory
all regular files, including hidden entries; record relative names, bytes and
SHA-256, then a clearly specified aggregate digest. Use the same algorithm and
unchanged model bytes across arms. The SDK revision alone is not a model hash.
Do not modify the model or add runtime pinning machinery solely to manufacture a
successful experiment.

Prepare once with connectivity for missing VAD assets, then turn Wi-Fi and
cellular off. Test the already prepared app and a fresh cached offline launch /
Prepare. A missing-model offline attempt is a separate failure/availability case,
not a warm-cache success. Do not clear the ASR caches to test it. Also verify that
an unavailable VAD is reported as unavailable, not mislabeled a silence rejection.

Where an existing local replay facility can feed the retained pipeline, use fixed
private 16 kHz mono samples for threshold comparison and retain every take. Make
1-second and 3-second digital-zero fixtures deterministically; keep them local
like the other audio. Add real room/fan/breathing/movement and speech recordings;
digital zeros alone do not represent a microphone. Replay the *same bytes* across
arms. The delivered patch does not add a recording store or replay UI. Without a
suitable existing replay facility, record that deterministic FP8/PAL8 replay was
not performed rather than equating policy tests or another ASR model with it.

## Experiment order and go/no-go

Use the same build and retained ASR configuration throughout. The coordinator's
empty-result fix is constant across all three runs below.

1. **A — ASR control:** `--asr-vad=off`. Record the baseline matrix and timings.
2. **Observation:** `--asr-vad=observe`. Run the full matrix; VAD proposes decisions
   but does not reject. Compare every quiet Yes/No and quiet phrase against the
   proposed decision, actual transcript, window probabilities and preserved PCM.
3. **B — Silero-only gate:** `--asr-vad=gate`, only after reviewing observation.
   Run the full matrix again, including alternating speech and silence and all
   deliberately difficult short/quiet cases. Do not change Whisper thresholds.

The initial candidate is `p >= 0.30` in any valid window. No minimum speech run,
volume threshold, clipping or normalization is used. It is a hypothesis. A single
quiet Yes or No proposed for rejection blocks promotion even when observe mode
lets ASR recover it. Do not hide a failure by repeating until it passes, speaking
louder, dropping its row, or presenting only the best attempt. Any additional
attempt must be labeled and must not replace the original.

After inspecting all cases, a threshold correction must be the only acoustic
policy change in its comparison. Retest the complete matrix on the new tested
source and retain earlier failures. Do not tune against one silent recording.
Only investigate Whisper noSpeechProb / an isolated Whisper threshold arm after
Silero has actually been measured and shown insufficient; do not activate
multiple gates together. A combined rule needs separate evidence and review.

## Batched interview instructions

Present one batch card containing all instructions and phrases **before** its
first Record. Do not open another interview form between Record and speaking.
The person should read the exact phrase first, wait for Ready, press Record,
speak once as instructed, and press Send. Gather their observations after the
batch. The agent may keep the pre-shown card visible throughout.

Keep phone position and room conditions recorded and consistent. “Quiet” means
natural low-volume speech that was valid in the control, not deliberate inaudible
mouthing. Do not increase microphone sensitivity thresholds or require raised
volume to turn a failure into a pass. Wait for each tutor reply / Ready before
the next Record; do not include the greeting in the test audio.

### Batch 1 — no speech

| Case | Instructions shown before Record |
|---|---|
| N01 | Press Record. Remain silent for 1 second. Press Send. |
| N02 | Press Record. Remain silent for 3 seconds. Press Send. |
| N03 | In normal room noise, press Record. Do not speak for 3 seconds. Press Send. |
| N04 | With the usual fan running, press Record. Do not speak for 3 seconds. Press Send. |
| N05 | Press Record. Breathe normally and make a small ordinary movement, without words, for 3 seconds. Press Send. |

In gate mode the required outcome is an empty user result, no new user fragment,
no tutor reply or TTS, the “No speech recognized” notice, and Ready with Record
usable. Watch for automatic meaning inference as well as conversation replies.
Do not confuse ASR fail-open/unavailable with a successful VAD rejection.

### Batch 2 — short and quiet

Display the literal phrase in the card before the user touches Record.

| Case | Exact phrase | Delivery |
|---|---|---|
| S01 | Yes | Quiet, once. |
| S02 | No | Quiet, once. |
| S03 | Yes | Normal voice, once. |
| S04 | No | Normal voice, once. |
| S05 | I want three, not two. | Short, quiet English. |
| S06 | Tôi không muốn mua hai cái. | Short, quiet Vietnamese. |

For every row: read the phrase first, press Record, say it once at the requested
volume, then press Send. No intervening form or question. Preserve exact displayed
ASR text locally; a tutor reply is not proof the number or negation was correct.

### Batch 3 — content and language coverage

| Case | Exact phrase | Delivery |
|---|---|---|
| S07 | I went to the shop this morning. | Normal English. |
| S08 | Sáng nay tôi đi mua đồ ăn. | Normal Vietnamese. |
| S09 | Today tôi đi siêu thị, but I did not buy coffee. | Natural English/Vietnamese code-switching. |
| S10 | siêu thị | Short phrase, natural volume. |
| S11 | I need seventeen, not seventy. | Numbers and contrast. |
| S12 | Không, tôi không đồng ý. | Vietnamese negation. |
| S13 | I do not want to cancel it. | English negation. |

Use the same read → Record → speak once → Send sequence. Keep existing known
`siêu thị` limitations separate from new regressions and compare with control;
do not reopen model optimization to improve this task's score.

### Batch 4 — boundaries, reset and lifecycle

Predeclare and keep every attempt. Run a quiet “Yes” followed by N02, a quiet “No”
followed by N02, then a quiet phrase in each language. Test “Yes” after two seconds
of initial silence and “No” followed by two seconds of final silence. These are
additional labeled boundary cases, not replacements for S01/S02.

Test End during recording; Send then End while VAD is running when the timing is
reachable; Send then End during staged ASR; and background/resume while recording
and while finalization is in flight. When a specific short VAD interval cannot be
hit, mark that timing unobserved instead of calling a later encoder cancellation
a VAD test. Verify no late transcript/save/reply/TTS, no stuck owner, no stale
cross-session state, and safe fresh Prepare/Record after native work drains.
Do not bypass the sticky memory-warning latch or restart repeatedly to bury a
warning. Any memory warning/native abort fails qualification and stops promotion.

Repeat a compact no-speech + quiet Yes/No + low-volume English/Vietnamese block
after a fresh offline cached launch/Prepare. Include a normal bilingual turn.

## Per-turn evidence and timings

For every attempted case, retain locally: case ID, arm, original attempt number,
capture UUID, sample count/duration, all window probabilities or aggregates,
active-window coverage/boundaries, candidate and actual VAD decision, exact
accepted transcript or rejection notice, user-fragment count before/after,
whether tutor generation and TTS began, Send-to-final, Send-to-Ready, VAD analysis
runtime, relevant footprint samples, memory-warning/native-crash state, and the
person's perceived responsiveness. Include cancellations, unavailable/error
fallbacks and failed attempts rather than omitting their rows.

The app emits `asr_vad_window` and `asr_vad_result` metadata only in observe/gate.
Correlate them with `asr_trial_capture`, `asr_trial_send`, `asr_trial_final` and
`asr_trial_audio` by UUID. Read the exact displayed transcript from the UI/local
ledger, not from newly public transcript logs. Absence of TTS alone is not proof
that no tutor generation began: inspect tutor start events and saved-fragment
counts as well. Verify the visible Ready state and usable Record control.

Use monotonic app timestamps, not interview/browser time. Keep first prepared,
first recorded and warmed turns separate. Report sample counts, medians and
ranges; do not claim p95 from a small block. Use the actual same-byte comparisons
when available and qualify unmatched microphone comparisons appropriately.

For rejected no-speech turns, inspect actual event absence/presence for encoder
load/execution, **Send-phase** decoder prewarm/load/execution, tutor inference and
TTS. Greeting speculative decoder prewarm has already been scheduled and remains
awaited; it is **not avoided work**. Measure the matched control-to-gate change in
Send-to-final/Ready and process footprint. Do not sum overlapping phase timers or
call sampled boundary footprint a continuous peak / model-only RAM measurement.
Do not infer latency/energy savings merely from a skipped call in source.

For genuine speech, report VAD runtime and matched full Send-to-final/first-audio
changes. Include VAD Prepare cost and retained-model footprint separately. A
correct transcript with a materially worse interaction still needs review.

## Acceptance and final publication

All must pass: intentional silence without fabricated transcript, no silent user
message, no unsolicited tutor/TTS/automatic meaning on rejection, clean Ready,
quiet Yes, quiet No, low-volume English, low-volume Vietnamese, non-regressed
normal bilingual/code-switching behavior, numbers/negation, no new memory warning
or native abort, and safe End/background/cancellation/offline behavior.

Review failures critically. Keep the smallest policy that the complete evidence
supports. Without adequate evidence, retain default off and report the task as
incomplete. The app is not fixed for ordinary use merely because a gate flag
exists or synthetic policy tests pass.

After a successful Silero-only gate qualification, make the narrow default-mode
promotion (and any already measured threshold correction) on `mvp`. Rebuild and
repeat the critical silence/quiet/bilingual/lifecycle/offline checks on the actual
promoted build. Record the tested implementation SHA and source/executable
identity. No precision or decoder heuristic changes belong in that commit.

Write a sanitized result report with starting/tested SHA, VAD artifact fingerprint,
mode/threshold, actual case counts and failures, timings/overhead/savings with
scope, warnings/crashes, retained limitations and user acceptance. Do not commit
recordings, raw logs, exact private transcripts, stores or private screenshots.
Recheck remote head, commit only owned reviewed files, fast-forward `mvp`, then
re-fetch and verify the final SHA. A result-report-only commit can follow the
runtime-tested commit; distinguish them, and report the final ref outside a
self-referential commit hash field. Stop the owned log capture at the end.
