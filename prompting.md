# Reporting UI and animation bugs

You do not need technical terminology or a diagnosis. Describe what looks wrong; a short screen recording helps, but is optional.

## Useful details

- Starting screen and selected value.
- Exact taps, including whether you change the value or reselect the current one.
- Which element moves, in which direction, and when it snaps back or clips.
- What should stay still or align with another element.
- Whether it happens every time, and any relevant device, text-size or Reduce Motion setting.

Example: "Settings > Voice. Reselect Apple. Its label briefly moves past the right inset, then snaps back. With Mural Voice it starts too far left. The trailing edge should stay aligned with the other rows."

## Copyable prompt

> Reproduce this UI animation bug through the real app. Record before and after, extract frames around the glitch, and inspect the transition frame by frame, not just the settled screen. It happens when I [steps]. I expect [behavior], but see [movement]. Check similar controls for the same issue. Preserve accessibility and test long labels. If recording is blocked, tell me what remains unverified.

## Why video helps

A screenshot shows one instant. A sequence of frames reveals when a label changes width, overshoots, clips, or snaps into its final position. A test that checks only the final value or layout can pass while the animation is still wrong.

The agent workflow and recording/cleanup instructions live in [verify-mural](.agents/skills/verify-mural/features/ui-animation.md).
