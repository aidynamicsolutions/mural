# Project verification

- Keep Xcode output concise: pipe `xcodebuild` through the installed `xcbeautify --is-ci`, with `set -o pipefail` and `tee` saving the raw log under `.build/verification/`. For test actions, set a unique `-resultBundlePath` and use `xcrun xcresulttool get test-results summary --path <bundle> --compact`; inspect only focused failure details. Never dump full logs or result bundles into agent context.
- For visual bugs involving animation, shifting, snapping, flicker, or transient clipping, follow [verify-mural's UI animation workflow](.agents/skills/verify-mural/features/ui-animation.md). Inspect the transition, not only the settled state. If recording or input is blocked, report that limitation explicitly; do not claim the animation was verified.
