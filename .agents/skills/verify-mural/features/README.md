# Verification feature map

Read the affected feature, not every file. Use the smallest check that proves the changed contract.

| Feature | User outcome | Verification file |
| --- | --- | --- |
| Onboarding and AI consent | Choose languages/processing and reach Talk without an account | [Onboarding](onboarding-consent.md) |
| Animation and transient layout | Labels/controls stay correctly positioned during transitions | [UI animation](ui-animation.md) |
| Themes, words and settings | Browse practice, retain choices, reach secure settings/notices | [Settings](themes-words-settings.md) |
| Conversation lifecycle | End explicitly, read transcript/meaning and retain eligible history | [Lifecycle](conversation-lifecycle.md) |
| On-device English conversation | Vietnamese support or either Chinese writing mode with real local ASR/tutor/English voice | [Local conversation](local-conversation.md) |
| Simplified display and transcript provenance | Read Simplified while preserving original recognition; reopen/edit without stale projection | [Chinese display](local-conversation.md#chinese-display-and-history) |
| Speech readiness and interruptions | Safe cancellation/drain; advisory notifications do not independently pause Talk | [Readiness and safety](local-conversation.md#readiness-and-safety) |
| Premium/live AI | Real provider reply, audio and failure handling | [Live AI](live-ai-device.md) |

## Select the surface

- Simulator preview: UI, navigation, synthetic setup/safety and real converter/archive/view integration. No microphone/model/acoustic or durable-preview-history proof.
- Physical phone: explicitly authorized real microphone/model/speech and native persistence. Use the [physical workflow](../references/physical-device.md), existing main app/runner and only new test conversations.
- Human judgments: recognized words, script rendering and audible voice are separate. Logs alone do not prove hearing.
- Core/host checks: exhaustive data/security boundaries through production code; real OpenCC goldens, never a converter stub for acceptance.

Breeze Simplified MVP is user-accepted; the exact boundaries and unrun Traditional/support/profiler gates are in [local conversation](local-conversation.md#accepted-evidence-and-limits). Retained FireRed research is not Breeze evidence. Local checks need no OpenAI key; premium responses require an authorized saved key. Device Hub is a typed/visual premium fallback and stays closed for microphone checks.

## Simulator entrypoints

Use the owned, initially Shutdown simulator from `AGENTS.md`. The outer host limiter, per-device/DerivedData locks, serial tests, saved logs/recordings and cleanup PASS/Shutdown remain mandatory.

```sh
active-ios-simulator-limit run -- make build
active-ios-simulator-limit run -- make agent-verify SIM_UDID="$SIM_UDID" \
  TESTS='testBreezeSimplifiedDisplayPreservesRawRolesAndEnglish'
```

`TESTS` replaces the default three-check smoke; empty/malformed/duplicate selections and zero/skipped tests are not passes. Omit it for smoke. Use `VERIFY_SUITE=qualification` for the unchanged broader 13-check profile/runtime suite, not every feature edit. Routine runs have a shared ten-minute build/runtime/cleanup budget; qualification has 40 minutes. Do not cut cleanup short.

| Changed contract | Focused selectors; add siblings only when affected |
| --- | --- |
| Chinese script, raw disclosure and explicit edit | `testBreezeSimplifiedDisplayPreservesRawRolesAndEnglish` |
| Missing Chinese assets / pair mapping | `testSimplifiedBreezeMissingAssetsDoesNotOfferFireRed`, `testMeaningLanguageSelectsOnDeviceRecognizerAndUnsupportedCombinationsFailClosed` |
| Setup cancellation/drain | `testSpeechSetupCancelKeepsAdmissionClosedUntilDrain` |
| Advisory memory notifications | `testMemoryWarningDuringApprovedSetupDoesNotInterrupt`, `testMemoryWarningKeepsTalkActiveAndPreservesTurns` |
| Genuine memory/thermal recovery | Applicable ceiling/thermal selectors in [local conversation](local-conversation.md#readiness-and-safety) |
| Meaning/reset/history | `testMeaningLabelWorksAfterEndingAndManualResetKeepsHistory`; relevant transcript siblings |
| Voice preference retention | `testOnDeviceVoiceSelectionPersists` or `testMuralVoiceSelectionPersists` |
| Settings motion / large text | `testSettingsDropdownTransitions`, plus `testSettingsLanguageRowAtAccessibilityTextSize` when affected |
| Search and themes | `testThemeSearchFiltersLocally`, `testThemeSurvivesNavigationToWords` |
| Onboarding/consent | Relevant selectors in [onboarding](onboarding-consent.md) |

Use `SIMULATOR_MODE=stock` for integrations affected by disabled SimSlim services. Custom interaction must stay inside `scripts/verify_simulator.py`, itself entered through the host limiter. See the [parent skill](../SKILL.md) for ownership, budgets, finalizers and evidence reuse.

For non-preview Settings persistence, use the retained synthetic installation and the separate set/check/restore lifecycle tests in the [rollout guide](../../../../docs/simulator-verification-lifecycle-plan.md). Preview records do not establish durable conversations. [Measured selections and boundaries](../../../../docs/simulator-test-speedup-plan.md).
