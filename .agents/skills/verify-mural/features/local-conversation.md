# On-device conversation verification

## User outcome and route

Settings > **On-device**, learning **English**, then choose **Meaning language**. Normal Talk has no ASR picker. Use **Prepare & start**, wait for real readiness, then speak/listen.

| Meaning language | Normal recognizer | Support/display |
| --- | --- | --- |
| Vietnamese | PhoWhisper CS, preserved Core AI FP8/PAL8 phone configuration | Vietnamese support; existing transcript |
| Traditional Chinese | Breeze PAL8 | Traditional support; unconverted existing transcript |
| Simplified Chinese | The same Breeze PAL8/assets | Simplified support and derived spoken-user display |

Breeze is MediaTek's retained local model, not Apple's built-in ASR. Apple Foundation Models supply the tutor/meanings/lookup/Help. English replies use the existing selected English voice. Chinese Help is on screen, never sent to English speech. Chinese automatic learning assessment remains disabled.

Missing/corrupt Breeze fails closed; it is not published in the current managed catalog. No FireRed fallback, model acquisition, re-export, provider/VAD/limit change or second recognizer merely to complete a test.

## Chinese display and history

Source contract: [Breeze implementation](../../../../docs/asr/chinese/breeze-simplified-implementation-20260928.md).

- Preserve exact raw recognition; canonical text retains pre-existing app whitespace handling. OpenCC converts Han script only, not English, grammar or regional vocabulary.
- Require `軟體 -> 软体`, not `软件`; `滑鼠` remains unchanged. Preserve English, whitespace, emoji and variation sequences. The pinned literal-`么` boundary prevents corruption of already Simplified text.
- Only finalized spoken user turns in the frozen Simplified pair gain a saved display snapshot. Typed/assistant turns and old history are not rewritten.
- Expand original recognition separately from displayed text. Reopen only the new test UUID; future Settings changes must not rewrite it.
- Edit starts with displayed wording. Explicit save makes edited canonical wording, removes stale projection and retains raw ASR. Never inspect/export the user's whole history to prove this.

Host checks use the actual dependency:

```sh
swift test --filter ChineseScriptPresentationTests
swift test --filter LocalSpeechPairPersistenceTests
```

For converter/archive/view integration, use the parent simulator lifecycle with `testBreezeSimplifiedDisplayPreservesRawRolesAndEnglish`. Add `testSimplifiedBreezeMissingAssetsDoesNotOfferFireRed` or `testMeaningLanguageSelectsOnDeviceRecognizerAndUnsupportedCombinationsFailClosed` for those changed contracts. Synthetic text/in-memory storage is not acoustic or native persistence acceptance.

## Readiness and safety

Cancel closes admission until the existing native owner actually returns. Safe navigation/next-pair selection does not admit a replacement model. Receipts and an enabled synthetic state do not substitute for actual model readiness.

Normal UIKit memory notifications log `asr_memory_warning stopped=false continuing=true` and must not independently cancel preparation, capture, inference or reply or create Resume. The sampled 3 GB ceiling, serious/critical thermal and real model faults still stop/drain and retain explicit recovery controls. No iOS safety override or lifetime memory guarantee.

Choose only the affected synthetic selectors through the [feature-map entrypoint](README.md#simulator-entrypoints):

| Contract | Selectors |
| --- | --- |
| Setup drain | `testSpeechSetupCancelKeepsAdmissionClosedUntilDrain` |
| Warning continuation | `testMemoryWarningDuringApprovedSetupDoesNotInterrupt`, `testMemoryWarningKeepsTalkActiveAndPreservesTurns` |
| Actual memory ceiling | `testMemoryCeilingInterruptionDuringApprovedSetup`, `testMemoryCeilingPausesSpeechUntilExplicitResumeAndPreservesTurns` |
| Thermal fault/recovery | `testThermalInterruptionDuringApprovedSetup`, `testThermalAlertAndExplicitResume` |

A model-free Ready fixture can intentionally have Record disabled because no ASR was loaded. Assert coordinator state, absence of warning-induced Resume and turn preservation, not a working microphone. Injected safety values are not physical resource measurements.

## Startup and preparation receipts

The user reports approximately **five seconds** after End, full quit and unchanged-install relaunch. Historical post-install receipt-backed loads took **161-172 seconds**, mostly encoder loading (141-150 s); the receipt hit and skipped prewarm. This supports installation/path-sensitive Core ML caching as the working explanation, not a traced cache result.

Record post-install/cold separately from unchanged-install/warm. Preserve native loading/validation and receipt invalidation. Do not resume cold-load profiling merely because another reinstall is slow. Reopen only for a warm regression, a relevant model/runtime/compute change or an explicit cold-start optimization request. [Warm checkpoint](../../../../docs/asr/chinese/breeze-simplified-implementation-20260928.md#user-confirmed-warm-relaunch-startup-investigation-closed-for-the-poc).

## Physical workflow

Read the [physical reference](../references/physical-device.md) before phone work. Reuse `com.kevintruong.mural.dev` and its existing `com.kevintruong.mural.dev.physicaltests.xctrunner`; the runner is not a separate personal-data sandbox.

Default `DEVICE_STAGE=prepare` builds only and retains explicit `MURAL_COREAI_TALK` Release. Its vi-en receipt metadata does not authorize a Vietnamese runtime. For Breeze use `DEVICE_PAIR=breeze-zh-CN-en` and an explicit matching `DEVICE_PREPARED`; never relabel old FireRed `zh-CN-en` stages.

Before install/runtime, refresh exact device/process/lock identity and exclusive idle/unlocked/cool readiness, close owner-coordinated mirroring and agree audio placement/listening. Stop only a freshly verified matching owned PID. Preserve signing, models, pointers, caches, voices, settings and personal history.

### Paired acceptance

The agent owns exact build/install/scoped capture and diagnosis; the user operates normal Talk and speaks/listens. Use one agreed short batch: mixed switching with a name/number, English-only and a natural response. Judge recognized words separately from rendered script. Verify Simplified meaning/lookup/Help, audible English reply and no Chinese Help playback. Scope reopen/edit to the new conversation. Restore test settings and stop only owned work; never shut down the phone.

Use bounded app-scoped capture from the physical workflow. Save source/pins/executable identity, current-PID Breeze readiness/inference and `breeze_script_display` markers. Logs contain private content and do not replace human listening or accuracy feedback. Stop/drain on genuine faults; no automatic retry, cache deletion or model substitution.

### Existing native automation

| Stage | Coverage/status |
| --- | --- |
| `breeze-check` | Model-free diagnostics/settings/selector check; restores original preference |
| `breeze-acoustic`, `breeze-multi` | Real reviewed acoustic input; requires frozen fixtures and current capture/playback gates, not broad accuracy |
| `breeze-support` | Intended meaning/lookup/Help check; previous runs failed before support acceptance, not qualified |
| `breeze-traditional` | Intended fresh Traditional acoustic regression; not run on accepted build |
| `breeze-history` | Model-free, exact new UUID reopen/edit; requires `DEVICE_BREEZE_HISTORY_SOURCE` from a successful cleaned-up acoustic run |
| `breeze-finish` | Real native converter and final preference readback; leaves English/Simplified only when authorized |
| `breeze-profile-check`, `breeze-profile` | Preparation-only Instruments tooling; blocked native initialization, no qualified cache trace |

Choose the smallest applicable stage, retain failures and read saved summary/cleanup before another command. Model-free selector/cleanup repairs precede expensive replay. Historical `DEVICE_BREEZE_MEMORY_POC=YES` was a diagnostic, not a requirement for ordinary advisory warnings; do not leave it installed or treat it as production qualification.

## Accepted evidence and limits

[Canonical closeout](../../../../docs/asr/chinese/breeze-simplified-implementation-20260928.md#mvp-closeout-user-accepted-simplified-workflow):

- User accepted live mixed names/numbers, Simplified meanings/lookup/Help, English reply audio without Chinese Help speech and stable ordinary turns.
- Real OpenCC goldens, focused synthetic UI/notification checks and native exact-UUID raw/display persistence plus explicit editing passed.
- Warm startup is approximate human timing, not a matched benchmark.
- Fresh Traditional acoustic coverage remains unchecked. Earlier prerecorded English/mixed and no-speech failures remain failures; accent causality is unproven.
- Automated support/profiler gaps remain separate from manual acceptance. A real warning in the updated ordinary binary was not explicitly observed in the latest smoke.
- No sustained resource/thermal safety or broad language/learning-quality qualification.

Keep detailed evidence private under `.build/verification/`. Older Phase 0-5 work orders live in the historical `mvp_plan.md` journal, not this feature's current task queue. For the preserved Vietnamese configuration use [precision findings](../../../../docs/asr/precision-comparison-20260918.md), [final result](../../../../docs/asr/fp8-pal8-final-validation-result-20260919.md) and the current physical recipe; do not restart rejected Nemotron/Parakeet or PAL4/PAL6 comparisons.

## Retained FireRed research

FireRed native/runtime/build/provisioning/catalog/host support remains intact. Managed acquisition/recovery passed historically; native resource qualification stopped on a warning and remains blocked. Legacy `DEVICE_PAIR=zh-CN-en` is FireRed-specific, not Breeze acceptance. See [retained support and source map](../../../../docs/asr/chinese/README.md#retained-firered-support) and [qualification tracker](../../../../docs/asr/chinese/simplified-talk-qualification-plan.md). Recheck current routing/contracts and obtain the applicable research handoff before any new expensive run; no automatic retry or warning/thermal override.
