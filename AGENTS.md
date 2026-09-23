# Project verification

- Keep Xcode output concise: pipe `xcodebuild` through the installed `xcbeautify --is-ci`, with `set -o pipefail` and `tee` saving the raw log under `.build/verification/`. For test actions, set a unique `-resultBundlePath` and use `xcrun xcresulttool get test-results summary --path <bundle> --compact`; inspect only focused failure details. Never dump full logs or result bundles into agent context.
- For visual bugs involving animation, shifting, snapping, flicker, or transient clipping, follow [verify-mural's UI animation workflow](.agents/skills/verify-mural/features/ui-animation.md). Inspect the transition, not only the settled state. If recording or input is blocked, report that limitation explicitly; do not claim the animation was verified.

## Testing
- For user-visible changes, use the relevant workflow in [verify-mural](.agents/skills/verify-mural/SKILL.md) as the primary acceptance check. Verify through the real app on the closest practical surface, simulator or physical device. A successful build or test command alone does not prove the behavior works.
- Prefer the smallest set of realistic end-to-end scenarios that meaningfully covers the changed behavior. Do not add unit tests by default or duplicate behavior already proved through the app.
- Add a focused isolated test only for an important failure mode that cannot be verified reliably or economically through the app, or for logic with no meaningful user-facing path. Identify the failure mode before writing the test; do not test helpers just for coverage.
- For bug fixes, check whether the existing verification workflow catches the specific failure. Add regression coverage when it does not; avoid duplicating coverage that already proves the behavior.
- Follow verify-mural's evidence instructions and save repeatable results under `.build/verification/`, using artifacts suited to the change, such as screenshots or video for UI behavior.
- Assert intended outcomes, not merely that code ran, something changed, or an implementation detail was used.