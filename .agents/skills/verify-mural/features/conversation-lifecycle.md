# Conversation lifecycle

## User outcome

After a conversation ends, the learner can still read its meaning and transcript, reset immediately for a new conversation, and trust that the saved history remains after the automatic reset.

## How to get to it

Launch the deterministic ended-conversation fixture:

```sh
xcrun simctl launch --terminate-running-process "$SIM" "$APP_BUNDLE_ID" --preview --ended-conversation
```

Run the relevant native checks:

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
  -only-testing:MuralUITests/MuralUITests/testEndedConversationAutomaticallyReturnsToGreeting \
  -only-testing:MuralUITests/MuralUITests/testOpenTranscriptRemainsReadableAfterAutomaticReset \
  test
```

## How to drive it

1. Confirm the ended fixture shows `Jeg liker kaffe.` and `I like coffee.`.
2. Toggle Meaning off and on using the complete control, not just a label coordinate.
3. Tap `New conversation` and confirm the Talk screen returns to `Hei!` with microphone off.
4. Open Words, then Past conversations, and confirm the `A coffee?` conversation remains.
5. For the delayed path, open `Conversation transcript`, wait at least 15 seconds, and confirm both passages remain before tapping Done.

## Proof

Capture before and after screenshots, accessibility output, and the native test result. Success is a visible immediate reset, retained history, and a visible transcript after the automatic reset. No API key is needed.

## Gotchas

- The automatic reset intentionally waits 15 seconds. Use a bounded 18-second wait, not an arbitrary sleep loop.
- The Meaning label is part of a button whose hit area must be inspected from the current frame.
- `--ended-conversation` is a Debug preview fixture. It does not prove a live WebRTC close or provider session closure.
