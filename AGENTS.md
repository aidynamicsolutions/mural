# Project verification

- Keep Xcode output concise: pipe `xcodebuild` through the installed `xcbeautify --is-ci`, with `set -o pipefail` and `tee` saving the raw log under `.build/verification/`. For test actions, set a unique `-resultBundlePath` and use `xcrun xcresulttool get test-results summary --path <bundle> --compact`; inspect only focused failure details. Never dump full logs or result bundles into agent context.
- For visual bugs involving animation, shifting, snapping, flicker, or transient clipping, follow [verify-mural's UI animation workflow](.agents/skills/verify-mural/features/ui-animation.md). Inspect the transition, not only the settled state. If recording or input is blocked, report that limitation explicitly; do not claim the animation was verified.

## Testing
- NEVER write unit tests after you write code.
- Highly prefer E2E tests as the sole testing mechanism. Use them to verify complex features work. At the end of E2E tests, produce a verifiable and repeatable artifact. ie. A video for UI changes, a script with a definitive output for backend stuff
- If you must test a system in isolation, FIRST write all the ways it could fail, THEN write the code.
- when writing e2e test don't pick the simplest possible scenario to prove it works, pick a medium to hard scenario when verifying the work with e2e test
- For user-visible changes, use the relevant workflow in [verify-mural](.agents/skills/verify-mural/SKILL.md) as the primary acceptance check. Verify through the real app on the closest practical surface, simulator or physical device. A successful build or test command alone does not prove the behavior works.
- Prefer a focused set of realistic, medium-to-hard end-to-end scenarios that meaningfully covers the changed behavior. Do not add unit tests by default or duplicate behavior already proved through the app.
- Use focused isolated tests only for important failure modes that cannot be verified reliably or economically through the app, or for logic with no meaningful user-facing path. Enumerate all the ways the system could fail first, then write any necessary unit tests before implementation code; do not test helpers just for coverage.
- For bug fixes, check whether the existing verification workflow catches the specific failure. Add E2E regression coverage when it does not; if isolation is necessary, follow the failure-analysis and test-before-implementation requirements above. Avoid duplicating coverage that already proves the behavior.
- Follow verify-mural's evidence instructions and save verifiable, repeatable artifacts under `.build/verification/` at the end of E2E tests. Produce a video for UI changes or a script with definitive output for backend changes; screenshots may supplement UI videos.
- Assert intended outcomes, not merely that code ran, something changed, or an implementation detail was used.