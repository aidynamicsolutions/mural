# Live AI conversation on the iPhone 17

## User outcome

The learner starts a real Mural conversation on the physical iPhone 17, receives a provider greeting and response, can type or speak, sees meaning, and gets clear audio and failure behavior.

## How to get to it

Follow [physical preparation and the premium fallback](../references/physical-device.md#device-hub-manualpremium-fallback), including fresh device/status discovery, exact-PID idle ownership and approved signed-artifact selection. Preserve the paired Core AI Release, main/runner identities, assets and data; do not substitute generic Debug or use blanket `--terminate-existing`.

Open only the owner-coordinated Device Hub session on that phone and choose View Screen. Use Capture Keyboard only for typed input and turn it off afterward. For microphone capture, fully quit the owned mirror and operate the phone directly. Debug diagnostic helpers require an explicitly approved matching Debug build.

## How to drive it

With a valid key entered through **Settings > Advanced > Use your own API key** and the required user authorization:

1. Accept AI consent and allow microphone access.
2. Start a conversation and wait for the greeting to finish.
3. Send one short typed reply through Device Hub or speak naturally on the phone.
4. Confirm a nonempty provider response, transcript passages, and settled audio.
5. Toggle Meaning and confirm a translation while active and after ending.
6. Mute, end, relaunch, and inspect the visible state and audio release.
7. Try one provider/network failure and record the user-facing error.

For content-free diagnostic runs, use the Debug `--verify-audio` and `--verify-meaning --verify-language=es` launch arguments and copy the resulting JSON reports as described in the parent skill.

## Proof

A passed live check needs the physical-device build/install evidence, a settled screenshot before and after the interaction, the exact user action, and either the content-free diagnostic report or a manually recorded observation of greeting, response, route, closure, and error state. A stream frame or process launch alone is not proof.

## Gotchas

- A saved user key and paid-provider authorization are prerequisites, not properties of the checkout. Without them, completed provider replies/audio/meaning are blocked; missing-key and consent UI can still be checked.
- Do not inspect Keychain contents or put the key in logs, screenshots, shell history, or reports.
- Device Hub can show live frames while input forwarding is broken. Quit and reopen the entire app, then verify a harmless navigation action before retrying.
- Device Hub can interfere with microphone capture. Fully quit it for voice recording checks.
- Stream frames can lag input. Inspect the settled screen before choosing the next action.
- The diagnostic helpers incur API usage and use temporary learning data; they are not automatic offline checks.
