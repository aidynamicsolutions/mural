# Conversation lifecycle

## User outcome

After a conversation ends, the learner can read its meaning and transcript, choose **New conversation** for a fresh session, and trust that an eligible history entry remains saved. A session with only Mural's greeting is discarded.

## How to get to it

Launch the deterministic ended-conversation fixture:

```sh
xcrun simctl launch --terminate-running-process "$SIM" "$APP_BUNDLE_ID" --preview --ended-conversation
```

Run the focused native checks:

```sh
xcodebuild \
  -project Mural.xcodeproj \
  -scheme Mural \
  -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  -parallel-testing-enabled NO \
  -only-testing:MuralUITests/MuralUITests/testMeaningLabelWorksAfterEndingAndManualResetKeepsHistory \
  -only-testing:MuralUITests/MuralUITests/testEndedConversationStaysUntilManualNewConversation \
  -only-testing:MuralUITests/MuralUITests/testOpenTranscriptRemainsReadableUntilManualNewConversation \
  test
```

## How to drive it

1. Confirm the ended fixture shows `Jeg liker kaffe.` and `I like coffee.`.
2. Confirm there is no meaning control on Talk. Open Settings and toggle **Meaning subtitles** off and on.
3. Leave the ended fixture open briefly. It must remain ended with **New conversation** available; it must not reset by itself.
4. Open `Conversation transcript` and confirm both the learner reply and Mural's reply remain readable.
5. Tap **New conversation** and confirm Talk returns to `Hei!`; then open Words > Past conversations and confirm the `A coffee?` history entry remains.

## Proof

Capture the ended state, Settings disclosure, and native test result. Success is a stable ended state, a Settings-only sentence-level meaning control, an eligible saved transcript, and an explicit manual transition to a new conversation. No API key is needed for the fixture.

## Approved setup interruption regressions

Run these selectors with the parent skill's arm64 simulator test command, a fresh result bundle, `-parallel-testing-enabled NO` and `-collect-test-diagnostics never`:

```sh
-only-testing:MuralUITests/MuralUITests/testThermalInterruptionDuringApprovedSetup \
-only-testing:MuralUITests/MuralUITests/testAudioInterruptionDuringApprovedSetup \
-only-testing:MuralUITests/MuralUITests/testRouteInterruptionDuringApprovedSetup \
-only-testing:MuralUITests/MuralUITests/testMemoryInterruptionDuringApprovedSetup
```

These preview-only scenarios approve a download, interrupt encoder preparation via the real safety/notification routing, and hold a non-cooperative child until the test taps **Finish simulated interruption**. Before release, Resume must be disabled and no conversation controls may appear. After release, background/foreground (and simulated cooling) must not auto-restart. Explicit Resume must retain approval/inventory, clear the setup card and restore conversation controls. Thermal recovery must show only one Resume button. Each test retains interrupted and recovered screenshots in its xcresult; export attachments for inspection.

Also retain the existing user-Cancel, checklist, cold-relaunch, foreground-drain and conversation-memory tests. These are injected coordinator/UI checks, not native drain or actual Core AI/continued-processing qualification. On the physical Vietnamese path, encoder-local validation must still say **Preparing encoder**, followed by **Preparing decoder**, then final **Validating speech**. Do not infer that ordering from the synthetic checklist test or induce thermal/memory stress on a phone.

## Lifecycle boundaries

- A non-empty spoken or typed learner message makes the transcript eligible for history. Mural-only greetings and Help responses do not.
- On-device conversations do not end for inactivity or elapsed time. Backgrounding pauses local work and foregrounding re-prepares the same in-memory session when possible.
- GPT-Live retains its inactivity and maximum-duration cost guards and its existing background close behavior.
- A forced audio, network, or system interruption saves eligible text and reports `Conversation interrupted. Start again when ready.`
