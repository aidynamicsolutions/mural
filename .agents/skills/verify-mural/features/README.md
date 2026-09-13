# Verification feature map

| Feature | User outcome | Verification file |
|---|---|---|
| Onboarding and AI consent | The learner chooses languages, understands processing, and reaches Talk without an account | `onboarding-consent.md` |
| Themes, words, and settings | The learner browses practice choices, sees learning state, and can reach secure settings | `themes-words-settings.md` |
| Conversation lifecycle | The learner can see meaning, reset a finished conversation, and retain its history | `conversation-lifecycle.md` |
| Live AI conversation | The learner receives a real voice or typed response and the device handles audio and failure states | `live-ai-device.md` |

Use simulator preview fixtures and native UI tests for the first three features. Use the physical iPhone 17 through Device Hub for live provider, microphone, WebRTC, and device-only behavior. With no OpenAI API key, the live response portion is blocked; missing-key and consent guards remain testable.
