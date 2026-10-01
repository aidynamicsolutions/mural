# Run Mural on iPhone

This checkout targets **iOS 27.0** and builds with **Xcode 27**. Reuse an existing checkout, signing team and bundle identity when updating; never uninstall to resolve a setup problem.

## Choose the mode

| Mode | Requirements and boundary |
| --- | --- |
| On-device | English learning; Vietnamese or either Chinese meaning language; ready Apple Intelligence and qualified local model assets. No OpenAI key. Current acoustic acceptance is on iPhone 17. |
| Premium | Own OpenAI project key, API billing/model access and network. ChatGPT subscription credit is separate. |

Both Chinese writing modes use Breeze; Simplified adds character display conversion, not another recognizer. Exact Breeze/PhoWhisper Talk packages are not published for ordinary first-install download in this build. Existing developer-staged assets do not prove a new phone can provision itself. Missing assets fail closed; do not fetch an invented package or substitute FireRed. [Distribution blocker](asr/app-store-model-provisioning-release-blocker.md).

## Build and install

For the project's existing paired phone, follow the [physical workflow](../.agents/skills/verify-mural/references/physical-device.md), preserving explicit Core AI Release, `com.kevintruong.mural.dev` and the existing automation runner. Generic Xcode Run is not permission to replace that recipe or consume another app slot. Build-only preparation can precede a fresh idle/unlocked/cool handoff; install/launch/runtime require it.

For a first personal build:

1. Clone [this repository](https://github.com/aidynamicsolutions/mural/tree/mvp), or use the current checkout. Open `Mural.xcodeproj` beside `Package.swift`; resolve the existing package locks.
2. Add your Apple Account in **Xcode > Settings > Accounts**. In Mural's **Signing & Capabilities**, select automatic signing and your team. Choose a unique bundle ID only for a genuinely new installation; retain it for updates.
3. Connect/unlock the phone, trust the Mac and wait for pairing in **Devices and Simulators**. Enable **Settings > Privacy & Security > Developer Mode** and complete its restart/confirmation.
4. Select the Mural scheme and phone, then Run. If required, trust the development profile in **Settings > General > VPN & Device Management**.
5. Choose languages and mode. On-device uses **Prepare & start** and actual asset/model checks; normal Talk has no ASR picker. Premium saves the key only through **Settings > Advanced > Use your own API key**. Never put a key in chat, source, build settings, screenshots or logs.
6. Allow microphone access when requested. Check one short turn and audible output. On-device inference remains local after assets are ready; initial asset acquisition may need network. Premium needs Wi-Fi/cellular.

A successful launch is not microphone/model/voice qualification. See [local verification](../.agents/skills/verify-mural/features/local-conversation.md) for scoped acceptance and remaining gaps.

## Refresh and troubleshoot

A free Personal Team profile expires after seven days. Reconnect and refresh using the same team/identity, keeping the app installed. [Apple membership guidance](https://developer.apple.com/support/compare-memberships/). Export a learning backup before deliberately changing team, bundle or device; API keys and model files are not the learning backup.

| Problem | Action |
| --- | --- |
| Phone unavailable or locked | Check cable/pairing, unlock and refresh device inventory; never reuse an old PID/UDID blindly |
| Profile expired | Rebuild in place; no uninstall/data reset |
| On-device unavailable | Inspect Apple Intelligence/device/locale readiness and the selected pair; no cloud fallback |
| ASR assets missing/corrupt | Report the exact verification/provisioning blocker; preserve files and pins |
| First Prepare after reinstall is slow | Allow bounded native loading; compare unchanged-install warm relaunch separately, not repeated installs |
| Talk shows Resume | Distinguish genuine ceiling/thermal/model interruption from a notification-only warning; never hide a real fault |
| No microphone/sound | Check Mural microphone permission and current iOS audio route |
| Premium key/connection rejected | Check project billing/model access, saved key and network without exposing credentials |

[Build/test guide](build-and-test.md) and [documentation index](README.md).
