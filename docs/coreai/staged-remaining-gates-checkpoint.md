# Staged hybrid remaining-gates checkpoint

Status: **Runtime-load/coexistence gate blocked. Normal Talk remains unchanged.**

## Accepted corpus exception

The user explicitly accepts fixture 007 as a known-error exception: both `seal tea` and `seoul tea` misrecognize Vietnamese `siêu thị`. Record corpus quality as **21 exact matches plus one user-approved known-error exception**, not 22/22 exact parity. This clears that discrepancy as a progression blocker. The failed fresh all-Core-ML comparator remains a separate limitation for controlled same-device comparisons.

## New passes, with scope limits

All following runs used the iPhone 17, h18p, existing development bundle, and Debug probe. No normal Talk integration, cache invalidation or data reset occurred.

| Check | Run | Observed result |
|---|---|---|
| Cancellation during decoder preparation | `304D669A-F145-4B53-A56D-969B38243AD0` | Request occurred inside prewarm; awaited its return, then teardown and exact recovery; zero warnings |
| Cancellation during Core AI encoding | `81273814-3F93-4625-8E95-0785697FC7B9` | Request occurred between encoder begin/end; scope release followed return, then exact recovery; zero warnings |
| Cancellation during language decoding | `071E1582-BF1B-40C1-A2B4-465F2FBAAD4D` | Request occurred inside the real WhisperKit language decoder call; underlying transcription returned before teardown, then exact recovery; zero warnings |
| Offline fresh-process launch/transcription | `1C97EF59-F00A-4297-B5EE-EBB995CCC8CB` | Exact fixture 001, zero warnings; user confirmed Airplane Mode on and Wi-Fi off before launch |
| Short background/foreground round trip | `CC6DD5D7-62F7-414F-AEDE-0A7435106E9B` | Two exact fixture-001 turns, zero warnings; launched Settings, returned to the existing Mural process; UIKit logs confirm foreground resume |

All recovery transcripts matched raw text, language and generated tokens. `check-evidence.py` independently checks the request timestamps against phase begin/end and release-before-recovery ordering.

Cancellation is cooperative outer-task cancellation, not a claim that native inference was interrupted. The preparation run waited approximately **40.94 seconds** after its cancellation request for prewarm to return. This is safe ordering, not an acceptable or guaranteed interactive Stop latency. The encoder has no owner-held decoder/function at teardown in its cancellation case; its explicit scope-release event establishes release ordering instead.

Background evidence is a short probe round trip, not prolonged suspension or persistence validation of an integrated conversation. The offline network state is human-confirmed, not separately attested by an on-device network monitor. These limitations are not silently promoted to full production UI acceptance.

## Coexistence: partial evidence, not a pass

The probe now reuses **LocalTutorModel.reply** and **LocalConversationEngine.speak**, not alternate implementations. Companion tasks are awaited and speech is stopped/released afterward. No microphone recording or personal conversation input is involved.

1. `2A334451-78D5-4461-A424-B09D430CC64A`: exact ASR output and zero warnings. TTS actually overlapped decoding, but tutor `model_request` occurred after decoder completion. This is only a TTS overlap pass.
2. `BDAA39AC-492B-4D8E-A786-56E6D95DB629`: moved companion startup before encoder loading. Exact ASR output and zero warnings. TTS overlapped encoding and tutor generation overlapped the decoder-prewarm interval, but cold prewarm delayed actual decoding until after both companions finished. Not simultaneous tutor generation plus active decoder inference.
3. `441D285E-5605-46E0-A3D8-2B1BEEB1B866`: attempted a fresh-process warm run on the same build to test actual overlap without that long prewarm. **Failed before transcription** at Core AI function loading:

```
Core AI function-load failed for phowhisper-cs-fp16-v1.encoder.h18p.aimodelc:
Foundation._GenericObjCError(0) [:]
```

The device log again reports MPSGraph could not load its cached model identifier. Zero warnings were recorded. This is not Jetsam or proven memory-pressure failure, and concurrent tutor activity is not established as the cause. It demonstrates a runtime loading reliability problem in this sequence. No automatic retry or additional cache repair was performed.

Full tutor/TTS coexistence remains blocked. A successful first specialization or one successful load cannot substitute for reliable cached reloads.

## Launch/trust interlude

Before the coexistence tests, several command-line launches were refused with a generic invalid-signature/entitlement/trust error. The local signature verified, the profile included the device, and the profile was unexpired. The user confirmed that the installed app opened normally and its developer was verified.

Process inspection confirmed that the manually running app was the exact newly installed bundle. Command-line activation then worked, followed by a successful fresh probe launch. No trust reset, signing change or reinstall was needed to obtain that first successful launch. A later rebuild/install for earlier companion startup also launched successfully. The initial rejection's cause remains unknown; it must not be presented as a proven bad profile or persistent trust failure.

Preserved failed launch attempts: `coexistence-launch-blocked/`, `coexistence-launch-blocked-2/`, `coexistence-launch-blocked-3/` in the evidence root.

## Gates still open

- Reliable cached Core AI function loading and full tutor-generation/TTS/ASR overlap.
- Sustained coexistence thermal envelope, not only short nominal-state samples.
- Silence/Yes/No edge-case coverage.
- Integrated conversation persistence, prolonged backgrounding, and user-visible Stop/retry behavior.
- Controlled Release cold/cached and end-to-end latency comparison. The baseline previously warned before transcription; do not rerun it unchanged or label Debug probe samples a controlled distribution.
- Supported device/OS matrix, fresh-install-like verification and integrated rollback testing.

These remain unpassed. The fixture-007 exception does not waive any of them. Downstream inference testing stopped on the new runtime load failure.

## Code and validation

- Enabled preparation/encoder/decoder cancellation flags for the staged fixture-001 path.
- Inject cancellation after a short diagnostic scheduling delay, recording the actual request timestamp. Saved event evidence, not the delay itself, proves overlap.
- Staged encoder work runs in a separately awaited scope so outer cancellation never releases resources before that scope returns.
- Added an explicit staged coexistence flag, using existing tutor/audio classes and scoped tasks. No production route changed.
- Product config/parity/normalization tests passed; physical evidence checks passed for the checks credited above.
- Device Debug builds passed. One initial Swift expression-diagnostic failure was fixed by explicitly typing the optional MainActor callback before rebuilding.
- `git diff --check` passed. Existing staged and unstaged work remains intact; no commit/publication.

Evidence root: `.build/verification/coreai-staged-remaining-gates/`. Each run preserves commands, system log, pointer and remote events/report. The collector stopped its scoped log process and terminated its owned Mural probe after retrieval. The final coexistence build remains installed; user data and model assets were not removed.

## Next investigation

Diagnose the repeated cached-function load failure without assuming cache corruption or silently deleting another cache entry. The previous one-entry repair was explicitly one-off. Preserve the failed specialization identity and system log and determine why a successful load is not reliably reusable before pursuing more coexistence or rollout tests.
