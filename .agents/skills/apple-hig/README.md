# apple-hig

This project copy uses the task-selective policy in [SKILL.md](SKILL.md). The reference corpus is retained; upstream installation/packaging notes below are not instructions to replace local policy or reload the full corpus.

[![Watch the demo](https://img.youtube.com/vi/UGaSV21ff18/maxresdefault.jpg)](https://www.youtube.com/watch?v=UGaSV21ff18)

## Copy-Paste Install Prompt

Copy and paste this message to your agent to have this skill automatically installed for you.

```text
Install the apple-hig skill for me from https://github.com/justinwetch/HIGAgentSkills.git
```

An agent skill containing 156 distilled Apple Human Interface Guidelines reference files, structured for accurate, context-efficient design guidance across Apple platforms.

## What This Is

The Apple HIG is authoritative and comprehensive, but its full text is too large and too prose-heavy to load directly into an agent's context. This skill distills each HIG topic into a compact, information-dense reference file that preserves specific rules, measurements, API names, and platform distinctions while removing redundant explanatory prose.

The result is a corpus that fits within a practical context budget and gives the agent precise, citable answers rather than paraphrased recollections.

## 2026-06-09 Refresh

This branch updates the skill against the Apple Human Interface Guidelines corpus captured on 2026-06-09.

Highlights:

- 156 distilled HIG topic files
- 16 detailed foundation references, available on demand behind the compact foundation in `SKILL.md`
- Restored Design Principles coverage as a tier-1, easy-triggered reference
- Updated routing index with 1,057 trigger keywords
- Current-source review completed for every inventoried source page
- Full-corpus audit and continuity sampling recorded under `sources/apple-hig-2026-06-09/verification/`

## Coverage

| Tier | Role | Count |
|------|------|-------|
| 1 | Detailed foundations (on demand) | 16 files |
| 2 | Platform overviews | 7 files |
| 3 | Components, patterns, technologies | 103 files |
| 4 | Niche and platform-specific controls | 30 files |

**Total:** 156 files, 1,057 trigger keywords, ~140k rough tokens in the full corpus.

Platforms covered: iOS, iPadOS, macOS, tvOS, visionOS, watchOS.

## How It Works

[SKILL.md](SKILL.md) defines a compact foundation plus selective reference lookup:

- Apply the foundation to affected UI, without opening every foundation file.
- Identify the actual platform, component, interaction and unresolved question.
- Search the routing index or open a known relevant reference. Tiers, keyword matches and `related:` links identify candidates, not mandatory loads.
- Read relevant sections and broaden when uncertainty or risk calls for it. Reuse guidance still available and applicable in context.
- Preserve platform/availability and measurement qualifiers. Check primary Apple sources when a summary cannot substantiate a consequential decision.

The `routing-index.md` file maps 1,057 trigger keywords to their corresponding reference files across all four tiers.

## File Structure

```
SKILL.md               Agent entry point and loading protocol
README.md              Skill overview and release/install notes
routing-index.md       Keyword-to-file routing map (auto-generated)
distilled/             156 runtime reference files, one per HIG topic
  *.md
```

Each `distilled/*.md` file includes YAML frontmatter with `topic`, `tier`, `platforms`, `category`, `triggers`, and `related` fields. The agent reads these fields to navigate the corpus without loading every file.

## Runtime Zip

Production testing should use the script-generated runtime zip, not the full repository.

Build the Claude-safe package with:

```powershell
python scripts\package_runtime_zip.py
```

This writes `release/apple-hig.zip`. The archive contains exactly one top-level folder named `apple-hig/` with:

```
apple-hig/
  SKILL.md
  README.md
  routing-index.md
  distilled/
    *.md
```

The packaging script writes forward-slash paths only, omits directory metadata, validates archive paths, and excludes hidden files, macOS resource forks, `sources/`, `scripts/`, `process.md`, `.gitignore`, raw Apple captures, rendered pages, caches, and git metadata. Those files are useful for repo review and future maintenance, but they are not required for an installed skill and should not be loaded by production agents.

To test locally, ask Apple platform design questions that exercise the compact foundation and relevant platform/component lookups. Confirm incidental domain words do not trigger unrelated reading, while broad audits can still load broader guidance.

## Token Budget

There is no required full-corpus or foundation-bundle load. Context use starts with `SKILL.md` and grows with the references needed for the question. The previous mandatory foundation/index policy had an estimated 33,600-token floor; that is historical overhead, not the current loading target. No fixed file quota applies to complex tasks.

## Distillation Method

Each reference file was distilled from the corresponding Apple HIG source page, targeting a 75% reduction in word count. The compression preserved:

- Specific measurements, sizes, and spacing values
- API names, class names, and framework identifiers
- Platform distinctions and per-platform behavioral rules
- Do/do not rules stated as direct directives

Removed: introductory framing, change history, repetitive examples, and prose that restated rules already expressed concisely elsewhere.

Each compression pass was followed by an evaluation step to confirm that no substantive rules or specifications were lost, only extraneous prose. Files were only accepted when the distilled version could answer the same design questions as the source.

## Installation

Use the runtime zip for production testing. After extraction, the installed skill directory must be named `apple-hig` so the folder name matches the `name: apple-hig` metadata in `SKILL.md`.

The skill triggers when a request involves Apple platform design, HIG components, specific measurements, Apple framework integration, or general interface design work that should use Apple's Design Principles as grounding.

## Attribution

Content distilled from the Apple Human Interface Guidelines, available at [developer.apple.com/design/human-interface-guidelines](https://developer.apple.com/design/human-interface-guidelines). This repository is an independent reference tool and is not affiliated with or endorsed by Apple Inc.
