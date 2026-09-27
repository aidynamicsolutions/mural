# UI animation verification

## Trigger and outcome

Use for shifting labels, snapping, flicker, transient clipping, menu dismissal, and other defects that exist only during a transition. Reproduce through the real UI before editing. A passing UI test or correct settled screenshot does not prove an animation is correct.

Ask only for missing details: starting screen/value, exact taps, changing versus reselecting a value, which element moves and in which direction, and what should stay still. A user recording is helpful, not a prerequisite. Do not require the user to diagnose the cause.

## Prepare and record inside the lifecycle

For an explicitly authorized **physical microphone/model transition**, use the parent skill's bounded native device workflow instead of this simulator recipe. Its prepared `.xctestrun` retains native XCTest screen recordings on success and failure; no mirror, USB microphone redirection or room-audio capture is needed. Export the selected test's attachments after cleanup, validate source decoding and inspect before/after transition frames as below. The physical Prepare checklist regression is qualified this way; preserve its sampled monotonic-state assertion too. Do not apply simulator shutdown or preview arguments to the phone.

For simulator UI work, use the same owned iPhone 17 / iOS 27.0, fixture, text size, orientation and actions in both runs. The public entrypoint requires an initially Shutdown exact UUID; it builds before boot, records only after readiness, runs serially and confirms Shutdown before returning:

```sh
make agent-verify SIM_UDID="$SIM_UDID" \
  EVIDENCE="$PWD/.build/verification/animation-$(date +%Y%m%d-%H%M%S)-$$" \
  TESTS='testSettingsDropdownTransitions'
```

Use `SIMULATOR_MODE=stock` for a stock comparison; the default is the validated Mural profile. Never omit the profile as an alleged opt-out: only stock restores persistent managed overrides.

The existing native test uses `--preview --ended-conversation`, opens Settings, changes and reselects mode, learning language and meaning language, and checks settled geometry. The command saves `settings.mov`, recorder PID/owner/log, unique `settings-transition.xcresult`, raw log, compact summary, full decode result and `cleanup.json`. The recorder is the existing `../scripts/record-simulator.py`, not a new capture framework. It is in the owned command group; graceful SIGINT finalization precedes shutdown even after failure, timeout or cancellation. Strict source decoding must pass: ffprobe with `-err_detect explode -count_frames`, positive duration, exact `nb_read_frames == nb_frames > 0`, and an empty decoder-error log. Do not treat a zero exit from a null-output transcode as sufficient; variable-rate captures can trigger output-mux timestamp errors unrelated to source decoding. Inspect the transition separately; passing native assertions alone is not visual proof.

Related focused selectors:

- `testOnDeviceVoiceSelectionPersists`: Apple/Mural choice, reselection and process-relaunch retention; no speech-output claim.
- `testSettingsLanguageRowAtAccessibilityTextSize`: largest Dynamic Type layout.

For custom interactions, prepare first with `make build`, then use the parent skill's single bounded `verify_simulator.py --cleanup-script ... -- bash interaction.sh` pattern. Put install/launch, recorder start/readiness, all input and capture **inside that script**. Do not detach a recorder and return to chat. A trap in an already-finished shell cannot protect later tool calls.

Reuse `record-simulator.py --device "$SIM" --output "$EVIDENCE/before.mov" --seconds 120` inside the owned group. Save its child PID/start identity, require `Recording started` before actions, and send SIGTERM to that still-owned child for early completion, then wait up to its 25-second finalization bound. The runner allows 30 seconds of SIGINT grace; its separate cleanup hook validates the finalized movie and restores any changed appearance/text/accessibility settings. Detached mirrors must also have a saved owner and identity-checked finalizer. Never kill an unrelated recorder/mirror or silently bypass readiness.

A smoke recording proves only capture lifecycle, not animation or microphone correctness. For a quick 3-second smoke use the same bounded custom-script pattern on the selected synthetic preview, then ffprobe plus full decode. Keep fresh filenames; the recorder refuses overwrites.

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

- Stop only owned captures. The helper normally finalizes within its duration plus 25 seconds; the enclosing runner must also confirm Shutdown. Ordinary cancellation is handled; SIGKILL/host failure requires the parent skill's ownership-checked manual recovery.
- On **Host recording is already in progress**, inspect ownership first. Do not start duplicate recorders, kill unrelated processes, or reboot another session's simulator. If an owned capture cannot be recovered, shut down only a disposable simulator owned by this verification run. Preserve logs and report the recording gap. Do not retry broadly or create new simulators repeatedly.
- A test timeout can also leave an unfinished xcresult. Label that run inconclusive, inspect processes, and separate preparation from the next bounded interaction instead of repeating the same command.
- Preserve videos, frames and reports locally; do not commit them. Review for sensitive content before sharing.
- Report build/test results, transition evidence and user phone confirmation separately. Simulator success is not phone acceptance. If capture or input is blocked, name the blocker and do not claim frame-by-frame verification.

## Proof to save

The result report must name the before/after recordings and inspected time ranges/frames, exact actions, expected versus observed motion, sibling/long-label/accessibility checks, and cleanup. A human-confirmed phone result may complete acceptance when simulator behavior differs; identify it as human-confirmed rather than agent-observed.
