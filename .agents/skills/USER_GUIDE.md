# Project Skills User Guide

## Quick chooser

- **Create or adopt an Xcode app:** `app-creator`
- **Build, test, run, and diagnose from Terminal:** `xcode-makefiles`
- **Track small local tasks:** `simple-tasks`
- **Apple UI rules and measurements:** `apple-hig`
- **Current Apple API documentation:** `sosumi-docs`
- **Implement or optimize SwiftUI:** `swiftui-expert-skill`
- **Review SwiftUI code:** `swiftui-pro`
- **Review Swift concurrency:** `swift-concurrency-pro`
- **Write a concise commit message:** `caveman-commit`
- **Measure Xcode build times:** `xcode-build-benchmark`
- **Analyze Swift compile hotspots:** `xcode-compilation-analyzer`
- **Analyze Xcode project settings:** `xcode-project-analyzer`
- **Analyze Swift Package Manager overhead:** `spm-build-analysis`
- **Coordinate a full build optimization pass:** `xcode-build-orchestrator`
- **Apply approved build optimizations:** `xcode-build-fixer`

You can invoke them by name in a request, or run their scripts from the project root with `./.agents/skills/...`.

## `app-creator`

**Use when:** Starting a new iOS/macOS app, or adding the project tooling to an existing app.

**What it does:** Checks the Xcode toolchain, scaffolds a new XcodeGen project, or adopts an existing project without regenerating its sources. It can also install `xcode-makefiles` and `simple-tasks`.

**Start interactively:**

```bash
./.agents/skills/app-creator/scripts/init.sh
```

**Create a new app non-interactively:**

```bash
./.agents/skills/app-creator/scripts/init.sh --project-mode new \
  --name Fit40 --bundle-id com.example.Fit40 \
  --platform ios --ui swiftui --output /path/to/Fit40 \
  --no-prompt
```

**Adopt this existing project:**

```bash
./.agents/skills/app-creator/scripts/init.sh --project-mode adopt \
  --output . --name Fit40 --platform ios --no-prompt
```

Useful options: `--dry-run`, `--skip-xcode-makefiles`, `--skip-simple-tasks`, `--git-init never`, and `--git-commit never`.

**Remember:** New scaffolding requires XcodeGen. Defaults are iOS + SwiftUI, and both subskills are installed unless skipped.

## `xcode-makefiles`

**Use when:** The project already has an Xcode project/workspace and you want repeatable Terminal builds, tests, simulator runs, logs, and per-agent build isolation.

**Install:**

```bash
./.agents/skills/xcode-makefiles/scripts/install.sh \
  --project-dir . --app-name Fit40 --platform ios
```

**Daily commands:**

```bash
make diagnose                 # Check tools and project configuration
make build                   # Strict-warning build
make test                    # Run tests
make build-and-run           # Build, then launch
make run                     # Launch a previously built app
make agent-verify            # Build and test
make clean                   # Remove build artifacts
```

Use `AGENT_NAME=CODEX make build` to choose an isolated build/log/cache location. For iOS, override the simulator with `make SIM_NAME="iPhone 16" build`. Use `--mode upgrade` when replacing an existing installation.

## `simple-tasks`

**Use when:** Managing a small, committed, project-local backlog. It is not a replacement for a team issue tracker.

**Install:**

```bash
./.agents/skills/simple-tasks/scripts/install.sh --project-dir .
```

**Typical workflow:**

```bash
scripts/task.sh plan improve-settings \
  --scope "Settings UI" --files "Sources/Settings.swift" --note "Define acceptance criteria"
AGENT_NAME=CODEX scripts/task.sh claim 1 --note "Starting work"
AGENT_NAME=CODEX scripts/task.sh done 1 --note "Finished; tests pass"
```

**Useful views:**

```bash
scripts/task.sh status
scripts/task.sh upcoming
scripts/task.sh needs-planning
scripts/task.sh blocked
scripts/task.sh summary --last-24h
scripts/task.sh finished --last-week
scripts/task.sh learn
```

`plan` stores tasks in `tasks/TASKS.md` and creates optional notes in `tasks/details/`. `claim` and `done` require `AGENT_NAME`; use `--mine` with status/reporting commands to filter to that agent.

## `apple-hig`

**Use when:** Designing or reviewing Apple UI, platform behavior, components, accessibility, measurements, or Apple framework conventions.

**What it does:** Routes the request to concise, platform-specific Human Interface Guidelines references with exact rules and values.

**Ask it:** `Use apple-hig to review the Fit40 workout screen for iOS layout, accessibility, and Dynamic Type.`

**Remember:** Name the platform and UI components. Use `sosumi-docs` when you need current primary Apple documentation or API citations.

## `sosumi-docs`

**Use when:** You need an exact Apple API signature, availability rule, behavior detail, WWDC transcript, or source URL.

**What it does:** Searches and fetches current Apple documentation through the pinned project-local CLI.

```bash
SOSUMI=".tools/sosumi/node_modules/.bin/sosumi"
"$SOSUMI" search "SwiftData ModelContainer" --json
"$SOSUMI" fetch https://developer.apple.com/documentation/swiftdata/modelcontainer --json
```

**Remember:** Requires Node.js 22+ and network access. If the CLI is missing, restore it rather than using a global replacement.

## `swiftui-expert-skill`

**Use when:** Implementing, refactoring, or performance-tuning SwiftUI, including state flow, `@Observable`, view composition, lists, localization, animation, deprecated APIs, or Instruments traces.

**What it does:** Gives implementation-focused SwiftUI guidance, checks modern APIs first, and catches state, identity, availability, and invalidation problems.

**Ask it:** `Use swiftui-expert-skill to refactor this view for correct state ownership and fewer updates.`

**Remember:** Prefer native SwiftUI, gate newer APIs with `#available`, and use Liquid Glass only when explicitly requested.

## `swiftui-pro`

**Use when:** You want a comprehensive SwiftUI code review rather than a feature implementation.

**What it does:** Reviews files for genuine correctness, modern APIs, views, data flow, navigation, design, accessibility, performance, Swift, and hygiene issues. Findings include lines and before/after fixes, followed by a prioritized summary.

**Ask it:** `Use swiftui-pro to review the SwiftUI changes in this branch.`

**Remember:** It avoids nitpicks and does not introduce UIKit or third-party frameworks unless requested.

## `swift-concurrency-pro`

**Use when:** Reviewing or fixing `async`/`await`, actors, `Sendable`, task groups, cancellation, `AsyncStream`, continuations, or strict-concurrency diagnostics.

**What it does:** Reviews concurrency for races, isolation and reentrancy bugs, cancellation failures, unsafe task creation, and async test problems.

**Ask it:** `Use swift-concurrency-pro to review this data loader for actor isolation and cancellation bugs.`

**Remember:** Prefer structured concurrency and do not use `@unchecked Sendable` as a compiler-error shortcut.

## `caveman-commit`

**Use when:** You need a short Conventional Commits message from the current diff.

**What it does:** Produces a precise imperative subject, with a body only when the why, migration, security, data, or revert context matters.

**Ask it:** `/caveman-commit` or `Write a commit message for these changes.`

**Remember:** It only writes the message. It does not stage, commit, amend, or add AI attribution.

## `xcode-build-benchmark`

**Use when:** You need trustworthy clean, cached-clean, zero-change, or incremental build timings before changing anything.

**What it does:** Runs repeatable measurements, reports medians and spread, and saves timestamped artifacts in `.build-benchmark/` without modifying project files.

**Ask it:** `Benchmark this project's clean and incremental Xcode builds.`

**Remember:** Keep scheme, configuration, destination, and cache rules identical when comparing runs. Measure before optimizing.

## `xcode-compilation-analyzer`

**Use when:** Swift type checking, `CompileSwiftSources`, `SwiftEmitModule`, or module planning appears to be the bottleneck.

**What it does:** Uses timing summaries and compiler diagnostics to find expensive files, functions, expressions, module invalidation, and mixed-language costs, then creates recommendations.

**Ask it:** `Analyze the Swift compile hotspots from the latest .build-benchmark artifact.`

**Remember:** It is analysis-only by default. It ranks likely wall-clock impact and does not edit source or build settings without approval.

## `xcode-project-analyzer`

**Use when:** Build problems look like Xcode configuration, target dependencies, schemes, build settings, run scripts, module maps, or incremental invalidation.

**What it does:** Audits project- and target-level configuration and produces evidence-based recommendations for Debug and Release builds.

**Ask it:** `Audit this Xcode project's settings, schemes, and script phases for build-time problems.`

**Remember:** Recommendation-first. It requires approval before changing project files, schemes, or settings.

## `spm-build-analysis`

**Use when:** Swift Package Manager dependencies, plugins, macros, package resolution, module variants, or dependency graph shape may be slowing builds.

**What it does:** Separates package issues from project issues, verifies packages are actually linked, and reports clean/incremental/CI impact before recommending changes.

**Ask it:** `Analyze the SPM dependency graph and plugins for build overhead.`

**Remember:** It does not rewrite manifests or dependencies without explicit approval. A local package on disk is not evidence that the project uses it.

## `xcode-build-orchestrator`

**Use when:** You want a complete, evidence-based Xcode build optimization audit.

**What it does:** Benchmarks first, runs the relevant compilation, project, and SPM analyses, merges them into `.build-benchmark/optimization-plan.md`, then stops for approval. After approval it delegates changes to `xcode-build-fixer` and re-benchmarks.

**Ask it:** `Run a full recommend-first audit to reduce this project's Xcode build wait time.`

**Remember:** Phase 1 does not modify project code or settings. Wall-clock wait time, not total compiler work, is the success metric.

## `xcode-build-fixer`

**Use when:** An optimization plan has approved items, or you explicitly name a build optimization to apply.

**What it does:** Applies one logical fix at a time, verifies compilation, re-runs the same benchmark, and reports the measured before/after delta.

**Ask it:** `Apply the checked recommendations in .build-benchmark/optimization-plan.md and re-benchmark.`

**Remember:** It changes only approved items. Best-practice settings may be kept even without an immediate timing improvement; speculative regressions should be flagged.

## Recommended sequence

- **New app:** `app-creator` -> `apple-hig` for design decisions -> `swiftui-expert-skill` for implementation -> `make agent-verify`.
- **Existing app:** `xcode-makefiles` for build/run/test, then `simple-tasks` if a local backlog is useful.
- **Review:** `swiftui-pro` for broad SwiftUI issues, plus `swift-concurrency-pro` when async code is involved.
- **Exact Apple API question:** `sosumi-docs`, optionally alongside `apple-hig` for design context.
- **Build optimization:** `xcode-build-orchestrator` -> review and approve `.build-benchmark/optimization-plan.md` -> `xcode-build-fixer`.
- **Targeted build analysis:** use `xcode-compilation-analyzer`, `xcode-project-analyzer`, or `spm-build-analysis` based on the suspected bottleneck; benchmark first with `xcode-build-benchmark`.
