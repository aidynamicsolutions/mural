# On-device speech

On-device Talk teaches English with one selected meaning language. There is no ASR picker in normal Talk and no automatic ASR/cloud fallback.

| Meaning language | Recognizer | Spoken-user transcript |
| --- | --- | --- |
| Vietnamese | PhoWhisper CS: packed-v3 FP8 Core AI encoder + PAL8 Core ML support | Existing canonical display |
| Traditional Chinese | Breeze ASR-25 PAL8 | Existing canonical display, unconverted |
| Simplified Chinese | The same Breeze model/assets | Derived Simplified display; exact raw recognition retained |

Breeze and PhoWhisper are locally provisioned models, not Apple's built-in speech recognizer. Core ML/Core AI execute their components. Apple's on-device Foundation Models supply the English tutor and selected-language meanings/lookup/Help. Chinese Help stays on screen; English replies use the selected English voice. Chinese automatic learning assessment remains disabled.

## Current entrypoints

- [Chinese implementation and acceptance](chinese/breeze-simplified-implementation-20260928.md): OpenCC policy, raw/display/edit boundaries and bounded MVP acceptance.
- [Local verification](../../.agents/skills/verify-mural/features/local-conversation.md): choose the affected check; distinguish manual acceptance from automated results.
- [Speech setup](speech-setup-ux.md): consent, verified assets, native readiness and drain-gated cancellation.
- [Model distribution](model-distribution-release-plan.md) and [P0 release blocker](app-store-model-provisioning-release-blocker.md): retained developer assets are not customer first-install qualification.

The paired phone retains explicit `MURAL_COREAI_TALK` Release. Use the [physical build recipe](../../.agents/skills/verify-mural/references/physical-device.md#local-mvp-workflow-override), verify actual compiler/backend evidence and preserve signing/pins. Do not add FireRed/compact research flags to a normal Breeze build.

## Identity and loading

| Artifact | Pinned manifest SHA-256 |
| --- | --- |
| Breeze PAL8 | `64021fb776ee2ef4cf02c05b2a9dafde0e0700e9bf7d967b4bc5302558b5fdb4` |
| PhoWhisper packed-v3 FP8 encoder | `73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13` |
| PhoWhisper PAL8 support | `430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336` |

Keep independent pins, full file verification, model shapes, tokenizer/ABI contracts and staged h18p/runtime/cache gates. PAL8 is palettization, not an FP8 decoder. Never reuse PhoWhisper assets for Breeze.

A receipt records successful preparation and can skip matching explicit prewarm. It still loads and validates models; it does not own Apple's specialization cache. Policy 2 uses sandbox-relative identity inside the app container, retaining manifest/scope/OS/device/compute/runtime invalidation.

Breeze's historical post-install load/validation took 161-172 seconds, mostly encoder loading. The user reports roughly five seconds after End, full quit and relaunch without reinstall. Installation-related cache/path effects are the working explanation, not a traced cache classification. Record cold and warm separately; reopen profiling only for a warm regression, changed model/runtime/compute contract or an explicit cold-start optimization request.

## Speech presence and safety

The existing VAD gate uses the three-strongest-window mean of at least `0.85`, or the accepted short-reply exception: two consecutive full 4,096-sample windows each at least `0.999`. A padded partial window cannot qualify. The `.30` active-window threshold and PhoWhisper trimming remain unchanged; Breeze passes the full accepted PCM. See [the short-reply fix](short-reply-vad-fix-20260920.md).

Normal Talk UIKit memory notifications log `asr_memory_warning stopped=false continuing=true` and do not independently cancel setup, capture, inference or reply. The sampled 3 GB ceiling, serious/critical thermal and real model-error stops still require their existing drain/recovery. Warning continuation is not memory optimization or protection from iOS termination. Retained research probes can have stricter stop policies.

## Retained research and evidence

[FireRed support](chinese/README.md#retained-firered-support) remains available as gated research, not normal Chinese Talk. Its download results do not qualify its blocked native resource path. Do not relabel legacy FireRed stages as Breeze.

For the selected Vietnamese configuration, retain [precision findings](precision-comparison-20260918.md), [engineering review](final-engineering-review-20260919.md) and [final phone result](fp8-pal8-final-validation-result-20260919.md). PAL4/PAL6, stateful decoder and other dated handoffs are historical evidence, not instructions to resume optimization. Keep export provenance and useful regressions; do not clear caches or regenerate models.

Native execution, model load, Send-to-final and first audible reply are different timing boundaries. Phase footprint is not model-only RAM or lifetime safety. Keep detailed recordings/logs local; publish only sanitized findings with identities and explicit limits.
