# Verification feature map

| Feature | User outcome | Verification file |
|---|---|---|
| Onboarding and AI consent | The learner chooses languages, understands processing, and reaches Talk without an account | `onboarding-consent.md` |
| UI animations and transient layout | Labels and controls stay correctly positioned throughout transitions | `ui-animation.md` |
| Themes, words, and settings | The learner browses practice choices, sees learning state, and can reach secure settings | `themes-words-settings.md` |
| Conversation lifecycle | The learner can see meaning, reset a finished conversation, and retain its history | `conversation-lifecycle.md` |
| Local feasibility probes | On-device Apple tutor and independent bilingual microphone ASR; physical human checks | `local-conversation.md` |
| Live AI conversation | The learner receives a real voice or typed response and the device handles audio and failure states | `live-ai-device.md` |

Use simulator preview fixtures and native UI tests for onboarding, navigation/settings, and conversation lifecycle. For animation defects, also inspect recorded transition frames as described in `ui-animation.md`. Use the physical iPhone 17 through Device Hub for live provider, microphone, WebRTC, and device-only behavior. With no OpenAI API key, the live response portion is blocked; missing-key and consent guards remain testable.


## Required simulator entrypoints

- `make build`: generic arm64 compilation, no boot.
- `make agent-verify SIM_UDID=... TESTS='testMethod ...'`: preferred for known affected behavior. Smallest sufficient focused selection, replacing rather than appending smoke. Zero tests/skips are not accepted; explicitly empty/malformed/duplicate selectors fail.
- `make agent-verify SIM_UDID=<owned Shutdown UUID>`: three-check smoke fallback for broad changes: onboarding, meaning/New conversation/preview History, and voice preference relaunch retention. Default reviewed Mural SimSlim profile, serial tests, full cleanup.
- `VERIFY_SUITE=qualification`: the unchanged broader 13-check selection, including local search and recorded Settings transitions, for profile/runtime or broad integration qualification. Routine focused/smoke jobs have a shared ten-minute budget; qualification has a separate 40-minute bound. Cleanup is never cut off to meet a timing target.
- `SIMULATOR_MODE=stock`: restore/verify managed services before tests. Required for system Spotlight, Health/Home/Fitness, Contacts/Calendar/Mail, Family/Screen Time, Maps/Games/News/Weather or wallpaper integrations affected by the default profile.
- Custom scripts must be enclosed by `scripts/verify_simulator.py`; detached helper ownership/finalizers are mandatory. See the parent skill. All artifacts stay under `.build/verification/`; inspect after confirmed Shutdown.

Qualification covers preview onboarding/consent/missing-key, backend/unsupported-pair guards, synthetic setup cancel/drain/retry/language-change, voice selection/reselection/relaunch, themes/local search/secure settings, ended transcript/New conversation/preview History, large text and Settings transitions. No selection runs real audio, models, provider calls or a phone.

| Change | Start with these selectors, adding siblings only when affected |
| --- | --- |
| Settings layout/animation | `testSettingsDropdownTransitions`, plus `testSettingsLanguageRowAtAccessibilityTextSize` for large-text impact |
| Local search | `testThemeSearchFiltersLocally` (match, no results, recovery) |
| Theme navigation | `testThemeSurvivesNavigationToWords` |
| Onboarding/consent | The relevant test(s) in `onboarding-consent.md` |
| Meaning/reset/history UI | `testMeaningLabelWorksAfterEndingAndManualResetKeepsHistory`; add transcript checks if affected |
| Voice preferences | `testOnDeviceVoiceSelectionPersists` or `testMuralVoiceSelectionPersists`, as affected |
| Setup cancellation/drain | `testSpeechSetupCancelKeepsAdmissionClosedUntilDrain`; relevant interruption matrix only when semantics change |

Keep existing target-driven scrolling and meaningful readiness waits. Coordinate heavy simulator work with other projects; separate devices still contend for host resources. Timings and exact selections are saved with each run. Results and scope boundaries: [speedup plan](../../../../docs/simulator-test-speedup-plan.md).

For opt-in normal-installation persistence, run `testSimulatorLifecycleSetRetainedSettings`, then `testSimulatorLifecycleCheckRetainedSettings` in separate slim and stock lifecycles, then `testSimulatorLifecycleRestoreSettings`. Use only a dedicated Mural Lifecycle synthetic installation. These assert exact disk-backed language settings before changing them, not durable conversation creation. Commands and evidence: [rollout plan](../../../../docs/simulator-verification-lifecycle-plan.md).
