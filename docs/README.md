# Mural developer documentation

Start with the current guides below. Source and tests define behavior; a historical pass does not qualify changed inputs.

| Task | Read |
| --- | --- |
| Build, tests and project generation | [Build and test](build-and-test.md) |
| Install or refresh a personal build | [Run on iPhone](run-on-iphone.md) |
| Choose and run verification | [verify-mural feature map](../.agents/skills/verify-mural/features/README.md), then the affected feature |
| Understand On-device speech | [ASR overview](asr/README.md) and [Chinese writing modes](asr/chinese/README.md) |
| Setup, consent, cancellation and recovery | [Speech setup](asr/speech-setup-ux.md), [resumable setup design](asr/background-speech-setup-plan.md) |
| Languages, records and progress | [Language architecture](language-architecture.md), [add a language](add-language.md) |
| Phone ownership, acoustic input and cleanup | [Physical workflow](../.agents/skills/verify-mural/references/physical-device.md), [E2E lessons](physical-iphone-e2e-lessons.md) |
| Model distribution and release blockers | [Distribution plan](asr/model-distribution-release-plan.md), [P0 provisioning](asr/app-store-model-provisioning-release-blocker.md) |
| Voice choices and measured comparisons | [TTS results](tts/results.md) |
| Optional account integration | [Managed accounts](managed-accounts.md) |

## Current speech contract

On-device mode teaches **English**, with Vietnamese, Traditional Chinese or Simplified Chinese meanings. Both Chinese modes use the same retained Breeze recognizer. OpenCC derives Simplified transcript display without translating English or replacing original recognition. Apple's Foundation Models provide replies, meanings, lookup and Help; Breeze is not Apple's built-in ASR.

The user accepted the bounded Simplified MVP. Native history/editing and real converter checks complement manual speech/listening; a fresh Traditional spoken regression, broad accuracy and sustained resource safety are not established. See [the feature checkpoint](asr/chinese/breeze-simplified-implementation-20260928.md#mvp-closeout-user-accepted-simplified-workflow).

Normal Talk memory notifications are advisory; actual memory-ceiling, thermal and model-failure guards remain. Unchanged-install warm preparation was approximately five seconds by user report. A slow first preparation after reinstall is not, by itself, a reason to restart profiling.

## How to use historical documents

Dated results, Core AI checkpoints, old phase journals and experiment handoffs preserve provenance and failures, not a current task queue or reusable device authorization. Use their exact source/model/runtime identity and coverage boundaries before reusing evidence. Plans not listed as current guides are research context; do not restart their experiments just because they say “next”.

FireRed code, tooling, pins and research documents are **retained**. Its native resource qualification remains blocked; it is not the normal Simplified recognizer or a fallback. [FireRed disposition](asr/chinese/README.md#retained-firered-support).

Keep private recordings, personal transcripts, complete device logs and model artifacts out of Git. Do not rewrite dated measurements to match newer behavior, manually edit generated provenance or treat missing private artifacts as passing evidence.

## Maintaining these docs

Update the relevant guide and feature map when behavior or commands change. Link to one measured result instead of copying its journal into several runbooks. Remove duplicate work orders only after preserving unique constraints and fixing incoming links. Cleanup scope/progress: [documentation cleanup](documentation-cleanup-plan.md).
