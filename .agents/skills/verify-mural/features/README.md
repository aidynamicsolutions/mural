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
