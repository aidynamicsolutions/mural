---
name: apple-hig
description: >
  Apply Apple Human Interface Guidelines when designing, implementing, or
  reviewing Apple-platform UI. Includes a compact foundation and task-specific
  references for iOS, iPadOS, macOS, tvOS, visionOS, and watchOS, updated for
  OS 27 releases. Use for platform conventions, accessibility, layout, controls,
  and design questions; load detailed guidance according to the affected UI,
  not incidental words in the app's domain.
---

# Apple HIG

Apply the foundation below to UI work. Use the references to resolve relevant
questions, not as a mandatory reading sequence. Non-UI work needs HIG detail
only when it changes a user-facing contract.

## Foundation

- Prefer familiar native controls and platform behavior. Make hierarchy,
  action labels, feedback, and recovery clear. Keep destructive actions
  distinguishable and protect people from accidental data loss.
  References: [design principles](distilled/design-principles.md),
  [buttons](distilled/buttons.md), [feedback](distilled/feedback.md).
- Preserve accessible names, roles, values, states, and interaction alternatives.
  Do not rely on color alone. A control's visible outline, layout bounds,
  accessibility frame, and effective hit region are not interchangeable.
  References: [accessibility](distilled/accessibility.md),
  [VoiceOver](distilled/voiceover.md).
- Support readable, adaptable text and layout, including Dynamic Type,
  localization, right-to-left content, safe areas, and available window space.
  References: [typography](distilled/typography.md), [layout](distilled/layout.md),
  [right-to-left](distilled/right-to-left.md).
- Use system-aware colors and materials, with sufficient contrast across
  applicable appearances. Respect accessibility preferences such as Reduce
  Motion and reduced transparency when the affected presentation uses them.
  References: [color](distilled/color.md), [materials](distilled/materials.md),
  [dark mode](distilled/dark-mode.md), [motion](distilled/motion.md).
- Request sensitive access in context, explain its purpose, and preserve user
  control. Apply privacy guidance when the feature handles sensitive data or
  permissions, not merely because the app belongs to a particular category.
  Reference: [privacy](distilled/privacy.md).

These are review principles, not a requirement to open every linked file or
redesign unaffected parts of the app.

## Select relevant detail

- Identify the affected platform, component, interaction, and uncertainty from
  the request and implementation. A spacing edit and a navigation redesign
  need different depth even if both involve the same screen.
- Search [routing-index.md](routing-index.md) or go directly to a known relevant
  file in `distilled/`. Tiers and keyword matches identify candidates, not
  mandatory loads. Check the file's `platforms` and the applicable section
  before applying its advice.
- Load relevant sections and expand when a decision, risk, or dependency needs
  more context. Treat `related:` entries as optional leads, not automatic
  expansion. Incidental words such as "exercise" do not require workout,
  HealthKit, or Digital Crown guidance for an ordinary iPhone button change.
- Reuse guidance still available and applicable in context. Retrieve missing,
  changed, or uncertain guidance as needed instead of rereading a fixed bundle
  on every turn. There is no fixed reference quota: a broad audit or cross-platform
  feature can warrant broad reading.

## Apply guidance accurately

- Preserve platform, OS availability, input method, and measurement context.
  Distinguish visible spacing from hit-region padding, defaults from minimums,
  and recommendations from requirements. Do not present a project design
  choice as an Apple mandate.
- When citing a numeric rule or API, identify its applicable source and use its
  actual value and qualifiers. Do not infer a universal constant from an
  approximate or platform-specific example.
- Distilled files are summaries. If they conflict, omit relevant context, or
  cannot substantiate a consequential decision, check the primary Apple source
  using [sosumi-docs](../sosumi-docs/SKILL.md). State uncertainty rather than
  inventing a rule. Source checks should answer the unresolved question, not
  start an unrelated documentation sweep.
- Verify the changed UI with the project's verification skill. Reading HIG is
  design input, not evidence that the implementation looks or behaves correctly.

## Maintaining the index

`routing-index.md` is generated from distilled frontmatter. Change
`scripts/generate_routing_index.py` or the relevant frontmatter, then regenerate;
never edit the generated index by hand.
