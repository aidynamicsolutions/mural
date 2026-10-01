# Conversation lifecycle

## User outcome

An ended conversation remains readable until **New conversation**. Eligible learner turns stay in history; a Mural-only greeting does not create a history entry. A stored local pair and display snapshot must not follow later Settings changes.

## Drive and proof

Use the deterministic `--preview --ended-conversation` fixture only inside the [parent lifecycle](../SKILL.md#mandatory-simulator-lifecycle). Choose affected selectors:

```sh
active-ios-simulator-limit run -- make agent-verify SIM_UDID="$SIM_UDID" \
  TESTS='testMeaningLabelWorksAfterEndingAndManualResetKeepsHistory testEndedConversationStaysUntilManualNewConversation testOpenTranscriptRemainsReadableUntilManualNewConversation'
```

1. Confirm `Jeg liker kaffe.` and its English meaning. Meaning visibility is controlled in Settings, not on Talk.
2. Leave the ended state briefly; it must not reset automatically.
3. Open the transcript; learner/assistant replies remain readable.
4. Tap **New conversation**, then confirm the `A coffee?` entry remains in Words > Past conversations.

Capture the relevant state, focused results and cleanup PASS/Shutdown. Preview History is in memory, not durable-data evidence.

For Simplified spoken text, use [Chinese display/history verification](local-conversation.md#chinese-display-and-history): real converter + synthetic archive/UI, then exact new-UUID native reopen/edit when persistence changes. Display, raw recognition and explicitly edited canonical wording have distinct roles.

## Setup interruptions

Select applicable thermal/audio/route/ceiling cases, not every interruption on each edit:

```sh
active-ios-simulator-limit run -- make agent-verify SIM_UDID="$SIM_UDID" \
  TESTS='testThermalInterruptionDuringApprovedSetup testAudioInterruptionDuringApprovedSetup testRouteInterruptionDuringApprovedSetup testMemoryCeilingInterruptionDuringApprovedSetup'
```

These approve synthetic setup, interrupt the real routing and hold a noncooperative child until **Finish simulated interruption**. Resume stays disabled until return. Foreground/cooling alone must not restart; explicit recovery retains consent/inventory, clears setup UI and exposes only one recovery action.

A UIKit memory notification is different: `testMemoryWarningDuringApprovedSetupDoesNotInterrupt` and `testMemoryWarningKeepsTalkActiveAndPreservesTurns` assert continuation without warning-induced Resume. [Current safety contract](local-conversation.md#readiness-and-safety).

Fixtures prove coordinator/UI admission, not actual native drain, model readiness, background compute or physical memory/thermal safety. Preserve the separate Cancel, cold-relaunch and foreground-drain requirements when their contracts change. Native Vietnamese checklist order is encoder, decoder, final validation; synthetic progress alone cannot prove it.

## Boundaries

- A nonempty spoken/typed learner message makes history eligible; greetings and Help alone do not.
- On-device has no inactivity/time-limit ending. Background behavior and recovery must retain the same session/pair and native-owner gates.
- Premium retains its inactivity/max-duration cost guards and background closure.
- Distinguish intentional End/reset from audio/system/model interruption; do not weaken a fault assertion to obtain a pass.
- Use an owned initially Shutdown simulator, stock services only when affected, and [physical acceptance](../references/physical-device.md) for microphone/model/speech/native persistence. Never induce resource stress to test UI.
