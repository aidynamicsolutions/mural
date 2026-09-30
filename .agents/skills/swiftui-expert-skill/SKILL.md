---
name: swiftui-expert-skill
description: Use when writing, reviewing, or refactoring SwiftUI code for iOS or macOS, including state management and `@Observable` data flow, view composition and invalidation/performance, lists and `ForEach` identity, environment usage, localization, animations, Liquid Glass adoption, migrating soft-deprecated APIs, or Instruments `.trace` capture/analysis for hangs, hitches, CPU hotspots, or
  excessive view updates.
---

# SwiftUI Expert Skill

## Operating Rules

- Consult relevant sections of `references/latest-apis.md` when choosing, replacing, or checking an uncertain API. Reuse applicable guidance already in context; no whole-file read is required for unrelated edits
- Prefer native SwiftUI APIs over UIKit/AppKit bridging unless bridging is necessary
- Focus on correctness and performance; do not enforce specific architectures (MVVM, VIPER, etc.)
- Encourage separating business logic from views for testability without mandating how
- Apply the compact foundation in [apple-hig](../apple-hig/SKILL.md) and Apple's API design patterns; load detailed HIG references for the affected platform, component and unresolved questions
- Only adopt Liquid Glass when explicitly requested by the user (see `references/liquid-glass.md`)
- Present performance optimizations as suggestions, not requirements
- Use `#available` gating with sensible fallbacks for version-specific APIs

## Task Workflow

Scope guidance and checks to the requested outcome, affected code and relevant risks. The router and checklist are aids, not a mandatory audit of every topic. Expand when a dependency, uncertainty or observed defect warrants it; do not refactor unrelated code merely because a pattern appears nearby.

### Review existing SwiftUI code
- Read the code under review and identify applicable risks and topics
- Check API availability or deprecation where relevant; distinguish hard deprecation from informational soft deprecation
- Use the Topic Router to resolve relevant questions, reusing guidance still available and applicable
- Validate availability gating and fallback paths against the deployment target when affected

### Improve existing SwiftUI code
- Inspect the affected implementation and select references needed for the change
- Prefer current APIs for new code; check hard-deprecated usage in the changed path and follow `references/soft-deprecation.md` for existing soft-deprecated APIs. Do not bundle unrelated migrations into a feature or bug fix
- Refactor hot paths or extract subviews when needed for the requested behavior, maintainability, or an evidenced performance issue, not as automatic extra work
- Investigate image downsampling when image size or decoding is relevant to an observed issue (see `references/image-optimization.md`)

### Implement new SwiftUI feature
- Design data flow first: identify owned vs injected state
- Structure views with clear ownership and identity; extract subviews where they clarify the feature or isolate meaningful updates
- Apply correct animation patterns (implicit vs explicit, transitions)
- Use `Button` for all tappable elements; add accessibility grouping and labels
- Gate version-specific APIs with `#available` and provide fallbacks

### Record a new Instruments trace
Trigger when the user asks to "record a trace", "profile the app", "capture a session", etc. Full reference: `references/trace-recording.md`.

1. **Confirm target** — attach to a running app, launch an app, or record all processes? If the user didn't say, ask. List connected devices when useful:
   ```bash
   python3 "${SKILL_DIR}/scripts/record_trace.py" --list-devices
   ```
2. **Pick a template based on target kind** — the `SwiftUI` template populates the SwiftUI lane on any **real device**: a physical iOS/iPadOS device **or the host Mac**. The only exception is the **iOS Simulator**, where the SwiftUI lane comes back empty — switch to `--template "Time Profiler"` in that case (still gives Time Profiler + Hangs + Animation Hitches). Always check `--list-devices`: `simulators` kind → `Time Profiler`; `devices` kind (real devices and the host Mac) → default `SwiftUI`. Full decision table in `references/trace-recording.md`.
3. **Start the recording**. For agent-driven sessions where the user says "I'll tell you when I'm done", start in the background and use a stop-file:
   ```bash
   python3 "${SKILL_DIR}/scripts/record_trace.py" \
       --device "<name|udid>" --attach "<AppName>" \
       --stop-file /tmp/stop-trace --output ~/Desktop/session.trace
   ```
   For interactive sessions, just tell the user to press Ctrl+C when done.
4. **Signal stop** — when the user says they've finished exercising the app, `touch /tmp/stop-trace`. The script cleanly SIGINTs xctrace and waits up to 60s for finalisation.
5. **Analyse** the resulting trace (flow into the "Trace-driven improvement" workflow below).

### Trace-driven improvement (Instruments `.trace` provided)
Trigger whenever the user's request references a `.trace` file. A target SwiftUI source file is **optional** — if given, cite specific lines; if not, recommend where to look based on view names and symbols the trace already reveals.

Full reference: `references/trace-analysis.md`. Summary of the composition pattern:

1. **Scope the analysis.** Ask yourself: does the user want the whole trace, or a slice?
   - "focus on X / after X / between X and Y / during X" → **resolve to a window first** (see step 2).
   - No scoping cue → analyse the whole trace.
2. **Resolve a window (only if the user scoped).** The parser exposes two discovery modes:
   ```bash
   # Find a log that marks the start/end of the region of interest:
   python3 "${SKILL_DIR}/scripts/analyze_trace.py" --trace <path> \
       --list-logs --log-message-contains "loaded feed" --log-limit 5
   # Or list os_signpost intervals (paired begin/end), filterable by name:
   python3 "${SKILL_DIR}/scripts/analyze_trace.py" --trace <path> \
       --list-signposts --signpost-name-contains "ImageDecode"
   ```
   Both modes accept `--window START_MS:END_MS` to scope discovery. Pick the `time_ms` (for logs) or `start_ms`/`end_ms` (for signposts) that match the user's description. Build a window like `--window 10400:11700`.
3. **Run the main analysis** (with or without `--window`):
   ```bash
   python3 "${SKILL_DIR}/scripts/analyze_trace.py" --trace <path> \
       --json-only --top 10 [--window START_MS:END_MS]
   ```
4. **Interpret with `references/trace-analysis.md`** — key diagnostics:
   - `main_running_coverage_pct` inside each correlation (<25% = blocked; ≥75% = CPU-bound).
   - `swiftui-causes.top_sources` reveals *why* updates keep happening — high-edge-count sources like `UserDefaultObserver.send()` or wide `EnvironmentWriter` entries are structural invalidation bugs. Fixing one often collapses many downstream hot views.
5. **When a specific view shows as expensive, ask who's invalidating it.** Use `--fanin-for "<view name>"` to get the ranked list of source nodes driving the updates.
6. **Optionally ground in source.** If the user pointed at a file, read it and match view names / user-code symbols against identifiers there. If not, recommend which files to open based on the view names SwiftUI reported.
7. **Return a prioritised plan.** Cite evidence (coverage %, hot symbol, overlapping view, log timestamp, cause-graph edges) and route each recommendation to a Topic Router reference.
8. Only edit code if the user asked for edits.

### Topic Router

Consult relevant sections when they answer a question or inform an affected risk. These links are candidates, not a reading checklist:

| Topic | Reference |
|-------|-----------|
| State management | `references/state-management.md` |
| View composition | `references/view-structure.md` |
| Performance | `references/performance-patterns.md` |
| Lists and ForEach | `references/list-patterns.md` |
| Layout | `references/layout-best-practices.md` |
| Sheets and navigation | `references/sheet-navigation-patterns.md` |
| ScrollView, scroll position, and scroll geometry | `references/scroll-patterns.md` |
| Focus management | `references/focus-patterns.md` |
| Animations (basics) | `references/animation-basics.md` |
| Animations (transitions) | `references/animation-transitions.md` |
| Animations (advanced) | `references/animation-advanced.md` |
| Accessibility | `references/accessibility-patterns.md` |
| Swift Charts | `references/charts.md` |
| Charts accessibility | `references/charts-accessibility.md` |
| Image optimization | `references/image-optimization.md` |
| Liquid Glass (iOS 26+) | `references/liquid-glass.md` |
| macOS scenes | `references/macos-scenes.md` |
| macOS window styling | `references/macos-window-styling.md` |
| macOS views | `references/macos-views.md` |
| Text patterns | `references/text-patterns.md` |
| Localization | `references/localization.md` |
| Deprecated API lookup | `references/latest-apis.md` |
| Handling soft-deprecated APIs | `references/soft-deprecation.md` |
| Previews | `references/previews.md` |
| Instruments trace analysis | `references/trace-analysis.md` |
| Instruments trace recording | `references/trace-recording.md` |

## Correctness Checklist

Review applicable items in the affected code. Consider ownership, deployment target and actual behavior before treating a pattern as a defect; this checklist does not require a whole-feature audit:

- [ ] `@State` properties are `private`
- [ ] `@Binding` only where a child modifies parent state
- [ ] Passed values never declared as `@State` or `@StateObject` (they ignore updates)
- [ ] `@StateObject` for view-owned objects; `@ObservedObject` for injected
- [ ] iOS 17+: `@State` with `@Observable`; `@Bindable` for injected observables needing bindings
- [ ] `ForEach` uses stable identity (never `.indices`/`\.offset`; id outlives the view and isn't derived from mutable content)
- [ ] Constant number of views per `ForEach` element; `List` rows are unary
- [ ] No closures stored in custom `@Environment`/`@FocusedValue` keys
- [ ] Custom `@Entry` default values are stable (no `Model()`/`Date()`/`UUID()` expressions)
- [ ] `.animation(_:value:)` always includes the `value` parameter
- [ ] `@FocusState` properties are `private`
- [ ] No redundant `@FocusState` writes inside tap gesture handlers on `.focusable()` views
- [ ] iOS 26+ APIs gated with `#available` and fallback provided
- [ ] `import Charts` present in files using chart types
- [ ] Previews use self-contained mock data; no dependency on live services or network

## References

- `references/latest-apis.md` -- On-demand deprecated-to-modern API lookup (iOS 15+ through iOS 26+)
- `references/state-management.md` -- Property wrappers, data flow, `@Observable` migration
- `references/view-structure.md` -- View extraction, container patterns, `@ViewBuilder`
- `references/performance-patterns.md` -- Hot-path optimization, update control, `_logChanges()`
- `references/list-patterns.md` -- ForEach identity, Table (iOS 16+), inline filtering pitfalls
- `references/layout-best-practices.md` -- Layout patterns, GeometryReader alternatives
- `references/accessibility-patterns.md` -- VoiceOver, Dynamic Type, grouping, traits
- `references/animation-basics.md` -- Implicit/explicit animations, timing, performance
- `references/animation-transitions.md` -- View transitions, `matchedGeometryEffect`, `Animatable`
- `references/animation-advanced.md` -- Phase/keyframe animations (iOS 17+), `@Animatable` macro (iOS 26+)
- `references/charts.md` -- Swift Charts marks, axes, selection, styling, Chart3D (iOS 26+)
- `references/charts-accessibility.md` -- Charts VoiceOver, Audio Graph, fallback strategies
- `references/sheet-navigation-patterns.md` -- Sheets, NavigationSplitView, Inspector
- `references/scroll-patterns.md` -- ScrollViewReader, scroll geometry, programmatic scrolling, target behaviors
- `references/focus-patterns.md` -- Focus state, focusable views, focused values, default focus, common pitfalls
- `references/image-optimization.md` -- AsyncImage, downsampling, caching
- `references/liquid-glass.md` -- iOS 26+ Liquid Glass effects and fallback patterns
- `references/macos-scenes.md` -- Settings, MenuBarExtra, WindowGroup, multi-window
- `references/macos-window-styling.md` -- Toolbar styles, window sizing, Commands
- `references/macos-views.md` -- HSplitView, Table, PasteButton, AppKit interop
- `references/previews.md` -- `#Preview` macro, `@Previewable` (iOS 18+), preview traits, mock data patterns for self-contained previews
- `references/text-patterns.md` -- Text initializer selection, verbatim vs localized
- `references/localization.md` -- String Catalogs, `#bundle` for packages, `LocalizedStringResource`, locale-aware formatting, RTL layout, translator comments
- `references/soft-deprecation.md` -- How to behave with soft-deprecated APIs (when to migrate, scoping rule, don't migrate during unrelated edits)
- `references/trace-analysis.md` -- Parse Instruments `.trace` files via `scripts/analyze_trace.py`; interpret main-thread coverage, high-severity SwiftUI updates, hitch narratives, and map findings back to source files
- `references/trace-recording.md` -- Record a new trace via `scripts/record_trace.py`: attach to a running app, launch one fresh, or capture a manually-stopped session; supports stop-file for agent-driven flows
