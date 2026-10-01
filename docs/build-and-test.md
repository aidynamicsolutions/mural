# Build and test Mural

Run from the repository root containing `Package.swift` and `Mural.xcodeproj`. Native builds use **Xcode 27 / iOS 27 SDK**; the generated app deployment target is iOS 27.0. Core checks require Swift 6 and the pinned C++ OpenCC dependency. Resolve existing locks, never upgrade pins just to build.

## Host and simulator

After dependencies resolve, Core checks need no API key or ASR weights:

```sh
set -euo pipefail
mkdir -p .build/verification
swift test > ".build/verification/swift-test-$(date +%Y%m%d-%H%M%S)-$$.log" 2>&1
active-ios-simulator-limit run -- make build
```

`make build` compiles generic arm64 Simulator only; it never boots. For UI checks, use the persistent owned Shutdown simulator from `AGENTS.md` and the [verification feature map](../.agents/skills/verify-mural/features/README.md):

```sh
: "${SIM_UDID:?Use the explicitly owned Shutdown simulator}"
active-ios-simulator-limit run -- make agent-verify SIM_UDID="$SIM_UDID" \
  TESTS='testBreezeSimplifiedDisplayPreservesRawRolesAndEnglish'
```

Simulator verification requires the installed host limiter and reviewed SimSlim 0.11.0; missing prerequisites are blockers, not permission to bypass them. Select the affected methods; `TESTS` replaces smoke. Omit it for the three-check smoke or deliberately choose `VERIFY_SUITE=qualification` for broader profile/runtime acceptance. Do not select by simulator name, create retry devices or run standalone boot/test commands. The existing runner owns locks, bounded build/runtime, screen recording, raw/formatted Xcode logs, compact xcresult and cleanup PASS/Shutdown.

Core tests cover data/security/persistence boundaries, including real OpenCC. Preview UI uses synthetic in-memory records: no microphone, ASR/tutor or durable-history proof. Use stock simulator services only for affected integrations. Missing dependencies, zero tests, skips and cleanup failures are not passes.

## Preview and project generation

Debug `--preview` uses temporary records and makes no provider calls. Add `--ended-conversation` for lifecycle UI. Drive custom fixtures only inside the parent skill's bounded simulator workflow. Remove preview arguments for actual persistence.

Regenerate when App membership or Xcode configuration changes, not for every build or documentation edit:

```sh
python3 scripts/generate_project.py
```

Preserve the selected signing/backend recipe and both package locks. Personal signing stays in ignored `Config/Local.xcconfig` included by `Config/Signing.xcconfig`. Change project recipes in the generator, never hand-edit generated files. Core source is discovered by SwiftPM; UI test membership is explicitly listed.

FireRed `--firered-runtime` / `--firered-file-probe` remain gated research options, not normal Breeze generation. See [retained support](asr/chinese/README.md#retained-firered-support).

## Physical and provider checks

Use the [physical workflow](../.agents/skills/verify-mural/references/physical-device.md) and [local feature](../.agents/skills/verify-mural/features/local-conversation.md). Physical work is explicitly opt-in, not a build dependency. Prepare before the idle/audible window; reuse installed main/runner identities, explicit paired Core AI Release and assets. `make agent-verify-device DEVICE_STAGE=prepare` is build-only. Select runtime coverage from changed contracts, not every suite.

On-device needs ready Apple Intelligence and qualified retained assets, not an OpenAI key. Premium/live checks need the user's saved API key and authorization; use [installation guidance](run-on-iphone.md). Debug-only `--verify-audio --verify-language=<registered ID>`, `--verify-meaning` and `--record-spanish-demo` are paid provider helpers, not local ASR proof. The Spanish demo uses typed input with live voice output and still needs recording/listening review.

Save new scoped evidence under `.build/verification/` and separate automated assertions, human judgments and unverified behavior. [Current evidence selection](../.agents/skills/verify-mural/SKILL.md#evidence-selection); [historical public validation](../verification/validation.md).
