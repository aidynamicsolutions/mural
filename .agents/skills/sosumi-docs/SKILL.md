---
name: sosumi-docs
description: Uses the project-local Sosumi CLI to search and fetch current Apple Developer documentation, Human Interface Guidelines pages, WWDC transcripts, and external Swift-DocC pages as Markdown. Use when implementation or design questions require exact Apple API signatures, availability, behavior, or source citations.
compatibility: Node.js 22+ and network access. The project-local CLI is installed at .tools/sosumi/node_modules/.bin/sosumi.
metadata:
  version: "0.1.0"
  cli: "@nshipster/sosumi"
---

# Sosumi Apple Documentation

Use the project-local Sosumi CLI for targeted, current Apple documentation lookup. Sosumi renders Apple Developer pages as Markdown and preserves the original source URL.

## Locate the CLI

Run from the repository or a repository subdirectory:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
SOSUMI="$REPO_ROOT/.tools/sosumi/node_modules/.bin/sosumi"
test -x "$SOSUMI"
```

The CLI is pinned in `.tools/sosumi/package-lock.json`. It requires Node.js 22 or newer and network access. Do not install dependencies during a normal documentation lookup. If the executable is missing, report that the project-local CLI needs to be restored instead of silently using a different installation.

## Workflow

1. Identify the framework, platform, symbol, topic, or WWDC session needed.
2. If the exact page is unknown, search first:

   ```bash
   "$SOSUMI" search "SwiftData ModelContainer" --json
   ```

   Use the best matching Apple URL from the returned `results`.
3. Fetch the narrowest useful page:

   ```bash
   "$SOSUMI" fetch https://developer.apple.com/documentation/swiftdata/modelcontainer --json
   ```
4. Read the JSON `content` field as Markdown and retain the JSON `url` as the source link.
5. Base exact API signatures, availability, parameters, behavior, and constraints on the fetched content. Do not fill gaps from memory when the page is unavailable.
6. Cite the original Apple URL in the answer. Sosumi is a renderer and is not affiliated with Apple.

## Supported content

Apple API reference:

```bash
"$SOSUMI" fetch /documentation/swiftui/view --json
```

Human Interface Guidelines:

```bash
"$SOSUMI" fetch /design/human-interface-guidelines/color --json
```

WWDC transcripts:

```bash
"$SOSUMI" fetch /videos/play/wwdc2021/10133 --json
```

External Swift-DocC pages:

```bash
"$SOSUMI" fetch https://apple.github.io/swift-argument-parser/documentation/argumentparser --json
```

Only fetch HTTPS URLs. Do not include credentials, tokens, or other secrets in URLs or queries. Use `sosumi serve` only when the user explicitly asks to run a local Sosumi server.

## Keep lookups focused

Prefer one search followed by one or more specific symbol pages over fetching a broad framework page. Extract only the sections needed for the task rather than dumping an entire document into the conversation.

For HIG work, use this skill for current source pages and citations. The project-local `apple-hig` skill remains useful for its distilled routing and compact design references; use both when the task benefits from quick HIG guidance plus current source verification.

## Troubleshooting

- Empty or unsuccessful search: use a more specific framework, symbol, or topic name.
- 404 or sparse page: search for the page title and fetch the returned canonical URL.
- Network or service failure: report the blocked lookup and do not present unverified Apple-specific claims as fact.
- Missing executable: report the expected path above. Do not fall back to a global CLI because this skill is intended to use the pinned project-local version.
