# Chinese-English speech

## Normal Talk: shared Breeze

English learning with either Chinese meaning language uses **one Breeze ASR-25 PAL8 recognizer** for the complete Mandarin/English turn. Traditional mode keeps existing display. Simplified mode adds pinned OpenCC character conversion after recognition, with raw ASR kept separately. No English translation, grammar repair, regional vocabulary substitution or duplicate recognizer.

Read [implementation and acceptance](breeze-simplified-implementation-20260928.md) and the [local verification feature](../../../.agents/skills/verify-mural/features/local-conversation.md).

The user accepted mixed live speech with names/numbers, Simplified meaning/lookup/Help, audible English replies without Chinese Help speech and stable ordinary turns. Real OpenCC checks and native scoped history/reopen/edit evidence complement that smoke. A fresh Traditional spoken session remains unchecked; older prerecorded failures and blocked support/profiler automation remain failures.

The exact retained Breeze export is reused. Breeze has no published managed download entry in this build: missing/corrupt assets fail closed, without FireRed substitution or invented downloads. Fresh-device provisioning remains a [release blocker](../app-store-model-provisioning-release-blocker.md).

## Verification and useful provenance

| Need | Read |
| --- | --- |
| Real converter, raw/display roles, persistence and edits | [Breeze Simplified checkpoint](breeze-simplified-implementation-20260928.md) |
| Normal phone/runner workflow, focused selectors and cold/warm startup | [Local verification](../../../.agents/skills/verify-mural/features/local-conversation.md) |
| Original Breeze export and bounded native result | [Native result](breeze-native-result-20260920.md) |
| Original conversion/probe design | [Historical Breeze plan](breeze-taiwan-plan.md) |
| Corpus/audio validation and scoring boundaries | [Host checks](host-checks.md) |

The authored [Taiwan](taiwan-smoke.template.json) and [Mainland](mainland-smoke.template.json) templates are recording scripts, not measured ground truth or a required new corpus run. Review spoken words independently of ASR output; keep personal recordings and detailed transcripts private. Script conversion cannot fix incorrect recognized words.

Existing host helpers remain under `Tools/ChineseASR/`: `prepare_breeze.py` packages reviewed converted assets, `run_reference.py` replays local models and `evaluate.py` validates/scores recordings. Do not re-export or acquire weights merely to repeat accepted smoke.

## Retained FireRed support

FireRed code, native bridge/build flags, package pins/catalog, host tools and device stages remain intact. It is an explicit research/probe path, **not the normal Simplified Talk recognizer or an automatic fallback**.

Managed download/cancel/resume/integrity/activation passed at its September 28 checkpoint. Native resource qualification stopped on an iOS memory warning before decode and remains blocked. The host CTC comparison was rejected for English/mixed quality. No new native FireRed pass or promotion is implied by Breeze acceptance.

- [Qualification tracker](simplified-talk-qualification-plan.md) and [candidate checkpoint](simplified-talk-candidate.md).
- [Native qualification](firered-aed-qualification.md) and [memory investigation](firered-memory-investigation-20260920.md).
- [Memory research handoff](firered-memory-research-handoff.md).
- [Smaller-model findings](firered-smaller-model-review.md) and [host-gate handover](firered-smaller-model-handover.md).
- [Original native design](firered-aed-plan.md) and [probe instructions](local-agent-firered.md).

Legacy `DEVICE_PAIR=zh-CN-en` stages encode FireRed assumptions; Breeze stages use `breeze-zh-CN-en`. Inspect current routing and requalify affected selector/ownership contracts before expensive research work. Old approvals, failed resource runs and an available phone are not permission for an automatic retry or warning/thermal override.
