# TODO

## Make On-device Talk resume feel immediate

- Current: returning to the app takes roughly 3-4 seconds by user observation; this release's timing has not been instrumented.
- Goal: on a warm, same-conversation resume, become genuinely Ready within 1-2 seconds on the iPhone.
- First measure where time goes: draining cancelled native work, verifying model assets, restoring ASR/VAD/tokenizer and decoder/frontend state, and preparing the selected voice. Then optimize the measured bottleneck, including whether safe reuse can avoid repeating work.
- Keep the conversation and captions intact, End available, and Record disabled until speech is actually ready. For this warm conversation-resume optimization, do not run microphone capture or model re-preparation in the background or skip asset/version validation. Measure cold or invalid-cache recovery separately from the warm path.
- Acceptance: repeat the background/return flow on the physical iPhone, report the resume-to-Ready timings, and confirm no lost/duplicated conversation content or stuck speech owner.

## First-time speech setup background continuation

- [ ] When ready, implement the [background first-time setup plan](docs/asr/background-speech-setup-plan.md). First verify continued-processing support and required signing entitlements on the iPhone, then implement safe checkpoints and a Resume fallback and validate the lock/app-switch flow on device.
