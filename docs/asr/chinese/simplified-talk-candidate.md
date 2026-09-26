# Simplified Chinese-English Talk candidate

2026-09-26. **Opt-in source/build/UI checkpoint only. Native speech remains STOP/unqualified. Fresh-install downloads are required for completion and are not implemented yet.**

## Source and scope

Applied the eight-file handover patch against `0244dcc` on local `mvp`. Its baseline was `615123338e3c21de763aa30516d294b16cb78bf0`; the intervening local commit changed documentation only and was preserved. Patch check/application succeeded without fuzz, rejects, reset or stash.

Settings selects English learning plus Simplified Chinese meanings (`zh-CN-en`, locale `zh-Hans-CN`). Initial preparation and paused-session resume share explicit pair-to-recognizer mapping. Traditional Chinese remains Breeze; Vietnamese remains PhoWhisper with the paired phone's existing Core AI opt-in. Ordinary builds reject FireRed before setup, without ASR/cloud fallback. English IDs, old pair defaults and history remain unchanged.

Review corrections beyond the candidate:

- Fixed the catch-variable shadowing compile error in early unavailable-backend handling.
- Diagnostics use the frozen setup job's pair during cancellation/drain, even if Settings changes the next language. The backend and recognizer/support labels now agree; selecting the next pair does not release the old owner.
- Updated two stale expectations in existing package tests and extended existing UI regression coverage. No new unit-test suite.

Reviewed all eight changed source files and searched checkout call sites, old Help names and binary backend assumptions. Remaining binary code in the QA runner explicitly offers only Breeze/PhoWhisper; the package schema likewise still supports only those two backends. Neither is a FireRed fallback. Chinese assessment remains disabled. Chinese Help is cached on screen, not passed to speech. Apple availability still checks English and the selected support locale at runtime; prompts remain bounded.

The pinned recognizer's configuration, hashes, native ownership, CPU one-thread/greedy policy, full-turn VAD and resampling are unchanged. Full verification still precedes native construction; existence preflight never means Ready. New setup admission checks do not release handles during synchronous C calls.

## Native continuation disposition

**Blocked.** Reviewed the checked-in qualification and memory investigation plus the retained private diagnostic report and newer model-source evidence. No newer resource qualification was found. The warning-free diagnostic missed the planned 360-second post-decode idle interval and delayed owner-release samples; pressure cause remains inconclusive. The later source audit checked downloads, not native residency.

The next investigation remains offline inspection of preserved `idle.trace` allocation call trees and timestamped VM ranges. If attribution remains unavailable, document the gap and obtain explicit review of a properly budgeted continuation, with capture ready before preparation. Any later Talk run must cover the actual selected voice, VAD and Apple tutor, with an agreed idle/drain interval and first-warning/crash/serious-thermal/native-duration stop. No unchanged blind rerun, warning suppression, threshold increase or automatic retry is justified.

This checkpoint installed and launched the UI only. No FireRed preparation, microphone batch or tutor acceptance was requested.

## Validation

Private evidence root: `.build/verification/20260926-122733-simplified-talk/`.

| Gate | Result |
| --- | --- |
| Patch/source integration | PASS for reviewed candidate; `git diff --check` clean |
| Ordinary simulator build | PASS after correcting candidate compile error |
| Native-linked Release | PASS, Xcode 27.0 (27A5252f); actual app compiler has both `MURAL_FIRERED_FILE_PROBE` and `MURAL_COREAI_TALK`; native linker inputs and bundled pin checked |
| Ordinary project restoration | PASS, regenerated project has no diff and no FireRed links/bridge/condition |
| Existing focused core checks | 22 passed; package and pair persistence suites only |
| Simulator UI | Two existing focused tests passed on dedicated iPhone 17 Pro / iOS 27.0 (24A5423a): VI/TW/CN selection, correct headings/backend, ordinary FireRed unavailable alert, unsupported learning combinations, cancellation/drain and next-language selection |
| UI evidence | `ui-final.xcresult`, exported screenshots, and `settings-simplified-talk.mp4`; one focused replay recorded to supply video |
| Phone installation/launch | PASS, in-place `com.kevintruong.mural.dev`, physical iPhone 17 / iPhone18,3 / iOS 27.2 (24B5084k). Initial launch blocked by lock; after human unlock, normal argument-free launch succeeded |
| Phone backend identity | Launch event confirms existing Core AI GPU-preferred PhoWhisper path. FireRed pair selection/preparation was not exercised on phone |
| Live ASR/tutor/support quality | BLOCKED by continuation gate; no recognition, script, meaning, lookup, Help or audible English result claimed |
| Native lifecycle and resource/idle | BLOCKED; simulator drain fixture is not native ownership qualification |
| Fresh-install provisioning/offline | BLOCKED; exact public source located, installer integration and physical clean-install acceptance remain required |

Signed installed artifact: `Mural.app` under the evidence root, preserved outside device DerivedData. Identity: `build-identity.json`, `device-artifact.sha256`. Build/install/launch logs and scoped Mural captures stay private. The first simulator attempt timed out amid another app's foreground activity; it is not counted as a pass. The dedicated simulator runs subsequently passed. Final test review corrected the new negative Record-button assertion to use the actual `local-conversation-record-send` identifier; its subsequent replay timed out during Settings navigation before reaching that assertion. That last replay is blocked, not passed; the earlier successful app-path tests and video remain valid, and no app code changed afterward. Existing interruption deprecation and LiveTransport async-alternative warnings remain unrelated to this change.

Both owned phone captures stopped after launch. Dedicated simulator mirror stopped and simulator shut down; the shared simulator was not erased or shut down. No user models, caches, voices, history or signing identities were changed, and no weights/logs/binaries were committed.

## Fresh-install source and required next work

The user requires development fresh installs to use an existing public source, with owned S3/R2 hosting deferred until production. Do not require publishing a Mural-owned Hugging Face repository for this MVP.

Exact public repository:

<https://huggingface.co/csukuangfj2/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26/tree/374cff185e952c40fcf2f6da972a3b6cf340608d>

Use `/resolve/374cff185e952c40fcf2f6da972a3b6cf340608d/encoder.int8.onnx`, `decoder.int8.onnx` and `tokens.txt` from that repository, never moving `main`. Encoder and decoder LFS metadata exactly match the existing size/SHA-256 pins. Full downloaded tokens match the existing pin. Six bounded start/middle/end range requests returned correct HTTP 206 ranges through `us.aws.cdn.hf.co`. These are metadata/range checks, not new full model downloads or native acceptance.

The existing installer expects a published canonical manifest and `support/` file layout, neither supplied by this upstream repository. After native qualification, extend that same installer/package contract minimally to use bundled reviewed metadata and explicit upstream file paths, retaining hash, host/redirect, range, storage, cancellation and atomic-activation checks. Review signed CDN redirects rather than broadly relaxing URL validation. Native bridge separation, reproducible ordinary linkage/notices, measured preparation disk reserve and safe clean-install phone verification remain outstanding. No fake manifest URL, second downloader, archive extractor or model substitution was added.

Production hosting is tracked in `todo.md`. Before publication, obtain the concrete S3/R2 destination and approval, verify immutable package URLs and notices, then update the reviewed catalog. Model weights must remain outside the app bundle and Git.

The user can involve a Mandarin reviewer accustomed to Traditional Chinese. She can speak her usual Mandarin; Simplified versus Traditional is the expected written script, not a required pretend accent. Validate output script and meaning separately, and do not generalize one speaker's smoke to Mainland accent coverage.
