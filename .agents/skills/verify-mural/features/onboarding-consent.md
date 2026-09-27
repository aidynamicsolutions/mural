# Onboarding and AI consent

## User outcome

A new learner chooses learning/support languages and a conversation mode, then taps Continue without granting OpenAI consent. GPT-Live requests separate consent on first start. On-device requires English/Vietnamese and no cloud key/consent. Phase 4 UI replay is PENDING HUMAN; see `local-conversation.md` for the current paired workflow.

## How to get to it

Build the Debug simulator app, install it on the selected iPhone 17-family simulator, and launch:

Use `--preview --preview-onboarding` **inside a single bounded interaction script**, as described in the parent skill. No standalone boot/launch/mirror calls between tool turns. The focused Make command below handles build, exact ownership, default profile, results and verified shutdown.

The existing native UI test drives the same real screens:

```sh
make agent-verify SIM_UDID="$SIM_UDID" \
  TESTS='testOnboardingChoosesLearningAndSubtitleLanguagesWithoutAnAccount testExistingUserCanDeclineThenAcceptAIConsentWithoutRepeatingOnboarding'
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

The simulator lifecycle rollout reran the mapped synthetic tests. It does not supersede Phase 4 physical/human acceptance in `local-conversation.md`; do not reset personal data to force first-use consent.

## Simulator evidence boundary

Use an explicitly owned, initially Shutdown simulator. Default slimming is validated for this synthetic UI flow; use `SIMULATOR_MODE=stock` for affected system integrations. Preview History is temporary, not reboot-persistence proof. Microphone, actual model execution, speech output and native background/drain remain physical-only checks. Require cleanup PASS/Shutdown before reviewing artifacts.
