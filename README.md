# Mural

**The language app you eventually delete.**

<p align="center">
  <img src="marketing/screenshots/iphone-17-spanish/01-hola.png" width="24%" alt="Mural greeting in Spanish with voice controls" />
  <img src="marketing/screenshots/iphone-17-spanish/02-conversacion.png" width="24%" alt="Spanish café conversation with English meaning subtitles" />
  <img src="marketing/screenshots/iphone-17-spanish/03-temas.png" width="24%" alt="Conversation themes for learning Spanish" />
  <img src="marketing/screenshots/iphone-17-spanish/04-palabras.png" width="24%" alt="Spanish vocabulary with three levels of recall strength" />
</p>

Mural is a native iPhone app for learning through conversation. Speak to a warm, animated orb, follow the meaning when you need it, and practise words again in later conversations. Mural adjusts the challenge from the evidence in your replies.

Built with SwiftUI, Liquid Glass and local SwiftData storage. **On-device** mode practises English with Vietnamese or either Chinese meaning language, using local speech models and Apple's Foundation Models. **Premium** connects directly to OpenAI with your own API key. Neither requires a Mural account or a running Mac during practice.

This is a development build: ordinary Breeze/PhoWhisper first-install model downloads are not published yet. On-device acceptance reused qualified assets on iPhone 17; a fresh installation is not automatically ready. See the [current documentation](docs/README.md) and [distribution blocker](docs/asr/app-store-model-provisioning-release-blocker.md).

## Get started

Use Xcode 27, an iPhone running iOS 27 or later, and an Apple Account for signing. On-device requires ready Apple Intelligence, a supported English/support pair and verified local assets; no OpenAI key. Premium requires network and your own API project with billing/model access. A ChatGPT subscription does not provide API credit.

### Install with a local AI agent

If Codex or another coding agent has access to your Mac's files and terminal, paste the prompt below. The agent can clone, build and install Mural. You handle Apple Account sign-in and team selection in Xcode, device trust and Developer Mode prompts, and API-key entry inside the app. The [iPhone installation guide](docs/run-on-iphone.md) covers each step.

```text
Help me build and install Mural on my iPhone from
https://github.com/aidynamicsolutions/mural, branch mvp.

Prefer the existing checkout. Read AGENTS.md, docs/README.md,
docs/run-on-iphone.md and docs/build-and-test.md. Check Xcode 27 and its iOS
tools, preserve package locks, run Core checks and compile through the
existing bounded simulator entrypoint. Preserve the paired phone's intended
backend/signing recipe; do not replace it with a generic build.

Guide me through adding my Apple Account and choosing my signing team in
Xcode. For a first installation, help me choose a unique bundle identifier if
needed. Preserve the existing team and identifier when updating Mural, and
do not uninstall it or erase its learning data.

Detect my connected iPhone, build with the configured signing team, install
Mural and launch it. Tell me when I need to unlock the phone, trust this Mac
or the developer profile, enable Developer Mode, or approve a system prompt.

I will choose languages and mode. For On-device, verify Apple/model
readiness; missing unpublished assets are a blocker, not permission to fetch
invented packages or substitute FireRed. For Premium I will enter my key in
Settings > Advanced > Use your own API key. Never request it in chat, read it
from Keychain, or put it in source/logs. Leave hosted trials/purchases disabled.

Report build/install checks separately from speech/listening and remaining
blockers. I will operate the first normal conversation.
```

### Install with Xcode

1. Use this checkout or clone [aidynamicsolutions/mural, branch mvp](https://github.com/aidynamicsolutions/mural/tree/mvp). Open `Mural.xcodeproj` beside `Package.swift`. For an existing paired installation use the [preserved physical recipe](.agents/skills/verify-mural/references/physical-device.md), not an unqualified default replacement.
2. In Xcode, open **Settings → Accounts** and add your Apple Account.
3. Select the **Mural** target, open **Signing & Capabilities**, enable automatic signing, and choose your team. For your own fork, replace the bundle identifier with a unique value such as `com.yourname.mural`. Keep that value stable for later updates.
4. Connect and unlock your iPhone. Trust the Mac if prompted. Turn on **Settings → Privacy & Security → Developer Mode** on the phone, restart, and confirm the setting.
5. Select **Mural** as the scheme and your iPhone as the destination, then click **Run**. If iOS asks you to trust the developer, do so in **Settings → General → VPN & Device Management**.
6. Choose languages and mode. On-device teaches English with the selected meaning language; **Prepare & start** checks actual model readiness. Premium saves your key in **Settings → Advanced → Use your own API key**. Allow microphone access when requested.

Confirm a short conversation and audible output in the selected mode. On-device inference runs locally after assets are ready; Premium needs Wi-Fi or cellular.

A free Personal Team can run the app on your own phone; TestFlight and App Store distribution require Apple Developer Program membership. Free provisioning profiles expire after seven days. Refresh by running the same project again, preserving the team and bundle identifier. Export a learning backup before changing either or switching phones. See the [detailed iPhone guide](docs/run-on-iphone.md) for common setup problems. [Apple membership guidance](https://developer.apple.com/support/compare-memberships/)

## What works today

- **A warm welcome:** choose a learning language and a subtitle language in two short screens, with a greeting that changes languages.
- **Conversation practice:** live voice, gentle corrections, optional meaning subtitles, word lookup, mute, and a typed reply when speaking is inconvenient.
- **On-device English:** Vietnamese support or shared Breeze recognition for both Chinese writing modes. Simplified display preserves original recognition separately; Chinese meanings/Help stay on screen and reply speech stays English. The [Simplified MVP is user-accepted](docs/asr/chinese/breeze-simplified-implementation-20260928.md#mvp-closeout-user-accepted-simplified-workflow), not a broad accuracy/resource guarantee. Chinese automatic learning credit remains disabled.
- **Themes:** 24 conversation settings, with cultural details supplied by each language module. You can also request a current topic; web search supplies source links.
- **Adaptive practice:** vocabulary and provisional ability observations come from validated conversation evidence. Each learning language keeps separate progress.
- **Recall bars:** one to three bars summarise repeated retrieval over time. Three bars require spaced evidence in different contexts. These are product heuristics, not calibrated forgetting probabilities or a language certificate.
- **A fresh start:** an ended conversation stays available until you tap **New conversation**. Your saved conversations and learning remain.
- **Local records:** export or import a JSON learning backup, delete a conversation, or delete all learning data from Settings.

The modules teach Norwegian Bokmål with an Eastern Norwegian voice target, Spanish from Spain, international English and French from France. Voice accent and teaching guidance are model instructions; fluent-speaker review is still needed before making pronunciation or learning-effectiveness claims.

## Privacy and API costs

Mural stores conversations, vocabulary and preferences on your device. The iPhone app has no Mural cloud sync, analytics SDK, advertising or account connection in this version. Your API key is stored in the device’s Keychain, excluded from learning exports, and sent only to OpenAI.

On-device speech/tutoring inference stays on the phone once required assets are ready; initial asset acquisition may use network. In Premium, audio, selected conversation text, learning context and requested searches go to OpenAI. Mural does not normally save raw audio. API requests set `store: false` where supported, but that does not disable all provider retention; OpenAI’s abuse-monitoring rules and your project’s settings still apply. [OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data)

OpenAI bills your project for voice, text and search. The app’s usage display is an estimate, and its conversation time limit is not a billing cap. Check your OpenAI project’s usage and spending settings.

## Planned public service

Managed free minutes, accounts and credit purchases are **not available in the iPhone app or a live Mural service**. The [backend foundation](server/README.md) contains account verification, a credit ledger and sandbox payment support. Its runbook lists the remaining work before commercial activation. No shared provider key belongs in this repository or a distributed app binary.

A public TestFlight link and App Store listing are not yet available. [Release preparation](release/README.md) records the outstanding requirements.

The [Mural website](https://mural.chat) lives in the separate [Chuloo/mural-website repository](https://github.com/Chuloo/mural-website).

## Build and test

Start with the [documentation index](docs/README.md), [build guide](docs/build-and-test.md) and [verification feature map](.agents/skills/verify-mural/features/README.md). Existing Make entrypoints own simulator lifecycle/locks, concise Xcode output, raw evidence and compact results. Preview UI uses in-memory fixtures; physical microphone/model/voice checks are separate and opt-in.

On 12 September 2026, the English, French, onboarding and AI-consent build passed **41 core tests and 11 native UI tests**. This covers language-specific progress, the two welcome screens, consent for existing users, secure key entry and the conversation controls. Earlier iPhone checks verified Spanish speech, Meaning during and after a conversation, reset, retained history and audio cleanup; those live results apply to the earlier tested builds. [Verification record](verification/validation.md)

## Code map

| Directory | Contents |
| --- | --- |
| `App/` | SwiftUI views, SwiftData storage, Keychain, WebRTC transport and API coordination |
| `Core/` | Language modules, teaching policy, transcripts, vocabulary evidence and recall projection |
| `Tests/` | Core learning and translation tests |
| `UITests/` | Native interface tests |
| `scripts/` | Xcode project and procedural icon generators |
| `docs/` | Current operating guides, linked feature verification and dated research/evidence |
| `release/` | Submission drafts and public-release checks |
| `server/` | Account, billing and hosted-service foundation; see its runbook before deploying |

Read [how the language architecture works](docs/language-architecture.md) and [how to add a language](docs/add-language.md). Contributions should follow [CONTRIBUTING.md](CONTRIBUTING.md); security issues belong in the [private reporting process](SECURITY.md).

## Dependencies and license

Dependencies are pinned in the root/Xcode manifests and locks, including WebRTC, FluidAudio, WhisperKit and SwiftyOpenCC. The app bundles [app notices](App/ThirdPartyNotices.txt), [OpenCC notices](Core/Resources/opencc-notices.txt) and the SDK privacy manifest. [ASR provenance](docs/asr/README.md) is separate from converter licensing; review notices/resources before distribution or dependency changes.

Mural is released under the [MIT License](LICENSE). Third-party components retain their own licenses. The Mural name and logo identify the original project; the software license does not grant trademark rights.
