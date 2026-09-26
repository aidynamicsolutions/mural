# TODO

## Simplified Chinese Talk: fresh-install completion and release hosting

- [ ] Complete fresh-install FireRedASR2-AED INT8 downloads through the existing managed speech installer after the native continuation/qualification gate. No developer-staged assets should be required for MVP completion.
- Public development source: `csukuangfj2/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26` on Hugging Face, revision `374cff185e952c40fcf2f6da972a3b6cf340608d`. Encoder/decoder LFS hashes match the existing pin; downloaded tokens match too. This is not the official training checkpoint, v1, CTC or a batch re-export.
- [ ] Extend the reviewed ONNX package contract and existing installer for the exact upstream files and bundled reviewed metadata, including safe signed CDN redirects, range resume, integrity, storage and atomic activation. Do not add a second downloader or publish a fake manifest URL. Full clean-install phone verification is still required.
- [ ] Before production release, host the reviewed immutable package on the user's S3 or Cloudflare R2 service; verify actual URLs, hashes, range behavior, redirects and notices before changing the catalog. Hosting/publication requires a concrete approved destination; no credentials or uploads yet.
- [ ] Resolve FireRed's stopped/inconclusive resource qualification before ordinary-build promotion. Review the preserved idle trace, agree any justified bounded continuation, then verify real combined Talk, lifecycle, offline restart and idle/release behavior. Do not retry simply to fill the matrix.
- Human Mandarin review can use the reviewer's usual Mandarin. Check Simplified output separately; one Taiwan Mandarin speaker does not establish Mainland accent coverage.

## Make On-device Talk resume feel immediate

- Current: returning to the app takes roughly 3-4 seconds by user observation; this release's timing has not been instrumented.
- Goal: on a warm, same-conversation resume, become genuinely Ready within 1-2 seconds on the iPhone.
- First measure where time goes: draining cancelled native work, verifying model assets, restoring ASR/VAD/tokenizer and decoder/frontend state, and preparing the selected voice. Then optimize the measured bottleneck, including whether safe reuse can avoid repeating work.
- Keep the conversation and captions intact, End available, and Record disabled until speech is actually ready. For this warm conversation-resume optimization, do not run microphone capture or model re-preparation in the background or skip asset/version validation. Measure cold or invalid-cache recovery separately from the warm path.
- Acceptance: repeat the background/return flow on the physical iPhone, report the resume-to-Ready timings, and confirm no lost/duplicated conversation content or stuck speech owner.

## First-time speech setup background continuation

- [ ] When ready, implement the [background first-time setup plan](docs/asr/background-speech-setup-plan.md). First verify continued-processing support and required signing entitlements on the iPhone, then implement safe checkpoints and a Resume fallback and validate the lock/app-switch flow on device.
