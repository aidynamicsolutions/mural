# Documentation cleanup

Status: complete. Baseline: `mvp` at `31fd730`.

## Goal and scope

Help developers and AI agents find the current behavior, safe commands and useful evidence quickly. Prefer short current guides and linked historical results over duplicated work orders.

- Update the existing `.agents/skills/verify-mural` feature map; do not create another skill or runner.
- Audit all 101 baseline files under `docs/`, plus affected root/verification entrypoints.
- Preserve FireRed code, native support, flags, provisioning, catalog pins, tests and useful operating/research documents.
- No backend removal: no SenseVoice/Paraformer implementation was found in App/Core/Chinese ASR tooling; negative safety assertions remain useful.
- Preserve model/cache/pointer/history files, signing, voices, package pins, worktrees and existing staged simulator-limiter edits.
- No app behavior changes, phone access, installs, model runs, generated-file edits or remote push.

## Progress

- [x] Confirm baseline, worktrees and unrelated staged changes.
- [x] Save this plan before implementation.
- [x] Classify documentation as current guidance, historical evidence, redundant instructions or generated provenance. Baseline inventory and relative-link audit are saved privately; 20 missing links were found, mostly private evidence references in the old MVP journal.
- [x] Update the verification map for shared Breeze, Simplified display/raw separation, editing, support/voice, advisory warnings and cold/warm startup.
- [x] Reconcile current README, ASR, build/install, language and speech-setup guidance.
- [x] Clearly separate retained FireRed/research instructions from normal Breeze Talk.
- [x] Record a concrete deletion manifest, preserve unique information and update incoming links before deleting redundant documents.
- [x] Check links/anchors, referenced files/commands/selectors, whitespace and scope; confirm protected source/staging is unchanged.
- [x] Review and scope the documentation-only commit; record results and remaining limits here.

## Editing rules

Current guides describe current source and accepted behavior. Dated reports retain their measured facts, source/build identities and failures; add a short historical-status pointer when needed, not a rewritten result. Preserve export/license provenance and generated evidence. Delete a document only when its useful content is available elsewhere and its links have a valid replacement.

Verification distinguishes real dependency tests, synthetic UI, native persistence and human listening/recognition. The accepted Simplified MVP is not a broad accuracy or sustained-resource qualification. A fresh Traditional acoustic pass and blocked automated support/profiler branches remain unqualified.

The startup note stays in verification guidance: unchanged-install warm relaunch was approximately five seconds by user report; post-install loading can be much slower. Cache relocation is a supported working explanation, not a traced cache result. Do not restart profiling solely because of another cold install.

## Deletion manifest

| Redundant document | Replacement / information retained |
| --- | --- |
| `asr/chinese/local-agent-breeze.md` | Current `.agents/skills/verify-mural/features/local-conversation.md` and Breeze implementation/acceptance guide. Original conversion/probe provenance remains in `breeze-taiwan-plan.md` and `breeze-native-result-20260920.md`. The deleted prompt calls a removed installer and obsolete launch-pin workflow. |
| `asr/local-speech-review-prompt.md` | Current verification skill, `speech-setup-ux.md`, `local-speech-qa.md` and the dated findings handoff. Its duplicated work orders, old receipt policy and stale acceptance scope must not guide new work. |

Applied both deletions after preserving useful information and updating incoming links. No FireRed implementation or support document was removed. Other historical reports, research recipes and raw provenance remain.

## Validation and delivery

Documentation-only checks: relative links/anchors, referenced source/test identities, command contracts, skill frontmatter, `git diff --check`, and a final path/scope review. Reuse applicable accepted evidence; documentation changes alone do not require a simulator or phone journey.

Private audit/check output: `.build/verification/documentation-cleanup/`. The final commit must exclude the pre-existing staged changes in `AGENTS.md` and `.agents/skills/verify-mural/SKILL.md`. If runnable code changes become necessary, stop and review that scope separately.

## Results

- Audited/classified all 101 baseline documentation files: 15 current guides with evidence, 59 historical records/research, 11 retained Chinese research/support documents, four authored templates, ten raw provenance files and two redundant prompts. Added a short documentation index; retained unique measurements, failures, templates and raw artifacts.
- Updated current developer guides and all affected verification features. Shared Breeze, OpenCC versus Foundation Models, raw/display/edit roles, warning versus genuine-fault recovery, warm/cold startup and manual versus automated acceptance are explicit. Old work orders/approvals no longer masquerade as current instructions.
- Removed exactly the two prompts in the manifest. Fixed or explicitly labeled 20 unavailable historical links; the optional sibling-repository reference is plain text, not a portable dependency.
- PASS: 367 relative Markdown links and 66 heading anchors across 100 Markdown files; 26 current UI selectors, both Core filters, nine Breeze stages, 12 shell-block syntax checks, Make/generator/package/skill contracts and `git diff --check`. No new em dashes.
- PASS: 176 protected source/configuration/instruction files unchanged; pre-existing staged limiter edits preserved. Cleanup delivery contains only Markdown. No simulator/phone/build/model operations or remote push were performed.
- Local commit: the commit containing this completed plan (`git log -1 -- docs/documentation-cleanup-plan.md`). Private audit, hashes, scope and delivery identity remain in `.build/verification/documentation-cleanup/`.

Limits: historical measurements were retained, not newly requalified. Fresh Traditional acoustic, automated support/profiler, sustained-resource and first-install distribution gaps remain documented; this cleanup does not close them.
