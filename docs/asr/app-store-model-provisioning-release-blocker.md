# App Store ASR model provisioning release blocker

Date: September 22, 2026
Status: **P0 release blocker: provisioning candidate exists; distribution qualification is parked by owner, hosted artifacts and clean-install qualification incomplete**
Related implementation: Core ML preparation receipt reuse in `3a2734c`

Current source audit and primary/backup distribution TODOs: [Model distribution release plan](model-distribution-release-plan.md). The original failure below is historical. The current candidate includes explicit Taiwan Talk and an installer, but its production catalog remains empty. Upstream-compatible models can use existing hosting; the exact locally converted Breeze and PhoWhisper packages have not been located there. The owner authorized removing Full Moon to free a development-app slot; the separate Mural QA installation now installs and launches using free signing, without altering daily Mural. Hosting is deliberately deferred until hosted-download qualification. The owner is not ready to enroll in the paid Apple Developer Program, so TestFlight/App Store clean-install qualification is parked until they say they are ready and enroll. Do not initiate enrollment, spending or hosting setup. Independent local QA may continue; it does not close this release gate.

Latest context: [findings and evidence limits](local-speech-findings-handoff.md), [next-agent prompt](local-speech-review-prompt.md), [accepted cancellation closeout](speech-setup-ux.md#accepted-cancellation-follow-up), and [local installer fault tests](local-speech-qa.md#local-installer-transaction-fault-tests-2026-09-23). Start owns setup/consent/progress; cancellation stops following native components while keeping safe navigation and next-pair selection usable. Four physical cancellation/retry runs and eight simulator UI checks passed. Post-install Cancel-to-drain measured 19.315 seconds for Breeze and 15.403 seconds for PhoWhisper; the owner accepts that residual wait. The older 195.051-second Breeze result is historical, not the current closeout. The new disposable installer tests pass range, recovery, integrity, simulated storage/write and pointer-boundary cases, but do not qualify actual process kills, device-wide low storage, hosted packages, failover or customer provisioning. The catalog remains empty and this P0 distribution/clean-install gate remains open. Language-quality investigation is explicitly deferred by the owner.

## Decision

Keep ASR model weights out of the App Store bundle. After installation, download exactly one compatible model package for the device.

- Supported staged hardware: download the staged Core AI encoder and Core ML decoder support.
- Other supported hardware: download an eager Core ML package only if that path is qualified.
- Do not download both packages onto one phone unless the user explicitly changes modes.

A future staged package should omit any unused duplicate Core ML encoder, but only after a decoder-only package is converted and independently qualified.

## Why this blocks release

The preparation receipt change removes repeated explicit decoder prewarming after one validated success. It does not provision model files or create the private Core AI encoder specialization required by staged Talk.

Physical verification on an iPhone 17 running iOS 27.2 found that the app data container had been recreated. The staged assets and private Core AI specialization were absent. Normal Talk first failed because the PAL8 support manifest was missing. After the exact pinned assets were restored, Talk failed again because the Core AI encoder specialization cache was unavailable. The existing diagnostic harness could specialize the exact FP8 encoder on the phone, after which Talk succeeded.

A fresh App Store installation cannot inherit developer-staged files or a private specialization cache. Shipping the current staged path without provisioning could therefore show an unresolvable encoder-cache alert to a normal user.

This is separate from the following verification gaps, which are not themselves user-facing provisioning dependencies:

- At the original checkpoint Breeze was a development-only probe. The current candidate adds explicit Taiwan Talk; that does not qualify its distribution or language accuracy.
- The exact prerecorded transcript fixture was not retained after container recreation.
- Destructive receipt/cache clearing was avoided during cancellation verification.

## Required first-run flow

```text
Install small app
  -> detect device and OS compatibility
  -> check network and free storage
  -> download one compatible model package
  -> verify manifest and every file hash
  -> atomically publish the verified package
  -> specialize the Core AI encoder on the iPhone when required
  -> load and validate encoder/decoder contracts
  -> mark local speech ready
```

The user must be able to complete this flow entirely on the iPhone. A Mac, developer tooling, manual file transfer, and hidden launch arguments must not be required.

## Acceptance criteria

### Distribution and storage

- The archived App Store app contains no ASR model weights.
- The app downloads only the model variant selected for the current device.
- Required download size, installed size, temporary space, and available storage are shown before starting.
- Downloads are resumable and do not leave a partially published model directory.
- Old model versions are removed only after the replacement is verified and active.

### Trust and compatibility

- Device architecture, OS/API availability, model revision, precision, and compute policy are selected from a reviewed manifest.
- The manifest has an independently reviewed pin.
- Every file is checked for expected path, size, and SHA-256 before loading.
- Invalid, duplicate, unsupported, or tampered metadata fails closed.
- A staged artifact is never silently replaced with a different precision or eager backend.

### On-device specialization

- A missing Core AI specialization is detected before recording begins.
- The app can create the required specialization on supported hardware without deleting unrelated caches.
- Specialization progress and cancellation are user-visible.
- Native work is allowed to drain before another model owner starts.
- Successful specialization is followed by function and shape validation.
- An iOS update or Apple cache purge triggers a safe local rebuild, not an unrecoverable alert.

### User experience and recovery

- The current “experimental speech encoder cache is unavailable” alert is never the terminal user experience.
- Recoverable failures provide clear **Download**, **Retry**, **Manage Storage**, or **Use Another Speech Option** actions as applicable.
- Network loss, backgrounding, cancellation, low storage, and app relaunch resume safely.
- Existing conversations, settings, and downloaded valid assets survive retry and app updates.
- Readiness is shown only after required verification, specialization, and contract checks succeed.

### Verification gates

Test on physical supported devices with production signing and settings:

1. Clean installation with no model files or private specialization.
2. Interrupted and resumed download.
3. Insufficient-storage failure without data loss.
4. Manifest or file-hash mismatch failing closed.
5. Cancellation during specialization and normal loading.
6. Relaunch after successful provisioning.
7. End/start conversation and force-quit/relaunch receipt reuse.
8. OS update or safely simulated cache-miss recovery without deleting user data.
9. Memory-warning and serious-thermal handling through safe test seams.
10. App archive and installed-container size accounting.

Record backend, model identities, manifest pins, compute units, preparation timings, first/later Send timings, memory, thermal state, warnings, and transcript fixtures.

## Current evidence

The receipt implementation itself passed package tests, Apple device compilation, live microphone turns, End/new conversation, pause/resume, background/foreground, and force-quit/relaunch. On a receipt hit, explicit decoder prewarm count was zero while normal decoder load, validation, decode, and unload still ran. Subsequent fresh-process Send-to-final measured 3.455 seconds on the tested iPhone 17.

Private evidence is retained under:

```text
.build/verification/coreml-preparation-lifecycle/20260922-073130/
```

The evidence demonstrates the reuse mechanism and the missing first-install provisioning requirement. It does not qualify a production downloader or claim compatibility beyond the tested device/artifacts.

## Non-goals

- Do not bundle both eager and staged weights to hide provisioning failures.
- Do not skip independent asset verification because a receipt exists.
- Do not retain the staged decoder merely to avoid loading.
- Do not automatically delete Apple caches.
- Do not promote Breeze into Talk as a fallback without separate model and transcript qualification.
