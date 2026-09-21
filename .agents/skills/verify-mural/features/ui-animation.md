# UI animation verification

## Trigger and outcome

Use for shifting labels, snapping, flicker, transient clipping, menu dismissal, and other defects that exist only during a transition. Reproduce through the real UI before editing. A passing UI test or correct settled screenshot does not prove an animation is correct.

Ask only for missing details: starting screen/value, exact taps, changing versus reselecting a value, which element moves and in which direction, and what should stay still. A user recording is helpful, not a prerequisite. Do not require the user to diagnose the cause.

## Prepare before recording

Follow the parent skill's build, launch, explicit simulator selection, preview fixture and readiness instructions. Finish booting, building and installing before starting a short capture. Use the existing simulator UI tests if serve-sim input or accessibility is unavailable; do not interpret accepted taps as successful navigation.

Keep before/after runs on the same device/runtime, text size, orientation, starting state and actions. Use temporary preview data, not personal conversations. Save exact commands, source state, device/runtime and expected motion under a fresh `.build/verification/` directory.

For Settings, use `--preview --ended-conversation`, then Settings. Available targeted tests in `UITests/MuralUITests.swift`:

- `testSettingsDropdownTransitions`: change and reselect mode, learning language and meaning language.
- `testOnDeviceVoiceSelectionPersists`: Apple/Mural selection, reselection and relaunch.
- `testSettingsLanguageRowAtAccessibilityTextSize`: largest accessibility text-size layout.

Run only the relevant test, with `-parallel-testing-enabled NO`, against the explicit simulator. Build-for-testing first, then use test-without-building during capture. Test assertions cover selection and settled geometry; the video is separate evidence for the transition.

## Bounded recording

Requires Python 3; `ffmpeg` and `ffprobe` are needed for frame inspection. Use the small helper rather than placing the recorder inside the same long-running tool call as a build/test. It stops after the chosen duration and sends SIGINT so simctl can finalize the movie. It also handles an early SIGTERM. SIGKILL or host failure cannot guarantee cleanup.

From the repository root, with `SIM` and `EVIDENCE` already set:

```sh
: "${SIM:?Select a simulator UDID}"
: "${EVIDENCE:?Create a fresh evidence directory}"
mkdir -p "$EVIDENCE"
nohup python3 -u .agents/skills/verify-mural/scripts/record-simulator.py \
  --device "$SIM" --output "$EVIDENCE/before.mov" --seconds 120 \
  > "$EVIDENCE/before-recording.log" 2>&1 < /dev/null &
echo "$!" > "$EVIDENCE/before-recorder.pid"
```

Record the supervisor PID, command, start time and owner in the report. In a separate bounded tool call, inspect the log for **Recording started** before driving actions. If it fails or is not ready, stop and diagnose; do not run a long test hoping capture will recover. The 120-second window starts with the recorder process, so choose a duration that covers the already-prepared interaction, not boot/build time. Set the driving tool's timeout independently.

After the interaction, verify the saved PID still belongs to this exact helper/device/output before stopping it early:

```sh
PID=$(cat "$EVIDENCE/before-recorder.pid")
ps -p "$PID" -o pid,lstart,command
# Only after matching ownership and command:
kill -TERM "$PID"
```

If the helper already exited, do not signal a reused PID. Allow up to 25 seconds for finalization, then inspect the log and validate the movie:

```sh
ffprobe -v error -show_entries format=duration -of default=nw=1 "$EVIDENCE/before.mov"
```

Require a nonempty file, positive duration and successful decoding. Repeat with fresh `after.mov`, log and PID filenames after the fix. A zero-byte file, incomplete movie, or recorder startup message alone is not evidence.

## Recorder smoke check

On an already booted, verification-owned simulator showing Mural, this checks automatic stop and movie decoding without a long test. Use a fresh evidence directory; the helper intentionally refuses overwrites. Allow 30 seconds for this tool call (3 seconds recording plus bounded finalization).

```sh
python3 .agents/skills/verify-mural/scripts/record-simulator.py \
  --device "$SIM" --output "$EVIDENCE/recorder-smoke.mov" --seconds 3 && \
ffprobe -v error -show_entries format=duration -of default=nw=1 "$EVIDENCE/recorder-smoke.mov"
```

A static screen may produce a very short movie; this checks recorder lifecycle, not an animation. To prove a feature, drive its real interaction and inspect its frames as below.

## Inspect the transition

Locate the interaction with a sparse overview, then inspect the short interval around the glitch at higher density. These example timestamps are selectors to adjust to the actual recording, not assumed event times:

```sh
ffmpeg -v error -i "$EVIDENCE/before.mov" \
  -vf 'fps=1,scale=240:-1' "$EVIDENCE/before-overview-%03d.jpg"
ffmpeg -v error -ss 10 -t 2 -i "$EVIDENCE/before.mov" \
  -vf 'fps=30,scale=360:-1,tile=6x10' -frames:v 1 "$EVIDENCE/before-transition.jpg"
```

Open the extracted images with the image-reading tool; extracting them without viewing them is not verification. Inspect full-resolution frames or the original movie when a contact sheet is too small or misses a short-lived defect. Crop only after establishing the full-screen context, and keep enough neighboring content to judge alignment and clipping. Repeat for the corresponding after interval, which may occur at a different timestamp.

Compare the same element before, during and after dismissal: its position, width, baseline, trailing inset, clipping, and any late snap. Native menu morphing is not automatically a bug; verify the specific unwanted displacement disappears. Check both directions of a value change and reselection of the current value. Inspect sibling controls using the same implementation, longest labels, large Dynamic Type, and Reduce Motion when relevant.

## Failure and cleanup

- Stop only owned captures. The helper normally finalizes automatically within its duration plus 25 seconds; a killed driving tool must not leave an unbounded recorder.
- On **Host recording is already in progress**, inspect ownership first. Do not start duplicate recorders, kill unrelated processes, or reboot another session's simulator. If an owned capture cannot be recovered, shut down only a disposable simulator owned by this verification run. Preserve logs and report the recording gap. Do not retry broadly or create new simulators repeatedly.
- A test timeout can also leave an unfinished xcresult. Label that run inconclusive, inspect processes, and separate preparation from the next bounded interaction instead of repeating the same command.
- Preserve videos, frames and reports locally; do not commit them. Review for sensitive content before sharing.
- Report build/test results, transition evidence and user phone confirmation separately. Simulator success is not phone acceptance. If capture or input is blocked, name the blocker and do not claim frame-by-frame verification.

## Proof to save

The result report must name the before/after recordings and inspected time ranges/frames, exact actions, expected versus observed motion, sibling/long-label/accessibility checks, and cleanup. A human-confirmed phone result may complete acceptance when simulator behavior differs; identify it as human-confirmed rather than agent-observed.
