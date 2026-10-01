# Breeze Simplified display: implementation and acceptance

Status: **user-accepted Simplified MVP**, committed in `31fd730` on `mvp`. This is bounded feature acceptance, not distribution, broad recognition accuracy or sustained resource qualification. Use [local verification](../../../.agents/skills/verify-mural/features/local-conversation.md) for current commands; do not reapply the original delivery patches or resume superseded ASR proposals.

## User contract

On-device mode teaches English. Meaning language selects support and presentation, not a recognizer picker:

| Meaning language | Recognizer | New spoken-user presentation |
| --- | --- | --- |
| Simplified Chinese | Existing verified Breeze PAL8 | Derived Simplified Han script; English unchanged |
| Traditional Chinese | The same Breeze model/assets | Existing canonical display, unconverted |
| Vietnamese | Preserved PhoWhisper/Core AI configuration | Unchanged |

Breeze recognizes Mandarin and English; speech itself has no Simplified/Traditional writing system. MediaTek's model runs locally through WhisperKit/Core ML, with CPU/Neural Engine encoder/decoder. Apple's Foundation Models separately generate English replies and selected-script meanings, lookup and on-screen Help. Chinese Help is not spoken through the English voice; Chinese automatic learning assessment remains disabled.

No new ASR weights, training, quantization, language forcing, grammar repair, VAD/provider/limit change or duplicate recognizer. Existing 16 kHz conversion, 30-second cap, decoding and selected English voice remain.

## Pinned converter and resources

| Item | Identity |
| --- | --- |
| Swift package | `ddddxxx/SwiftyOpenCC`, product `OpenCC` |
| Wrapper revision | `1d8105a0f7199c90af722bff62728050c858e777` |
| OpenCC submodule | `be3af873de7d9ca28c274b4a917d9fcd953345cf` |
| Stored policy | `tw2s-han-1d8105a0-v1` |

This is the reviewed older wrapper, not a moving/latest OpenCC dependency. The actual API is `ChineseConverter(options: [.simplify, .twStandard])`. It uses Taiwan glyph-variant normalization followed by Traditional-to-Simplified dictionaries; **omit `.twIdiom`**. Required goldens include `軟體 -> 软体`, not `软件`, and unchanged `滑鼠`, not `鼠标`.

Mural passes only single-scalar Han-grapheme runs to OpenCC. English, numbers, punctuation, whitespace, emoji, NUL and other graphemes are copied byte-for-byte. Han plus a variation selector is preserved whole rather than breaking a rare name/glyph sequence. Literal Simplified `么` is preserved at the boundary because the pinned Taiwan-variant dictionary otherwise maps it to `幺`; Traditional `麼` still converts to `么` and legitimate `幺` remains unchanged. Dictionary conversion can be contextually imperfect and cannot repair a wrongly recognized word.

One process-lifetime actor owns/reuses the converter serially; do not create one per turn or view. Prepare dictionaries and the required notice before microphone readiness. Missing resources fail explicitly, never silently select another converter/model.

The fetched checkout was clean; exact wrapper/submodule identities and all **16 `.ocd2` dictionaries** were inspected. Real dependency tests and native goldens passed on the qualified build. Root and Xcode locks retain their other pins. The app links OpenCC and bundles its dictionaries plus `MuralCore` notices.

Licenses: wrapper MIT, OpenCC Apache-2.0, selected marisa BSD-2-Clause alternative and darts-clone BSD-2-Clause. Full reviewed notices are in `Core/Resources/opencc-notices.txt` and reachable through Settings notices. Converter licenses do not replace ASR model licensing. Reinspect affected notices/artifacts before distribution.

## Raw, canonical and display roles

1. `rawASRText` preserves the exact native result. It is provenance, not teaching text.
2. `Fragment.text` / `Passage.text` retain existing canonical wording and pre-existing whitespace handling. Tutor/history prompts, revision keys and learning boundaries use canonical text, not a display projection.
3. Optional `scriptPresentation` stores canonical source, derived display and policy identity. Attach it only to new finalized spoken user turns in the frozen Simplified pair. Typed/assistant turns, legacy streams and old history are not rewritten.
4. UI uses `displayText` and exposes original recognition separately. Save the snapshot once; do not reconvert on each render or from current Settings.
5. Archive schema remains **2**. Optional metadata round-trips; import checks source/role/pair/bounds and non-Han preservation. These are structural checks, not cryptographic authentication or independent dictionary proof.
6. Edit starts with displayed wording. Explicit save removes stale projection, retains raw recognition and uses existing canonical revision/learning invalidation. Later pair/library changes do not rewrite earlier history.

Persist raw/canonical recognition **before** awaiting conversion. Cancellation, End or backgrounding cannot erase that saved turn; session/source/foreground/admission checks reject a late projection from another state. Conversion failure is visible, not a fallback or transcript repair.

## Asset and configuration boundaries

`App/BreezeEnglishRecognizer.swift` and its asset pin were not changed by this display feature. Both Chinese modes resolve the same `.taiwanMandarinEnglish` recognition assets through the existing managed-or-retained path. Simplified conversation/support remains `zh-Hans-CN`; asset sharing does not change the selected support locale. Initial and resumed preparation receive the frozen pair.

Retain historical FireRed catalog metadata, `active-zh-CN-en.json` and files. The Simplified managed-delete action refuses deletion and explains shared Breeze ownership; it must not remove FireRed or shared Breeze. No automatic migration, cache clearing or model copying.

Breeze is **not published in the current managed catalog**. This phone reused independently verified retained files. Missing/corrupt Breeze fails without FireRed substitution or invented hosting. [Customer provisioning](../app-store-model-provisioning-release-blocker.md) remains separate.

Normal generation uses `scripts/generate_project.py` without FireRed/file/compact flags. Preserve the paired phone's explicit `MURAL_COREAI_TALK` Release. Required signed-build evidence includes actual compiler invocation, linked converter, dictionary/notice bundles and main/runner signatures; requested flags or a source hash alone are insufficient.

## Verification selection

Use production tests with the real dependency:

```sh
swift test --filter ChineseScriptPresentationTests
swift test --filter LocalSpeechPairPersistenceTests
```

For synthetic UI, select affected methods through the [owned simulator entrypoint](../../../.agents/skills/verify-mural/features/README.md#simulator-entrypoints): display/raw/edit, missing assets/no fallback, pair mapping or cancellation/drain. The fixture uses real converter/archive/views but synthetic text and an in-memory store; it is not acoustic acceptance.

For native work, read the [physical workflow](../../../.agents/skills/verify-mural/references/physical-device.md). Reuse the installed main app and existing XCTest runner, not another QA slot. Default `prepare` is build-only; its vi-en metadata does not authorize Vietnamese speech. Breeze runtime uses `DEVICE_PAIR=breeze-zh-CN-en` and a matching prepared artifact. Legacy `zh-CN-en` stages retain FireRed assumptions and must not count as Breeze acceptance.

Keep exact build/PID identity, readiness/inference and content-free `breeze_script_display` markers. Judge words separately from script, and audible English separately from logs. Scope persistence/edit to a new test UUID; never export or modify the user's whole history. Preserve settings/assets and require owned cleanup on failure as well as success.

## MVP closeout: user-accepted Simplified workflow

| Contract | Evidence |
| --- | --- |
| Mixed Mandarin/English, names/numbers and live English | User acceptance; not a corpus benchmark |
| Simplified display | Eight Core methods / eleven real OpenCC goldens, plus native dictionary check |
| Meaning, lookup and Help | User confirms Simplified text, audible English replies and no Chinese Help audio |
| Ordinary multi-turn UX | User confirms no unexpected Pause/Resume; real-observer synthetic warning regressions passed |
| Reopen, original recognition and explicit edit | Earlier exact-UUID native pass; five persistence tests and 28 delivered production boundary assertions |
| Warm startup | Approximately five seconds after End/full quit/unchanged-install relaunch, by user report |
| Signed identity/resources | Source/artifacts matched installed ordinary Core AI Release; pins, dictionaries/notices and signatures checked |

The 28 delivered boundary assertions used an injected map, not OpenCC acceptance; real dependency goldens are separate. Host runner checks passed. Applicable earlier UI recordings/results and native scoped persistence were reused on unchanged contracts; no new phone operation was needed merely to record closeout and commit.

Limits remain explicit:
- Fresh Traditional speech on this build was not checked; shared-model/source/UI evidence is not a native acoustic pass.
- Earlier prerecorded English/mixed and no-speech failures remain failed. Live-user success does not establish accent causality or broad accuracy.
- Automated support and profiling stages retain their failed/unqualified branches; manual acceptance is separate.
- Latest ordinary smoke did not explicitly observe a real OS memory warning. No sustained memory/thermal soak, lifetime safety or quantization benefit is claimed.
- Chinese automatic learning credit and first-install distribution are not qualified by this feature.

Private closeout: `.build/verification/breeze-simplified-closeout-20260930/`.

## September 30 warning UX follow-up: ordinary phone update installed

Earlier ordinary logs showed a memory-warning event followed about 20 ms later by an app-imposed pause. Normal Talk now logs `asr_memory_warning stopped=false continuing=true` without stopping or calling the coordinator safety callback. Notifications alone do not cancel preparation, recording, inference or reply. Resume is not cosmetically hidden: sampled 3 GB, serious/critical thermal and real model-failure recovery remain.

Two synthetic notification regressions and three distinct ceiling/thermal recovery cases passed. Initial tests wrongly expected an enabled microphone without loaded models; corrected checks measure Ready/no warning-induced Resume and preservation. Failed attempts remain evidence, not passes.

The ordinary signed update was installed in place, preserving main/runner identities and data. Its model-free `breeze-finish` native dictionary/settings readback passed, 1/1 without ASR/microphone, in 98.54 s including cleanup. Final preference was On-device / English / Simplified Chinese. Main executable SHA-256: `a0370d72cb0d6c4e15d8dbbbda495752f2dcd1fb4c7ed7f437053c784b2e9e1d`. Private evidence: `.build/verification/breeze-memory-warning-nonblocking-20260930/`.

## User-confirmed warm relaunch: startup investigation closed for the PoC

After End, completion, full quit and relaunch without reinstall, the user reports whole preparation around **five seconds** and accepts slow first preparation after reinstall. A full process restart distinguishes this from same-process resident-model reuse. It is approximate human timing, not a matched benchmark or proof of the internal cache label.

Treat startup as resolved for this PoC. Separate cold/warm results and retain native loading/validation. Reopen only for slow unchanged-install relaunches, a relevant model/runtime/compute change or explicit cold-start optimization. Do not automatically resume blocked profiling after another development install.

## September 30 Breeze load profile: encoder bottleneck confirmed, cache cause unconfirmed

Historical production component timings, all with receipt hits and skipped prewarm:

| Run | Mel | Decoder | Encoder | Total load/validation |
| --- | ---: | ---: | ---: | ---: |
| Mandarin acoustic | 0.064 s | 17.854 s | 149.998 s | 167.923 s |
| Support | 0.064 s | 19.917 s | 141.447 s | 161.432 s |
| Corrected support | 0.066 s | 22.437 s | 149.850 s | 172.361 s |

Remaining validation/orchestration was under 8 ms; asset hashing was separately about one second. The bottleneck was actual loading, not a missing receipt. The pinned Argmax runtime `1e2a163736dfa5a198e637ae44c114e1c6d5cc2d` loads Mel/decoder/encoder sequentially through Core ML. The preserved Vietnamese flag does not select a GPU Breeze encoder.

Distinct historical sandbox paths plus Apple's [path/configuration-sensitive cache guidance](https://developer.apple.com/videos/play/wwdc2023/10049/) support reinstall-related cold loading. Recompilation/cache classification was not instrumentally established. Optional profiler attempts failed device/automation setup before a qualified model trace; finalized zero-model-event traces are not acceptance. Original failures and separate ownership recovery remain retained; no expensive model replay followed. A host-tested profiler early-exit correction does not qualify that native stage.

Private evidence: `.build/verification/breeze-load-profile-20260930/`. Current warm feedback supersedes the proposed immediate profiling work, not failed test outcomes.

## Local qualification checkpoint: September 30

Historical initial integration: all three delivered patches were reconciled against the full checkout; pinned dependency/submodule/resources, real host goldens, archive/policy checks, normal generation and focused owned simulator checks passed. Actual compiler/link/resource/signature evidence established the intended ordinary Core AI Release. Initial native accuracy/support gates were incomplete. This is provenance, not instructions to reapply the bundle.

## September 30 resumed native checkpoint: display PoC passed; acoustic qualification incomplete

A reviewed Mandarin-dominant turn established distinct raw/Simplified display and unchanged English with one Breeze identity. Exact-UUID history/relaunch/explicit edit passed separately in 111.64 s through cleanup without ASR reload. Earlier prerecorded English/mixed failures and corrected no-speech support remained failed, without automatic replay. A separate warning-continuation diagnostic was restored to the ordinary artifact; it did not override thermal/ceiling guards or establish production resource safety. Later user acceptance closed the Simplified manual gates above, not these failed automation outcomes.

See [physical E2E lessons](../../physical-iphone-e2e-lessons.md) for retained failure-prevention details. Private evidence remains under `.build/verification/breeze-simplified-20260930-122221/`.

## Rollback

Drain first; revert only reviewed source/build changes. Preserve models, pointers, caches, settings, raw/canonical history and scoped evidence. Do not automatically run old FireRed when restoring an older CN mapping. Older code may drop unknown display metadata on a later save while retaining existing raw/canonical fields. No model/data deletion or binary downgrade is part of documentation cleanup.
