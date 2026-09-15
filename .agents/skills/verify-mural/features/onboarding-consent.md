# Onboarding and AI consent

## User outcome

A new learner chooses learning/support languages and a conversation mode, then taps Continue without granting OpenAI consent. GPT-Live requests separate consent on first start. On-device requires English/Vietnamese and no cloud key/consent. Phase 4 UI replay is PENDING HUMAN; see `local-conversation.md` for the current paired workflow.

## How to get to it

Build the Debug simulator app, install it on the selected iPhone 17-family simulator, and launch:

```sh
xcrun simctl launch --terminate-running-process "$SIM" "$APP_BUNDLE_ID" --preview --preview-onboarding
```

The existing native UI test drives the same real screens:

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
  -only-testing:MuralUITests/MuralUITests/testOnboardingChoosesLearningAndSubtitleLanguagesWithoutAnAccount \
  test
```

Use `serve-sim` and its `$HELPER_URL/ax` endpoint for a quick visual inspection. Read fresh state after selecting French and after selecting Spanish as the subtitle language.

## How to drive it

1. Confirm `onboarding-language-fr` exists.
2. Tap French, then `onboarding-continue`.
3. Confirm the mode-specific privacy/preparation copy, privacy link, subtitle picker, and `Continue` label.
4. Select Spanish in `onboarding-meaning-picker`.
5. Confirm the example is `¡Hola!`.
6. Tap `onboarding-continue`.

## Proof

Capture the initial onboarding frame and the resulting Talk frame plus accessibility output. Success is:

- the final target caption is `Salut !`;
- the meaning caption is `¡Hola!`;
- microphone status is `Microphone off`;
- no API key field is shown;
- the targeted UI test passes.

## Gotchas

- This is a simulator-only Debug fixture and makes no provider request.
- Do not bypass onboarding by editing SwiftData or installing a marker.
- `--preview` uses in-memory records. It proves the UI flow, not persistent onboarding migration.
- A live AI response still needs the physical iPhone 17 and a key entered through Settings.

Phase 4: no duplicate agent UI automation or new tests. The existing UI test has not been rerun for this checkpoint. Use the human checklist in `local-conversation.md`; do not reset personal data to force first-use consent.
