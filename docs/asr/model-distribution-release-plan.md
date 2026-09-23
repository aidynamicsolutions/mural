# Model sources, backup downloads, and App Store release checklist

Status: source audit and [bounded physical local-speech QA](local-speech-qa.md) completed; dual-source downloads are **planned, not implemented or qualified**. Native preparation cancellation/recovery and cached relaunch now have automated phone evidence, including a 195-second Breeze native cancellation drain. Storage samples are not yet a release reserve.
Last checked: 2026-09-22. Candidate base: `3bae86c34072c088454afe5b235802a76b6e2c3b` plus Taiwan/provisioning working changes.

For consolidated findings, authorization, evidence limits and prioritized follow-up, read [the review handoff](local-speech-findings-handoff.md) and [next-agent prompt](local-speech-review-prompt.md).

## Decision

Prefer the existing publisher's **exact iPhone-compatible artifact** as primary and an independently hosted, byte-identical Mural copy as backup. Use Cloudflare R2 or Amazon S3 for the backup once the owner supplies the account/bucket/public HTTPS endpoint. Do not introduce another inference service. Speech still runs locally.

A different quantization, conversion, tokenizer or model is not a backup source. Source training weights are not a substitute for the locally converted models. If no public host has our exact conversion, that conversion needs a Mural primary host as well as a backup. Putting both URLs behind the same failing origin/account is not meaningful outage protection.

No bucket was created, money spent, credentials embedded, weights published, or catalog URLs invented during this audit.

### Owner decisions: hosting and paid enrollment deferred

The owner currently has **no paid Apple Developer account** and has chosen to provide hosting later. Neither is required to continue local development and the available QA checks. Use the existing free development signing; do not enroll or purchase hosting on the owner's behalf.

**Release state: parked.** The owner is not ready to enroll in the paid Apple Developer Program. Do not start TestFlight/App Store distribution qualification or ask the owner to enroll until they say they are ready. No enrollment, purchase, hosting setup or publication is authorized now. This parks the distribution gate, not independent local QA.

- Continue now: disposable QA installation, fresh-container checks, installer component/failure tests, upstream-source checks and locally staged native preparation/lifecycle measurements where practical. Label staged-model checks separately from customer download qualification.
- Hosting gate: before real primary/backup download qualification and release, obtain the selected S3/R2 account/bucket/public HTTPS endpoints from the owner, then publish verified packages and test outage recovery. Do not block unrelated local testing or invent placeholder production URLs while waiting.
- Distribution gate: before TestFlight/App Store work, the owner must enroll in the paid Apple Developer Program and complete required agreements/configuration. Free development signing is sufficient for the current local QA install but does not qualify TestFlight/App Store distribution.
- Parked release step: after the owner confirms readiness and completes enrollment, finish the approved hosting/artifact prerequisites, then perform a production-signed TestFlight clean install on supported hardware. Verify first-use provisioning and offline relaunch, review current App Store requirements, and record the evidence before treating distribution as qualified.

## What the app actually uses

| Role | Provenance and current download path | Online result | Release action |
| --- | --- | --- | --- |
| Taiwan Talk: Breeze PAL8 | Original [MediaTek-Research/Breeze-ASR-25](https://huggingface.co/MediaTek-Research/Breeze-ASR-25/tree/cffe7ccb404d025296a00758d0a33468bec3a9d0), locally converted to `breeze-asr25-pal8-v1`. `BreezeEnglishRecognizer.localDirectory()` accepts the pinned managed package or retained developer directory. No original-weight download/conversion on phone. | Original revision accessible; weight range returns 206. Original inventory has no Core ML/Core AI artifacts. Community comparisons below did not locate our encoder/decoder bytes. | Host the exact qualified PAL8 export, unless a byte-identical public copy is subsequently found. Do not switch converters/models to avoid hosting. |
| Vietnamese Talk: PhoWhisper PAL8 support | [vinai/PhoWhisper-large](https://huggingface.co/vinai/PhoWhisper-large/tree/b9136a44b5f2ca664bd0b8f74baecf1715f6eeeb) + [rinhoooo/phowhisper-large-vien-cs-asr](https://huggingface.co/rinhoooo/phowhisper-large-vien-cs-asr/tree/a98f55e0f42b2c4f1e71b3348a2b917fac0a7328), locally merged and converted. | Both exact upstream revisions accessible, original weight/adapter ranges return 206. Neither repository contains the required converted package. | Host the exact merged PAL8 support package. Base-only community PhoWhisper is not this merged model. |
| Staged Vietnamese encoder: Core AI FP8 | Locally exported/compressed/compiled from that merged PhoWhisper source. Packed v3 source and h18p AOT export; native specialization is created on the target phone. | No upstream Core AI files in either original repository. | Distribute our reviewed source/AOT assets; never distribute another phone's private Apple specialization cache. Existing local compile flag is not approval to make this the public default. |
| Speech-presence detection: Silero VAD v6.2.1 | `VadManager` from FluidAudio, [FluidInference/silero-vad-coreml](https://huggingface.co/FluidInference/silero-vad-coreml). | Exact v6.2.1 weight file accessible; full 882,304-byte file downloaded and SHA-256 matched upstream LFS metadata. | Reuse upstream. Pin the complete required bundle and mirror it; small but still a first-use network dependency. |
| Mural Voice: Supertonic-3, ANE int4 | `LocalNeuralTTS.prepare()` -> `Supertonic3ResourceDownloader.ensureModels(veVariant: "ane-int4")` plus selected voice style. [FluidInference/supertonic-3-coreml](https://huggingface.co/FluidInference/supertonic-3-coreml). | Repository and an int4 weight range accessible. | Reuse upstream after freezing the complete required variant, shared components, JSON configuration and voice styles. Mirror all required files, not only one int4 graph. Review OpenRAIL++ obligations before redistribution. |
| Tutor, meanings, lookup and Help | Apple's on-device Foundation Models through `LocalTutorModel`. | OS-managed, not a Hugging Face artifact. | Do not copy/mirror Apple system models. Keep availability and device/locale checks and honest unavailable states. |
| Apple speech voice | System voice APIs. Also the existing explicit fallback when Mural Voice is unavailable. | OS-managed. | Do not mirror system voices. This existing voice fallback is separate from identical-file download failover. |

### Older/optional recognizers, not automatic Talk substitutes

| Model | Current source | Audit result |
| --- | --- | --- |
| Stock Whisper large-v3 626 MB | `WhisperRecognizer.download()`, [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/0f63a7800b00dd0226abd051b906c246e1907482), `openai_whisper-large-v3-v20240930_626MB` | Pinned repository and encoder weight range accessible. Freeze any additional runtime tokenizer downloads too before release. |
| Vietnamese Parakeet CTC | `VietnameseEnglishRecognizer.download()`, [leakless/parakeet-ctc-0.6b-Vietnamese-coreml](https://huggingface.co/leakless/parakeet-ctc-0.6b-Vietnamese-coreml/tree/8e7545c334001a4a135aa031095538ff97487089) | Pinned compiled encoder weight range accessible. Prior mixed-language failure is unchanged; not a replacement for PhoWhisper. |
| Nemotron multilingual 1120 ms | FluidAudio `StreamingNemotronMultilingualAsrManager`, [FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML](https://huggingface.co/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML) | Selected variant decoder weight range accessible. Prior language-quality rejection unchanged. |
| FireRed v2 AED INT8 | Compile-time-only probe, locally staged from [sherpa-onnx released export](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26.tar.bz2). Original `FireRedTeam/FireRedASR2-AED@2304afed56eacfee6256dee5937ed22ffa0b64ec`. | Original revision accessible; released archive range returns 206; GitHub asset digest matches the previously recorded `43015b3f1643a5688b4821e8ed323473d38b798c4ec291471fe00df1bcfc4f1c`. No full archive redownload. Still unqualified after prior phone memory warning; do not ship it as fallback. |
| Kokoro | TTS selector explicitly rejects this blocked experiment before model load. | No active production downloader to mirror. Do not add it to the release inventory unless independently enabled/qualified. |

## Exact-byte evidence and its limits

Anonymous upstream repository requests succeeded. Bounded HTTP requests read 32 bytes at offset zero and received exact `206 Content-Range` responses for representative weights of all eight HF repositories above; a separate request checked the exact VAD v6.2.1 file and PhoWhisper's `pytorch_model.bin`. Large-file HF requests redirected to `us.aws.cdn.hf.co`. This host is observed, not a permanent exhaustive CDN allowlist. Never pin an expiring signed redirect URL as the download URL.

The VAD full-file result was:

- Revision `b419383c55c110e2c9271fa6ee0ea83d03c70d96`.
- `silero-vad-unified-256ms-v6.2.1.mlmodelc/weights/weight.bin`.
- SHA-256 `53ecc8b5081146140ab654c89109cf001f2183abddd7a2411c5081feeffff063`.

Current upstream heads observed for dependencies whose runtime uses `main`:

- Supertonic: `9f3606bf5c5ff9d6680cf6226614ac61358a24f3`.
- Nemotron: `1a41b75758b0337ff67db7d5408280aaaf23074e`.
- VAD: revision above.

These observations are **not** new approved runtime pins or proof that currently cached phone files equal these heads. Freeze and compare actual accepted files before changing their download policy.

HF search returned 13 community Breeze-ASR-25 Core ML repositories (plus one Breeze-26 repository, inspected but not a substitute). LFS weight hashes were compared against our three pinned weight files. None matched our encoder and decoder; common matches were the shared mel frontend only. For example, `fredchu/breeze-asr-25-whisperkit-coreml` and `aoiandroid/breeze-asr-25-whisperkit-coreml-ios` were inspected, not assumed incompatible from names alone. Also inspected `dqnguyen/pho-whisper-coreml`; its base conversions do not establish our merged adapter/Core AI identity. Searches are bounded, not proof of absence everywhere on the internet.

Our Breeze hashes that a genuine mirror must retain:

- Encoder: `dc4dcbad211ffe178ee7f45d429aabea5659ff58b4efc697a3c9b3872c15529b`.
- Decoder: `0ed0151851d654194e281d2125c160634d0ca5e7346916bb2d8c0e7939c5cbc0`.
- Mel: `801024dbc7a89c677be1f8b285de3409e35f7d1786c9c8d9d0d6842ac57a1c83`.

Evidence: `.build/verification/model-sources/` (private, uncommitted inventories, HTTP results and QA build/install logs). Additional middle and final 32-byte ranges passed for the exact VAD v6.2.1 weight and Supertonic L128 int4 weight (`resume-ranges.json`). Sample requests establish reachability and range support at those tested offsets, not full-package integrity, sustained uptime, mid-transfer failover or iPhone execution.

## Smallest dual-source implementation to finish

Current code is not dual-source: `ReviewedSpeechPackage` has one manifest URL and one files base URL. `SpeechHTTP` checks approved hosts but does not select a backup. FluidAudio's registry URL/repository overrides select a registry globally; they are not per-download automatic failover. Its normal resolver currently uses `/resolve/main/`. Do not claim setting that override implements safe pinned failover.

1. Freeze each accepted artifact inventory, revision, file sizes and SHA-256 digests. Keep a locally reviewed manifest pin independent of either server. Include VAD and selected TTS dependencies, not just ASR.
2. Add an ordered primary/backup location list to the existing package/download path, not a new model-provider architecture. Where upstream path layout differs from our package layout, record an explicit reviewed component/path mapping. The present single `support/` base URL cannot simply point at an arbitrary original HF repository.
3. Prefer primary; switch to the reviewed backup for bounded network/availability failures (DNS/connect/read timeout, unavailable repository, 429/5xx). Honor bounded Retry-After. Cancellation, incompatible metadata, disk-full and unsupported hardware are not reasons to switch servers. With no network, both servers fail; retain partial progress and explain that an internet connection is needed.
4. Never accept failed integrity or an unapproved redirect. If retrying a corrupted file from the backup, discard only that unpublished file and verify the replacement in full. Do not call corruption an ordinary network failure or weaken trust to succeed.
5. Resume identical immutable content from its retained offset with exact range/length checks. Only hashes establish identity; differing server ETags are not permission to use different model bytes. Wrong 200/206/range/encoding must not be appended. Reverify every file before existing atomic publication.
6. Keep old working packages active throughout. Do not switch model, precision, language pair, compute units or tutor backend. No bucket credentials in the app; read-only anonymous HTTPS only.
7. Reuse verified installed assets offline. Rebuild native caches locally if required. A backup endpoint protects downloads, not model accuracy or Apple runtime incompatibility.

## Release TODO checklist

### Artifacts and licenses

- [ ] Freeze the exact shipping build/backend/device/OS matrix. The current candidate's `PhoWhisperStagedEncoder.enabled` returns true when Core AI is available, including ordinary Release; earlier baseline-only/default-opt-in documentation is historical. A compiler flag alone does not identify the backend. Verify the actual source, compiler and runtime events; do not test one path and ship another.
- [ ] Verify source-to-export provenance and complete per-file inventories for both speech pairs, VAD, TTS shared graphs/configs and selected voices.
- [ ] Include complete required notices: Breeze Apache-2.0, PhoWhisper BSD-3-Clause, adapter CC-BY-4.0, underlying Whisper MIT; separately review Supertonic OpenRAIL++ terms and any other actually shipped dependency terms. Model-card tags alone are not legal clearance.
- [ ] Update the existing app notices to describe the actual PAL8/FP8 modifications and public distribution, replacing obsolete development-only/no-hosting wording. Preserve attribution, source links, required restriction notices and change statements. Do not modify pinned model files in place to add notices: create a reviewed new package/version or supported notice inventory.
- [ ] Retain verified source/export manifests and converter/toolchain revisions in the release record. Never include conversations, recorded speech, API keys, developer credentials or native private caches.

### Storage and publication

- [ ] **Deferred by owner:** obtain an approved R2 or S3 account/bucket and public HTTPS domain when starting hosted-download qualification. Not required for current local QA work. Review expected storage/download costs before provisioning paid resources. Credentials go through local/provider tooling, not chat or application source.
- [ ] For upstream-compatible artifacts: upstream revision URL primary, independently hosted byte-identical Mural copy backup. For local conversions: choose a Mural primary plus independent backup; two names for one bucket are not independent.
- [ ] Use immutable version/hash-prefixed object keys; never overwrite released bytes. Disable automatic content transformation/compression for weight objects. Enable versioning/recovery where supported and appropriate; retain a local verified copy regardless.
- [ ] Upload to both approved locations; read back and hash every object independently. Test anonymously from outside the owner account, including redirects, first/middle/final ranges, range past EOF and content lengths.
- [ ] Measure physical native preparation storage reserve, peak temporary use and retained package/cache sizes separately. Do not substitute old cache logical sizes or guesses for measured reserve.
- [ ] Run `Tools/ASR/make_speech_package.py --help`, generate immutable packages from the reviewed exports using the actual reserve and URLs, independently review the printed manifest pins, then populate the source catalog. Tool currently emits a single-source entry; update it with the runtime location representation before dual-source release.

### Automated and physical acceptance

- [x] Local installer transaction fault tests: mocked exact-range resume after network loss/cancel and fresh invocation, bad manifest pin/file hash, simulated low storage before and during transfer, read-only staging write failure, full-object `200`, unreviewed redirect, immutable-directory publication, injected pointer-boundary interruption, recovery without redownload, and old-version retention. Evidence: `.build/verification/speech-installer/20260923T025140Z/`.
- [ ] Remaining local/system evidence: actual OS process termination/relaunch at transfer and publication boundaries and actual device-wide low-storage behavior (only on a disposable device). Hosted CDN/backup failover and selected-mode customer provisioning also remain open behind the hosting gate. The local suite uses synthetic plans and injected faults; it is not a hosted or release install.
- [ ] Primary healthy: no backup request. Primary unreachable/404/429/503: bounded backup attempt. Both unavailable: clear retry state, no partial publication. Cancellation: no surprise backup attempt.
- [ ] Kill during primary download; relaunch with primary blocked; resume from backup and verify exact final files. Inject wrong ranges, oversized/truncated bodies and mixed-version backup content; fail closed.
- [ ] Test selected-mode-only download plus required VAD/TTS; no hidden download of the other ASR mode. Account for all first-use dependencies in storage/consent UI.
- [ ] Disposable physical installation: no staged models, receipts or private caches; download, prepare, conversation, relaunch, cancellation during native work and safe cache-miss recovery. Preserve daily app data.
- [ ] Simulated disk-full first. Real exhaustion requires a dedicated disposable device; do not fill the user's daily phone without separate authorization.
- [ ] Archive the exact release configuration and run `Tools/ASR/check_speech_archive.py --archive <actual.xcarchive> --package <vi-package.json> --package <tw-package.json>`. Record archive/IPA sizes separately from App Store thinned size and installed footprint.
- [ ] **PARKED - TestFlight/App Store release qualification:** wait until the owner says they are ready and has enrolled in the paid Apple Developer Program. Then complete required agreements/configuration and approved hosting/artifact prerequisites, and repeat essential clean first-use/offline reuse through a production-signed TestFlight install on supported hardware. Review current App Store requirements for downloadable model assets and all APIs. A local development build is not distribution approval.
- [ ] Keep mixed-language recognition and Traditional Chinese teaching quality as separate acceptance gates. A successful mirror cannot fix the known mixed-span recognition failure.

### Operations after release

- [ ] Retain old immutable packages while supported app versions pin them. Roll forward by adding a reviewed version; never repair a published version by replacing bytes.
- [ ] Periodically probe each source independently with a small bounded range and verify selected objects. Alert on primary and backup failures independently. Do not build a custom monitoring service if existing hosting/CI monitoring suffices.
- [ ] Rehearse primary outage before release and after endpoint/pin changes. Document restoration/rollback without invalidating installed valid packages.

## QA provisioning result: installation unblocked

With owner approval, Xcode automatic signing successfully provisioned `com.kevintruong.mural.qa` using the existing free team; Release with `MURAL_COREAI_TALK` built successfully. No tracked signing configuration changed.

The first install failed at the maximum **three apps signed with a free developer profile**. The owner subsequently authorized removing Full Moon. Verified the installed app name `fullmoon`, bundle `com.kevintruong.fullmoon`, version 1.2 (3); removed only that app, then installed and launched **Mural QA** on the paired iPhone 17. The daily `com.kevintruong.mural.dev` installation remained present with identical before/after app metadata and bundle URL. No daily data or model caches were reset.

The initial display-name build override did not override the explicit Info.plist. Corrected the QA build with a separate temporary Info.plist (`.build/verification/model-sources/QA-Info.plist`); the final signed build is labeled **Mural QA**. The tracked daily Info.plist is unchanged. The current derived Release product is the QA build, not a daily-app reinstall artifact. Check bundle identity before any subsequent install.

Before the explicit first launch, the accessible QA container had no model files, preparation receipts or learning store; only ordinary system directories and a launch snapshot were listed. Launch succeeded. This proves installation and a fresh app-container starting point, not speech readiness, absent device-wide Apple caches, a completed native-storage measurement or customer provisioning.

Evidence: `.build/verification/qa-install-20260922-143213/`. Hosting is intentionally deferred; leave the production catalog empty and hosted-download/dual-source release gates open while continuing independent local checks.
