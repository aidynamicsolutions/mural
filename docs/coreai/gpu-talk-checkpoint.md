# GPU-preferred staged ASR and normal Talk checkpoint

Status: **Explicit opt-in works in normal Talk on the test phone. Not approved as the default. Paused-session restoration replay is pending.**

This follows [staged Talk assessment](staged-talk-assessment.md). The workaround uses a separate GPU-preferred compilation of the same frozen FP16 encoder, not a repair of the failing default/ANE-backed specialization. The Core ML decoder, frontend, tokenizer and decoding policy are unchanged. No Core AI decoder experiment, cache deletion, uninstall, data reset, commit or publication occurred.

## Loading diagnosis and workaround

A new cache-hit-required, encoder-loading-only run reproduced the original error without inference, tutor or TTS:

- Run `000AD3D1-13ED-4842-BCC2-F7D235AE1B38`, zero recorded memory warnings.
- `coreai_cache_lookup ... hit=true required=true` followed by the same function-load throw.
- This time scoped `aned` output explicitly reported `Model load failed ... isPreCompiledModel=1 : lErr=(null)`.
- The implicated specialized entry was copied read-only before testing. Its nine file hashes were identical before and after the failed run.

The underlying ANE rejection reason remains unknown. This is not proof of corrupt cache bytes, tutor causation, or memory pressure. No retry of the failed loading configuration followed.

Compiled the retained source encoder with the supported `coreai-build --preferred-compute gpu --architecture h18p` option. No re-export, weight, precision or decoding change:

- Source: `.build/coreai/split-export/phowhisper-cs-fp16-v1.encoder.aimodel`
- Source recursive fingerprint: `fd6ea079176fe51b39a81caab1ac0856e59977e2f7e14bad6b81fbd7635c5db6`
- Output: `.build/coreai/encoder-gpu-aot/phowhisper-cs-fp16-v1.encoder.h18p.aimodelc`
- Output fingerprint: `f783c9b539d90a589e1449e514599e240ce6036b3bab6c298858e49bba112829`
- Separate phone directory: `Library/Application Support/CoreAI/PhoWhisperGPU/`
- Runtime options: `SpecializationOptions(preferredComputeUnitKind: .gpu)`.

The GPU-preferred load logs name a different cache suffix (`1146bd5a.../14371356...`) from the preserved failing entry (`e10a76a0.../3EED3375...`). Preference is not a universal hardware-placement guarantee. The captured GPU candidate load did not report the ANE-backed load failure.

## Debug probe qualification

Same iPhone 17 / iPhone18,3, h18p, iOS 27.0 (24A435), Xcode 27.0 (27A5252f), bundle `com.kevintruong.mural.dev`. These are Debug probes, not Release benchmark distributions.

| Check | Run | Result | Highest event-sampled footprint |
|---|---|---|---:|
| Loading only | `310B27FB-534F-44AD-BA03-6F283017BEAC` | Passed, cache hit | 61,377,408 bytes |
| Fresh-process reload | `181E2D5D-406B-46F8-99AD-2731BFDE3AC7` | Passed | 60,590,976 bytes |
| One staged turn | `15AFD077-0FD7-4157-8EC6-1844F536811E` | Exact fixture 001 | 2,084,718,720 bytes |
| Ten serial turns | `3718DEB2-E805-459D-903B-77AE817A8EB9` | Ten exact fixture-001 checks | 2,126,071,984 bytes |
| Frozen corpus | `197B7FDF-4D2F-4986-8732-BB5CD3976A8B` | 22 completed | 2,121,156,712 bytes |
| Preparation cancellation | `787531EC-CF0F-48C6-BD68-5A318E2B1226` | Exact recovery after drain | 2,085,472,408 bytes |
| Encoder cancellation | `DBD70D20-0C2F-4324-A219-FABD8440ED50` | Exact recovery after drain | 2,092,452,040 bytes |
| Decoder cancellation | `D4023F00-A139-4CCC-A347-90A4CDDD2C2D` | Exact recovery after drain | 2,085,488,768 bytes |
| Tutor/TTS coexistence | `C564A730-389F-4B83-AEB6-5A45ED1E7E02` | Exact fixture 001 | 2,096,564,400 bytes |

Every row recorded zero iOS memory warnings. These are event samples, not continuous peaks. The GPU loading-only run also reported process-lifetime RSS peak around 2.61 GB despite its much lower post-load footprint; do not claim loading requires only 61 MB.

The corpus has **21 exact historical-reference matches plus the user-approved fixture-007 exception**. Both `seal tea` and `seoul tea` misrecognize Vietnamese `siêu thị`. All 22 normalized outputs also match the prior staged phone corpus. This is not 22/22 exact historical parity, complete token/logit parity, or a fresh same-device baseline comparison.

Saved cancellation timestamps independently verify requests occurred inside each phase and release/recovery followed underlying return. In the coexistence log, `model_request` precedes language-decoder entry, `model_complete` follows that entry but precedes language-decoder return, and TTS finishes during text decoding. This establishes short tutor-generation overlap with active language decoding and TTS overlap with text decoding, not sustained simultaneous tutor generation and text-token decoding.

One ten-turn launch was blocked by the phone lock. It performed no inference. The user unlocked the phone, then the named run completed. No security setting was changed.

## Normal Talk integration

`LocalConversationEngine.WhisperRecognizer` remains the single recognizer owner. No provider framework or alternate decoder was introduced.

- Default Release builds remain WhisperKit/Core ML and ignore `--coreai-talk-gpu`.
- Debug can explicitly opt in with `--coreai-talk-gpu`.
- A local Release build explicitly opts in using `OTHER_SWIFT_FLAGS='$(inherited) -D MURAL_COREAI_TALK'`. The repository build settings do not enable it by default.
- Prepare verifies frozen support/encoder identities and loads the tokenizer. Diagnostics explicitly say models load after Send.
- Each turn awaits frontend/encoder work in its own scope, passes only owned FP16 embeddings and mel identity to the existing decoder, and unloads decoder models before returning on success/error/cancellation.
- Shared tensor and fingerprint helpers are extracted from the probe; existing executable bridge/layout tests now exercise those shared implementations.
- The production opt-in requires the verified cached GPU specialization; a cache miss fails without automatic specialization, repair or fallback.
- An iOS memory warning cancels/drains work and disables preparation for that process. It does not start the baseline backend in the same process. Model errors are not automatically retried.

### First real-path failure: asset verification buffers

The initial Release Talk trial warned during Prepare, before `asr_assets_ready` and before inference. The successful probe used per-chunk autorelease pools; Talk's original multi-gigabyte `FileHandle.read` hashing loop did not. A controlled 256 MiB host check measured approximately 276 MB peak RSS with the old loop versus 8.7 MB with per-chunk draining, with identical hashes.

Fixed the shared normal-Talk asset-verification loop, not a model or quality gate. The phone replay then passed: verification sampled 61.8 MB before and 65.0 MB after, taking 1.80 seconds, with no recorded memory warning. Also corrected the next Prepare error after a warning so it preserves the memory-warning explanation instead of incorrectly saying speech is still active.

### Human-confirmed Release results after that fix

- Prepare and greeting: passed, no alert.
- Multiple distinct recorded turns, tutor replies and speech: passed.
- End, saved transcript and normal relaunch: passed.
- Offline launch/recording/reply/speech with Airplane Mode and Wi-Fi off: user answered yes to the explicit network-disabled checklist.
- End during Finalizing, wait for drain, then a different recording: user-confirmed pass; logs show the canceled encoder turn did not publish an ASR result before the new session.

First-turn timing was **not** a startup performance pass:

- Prepare: 2.80 seconds.
- First Send-to-final: 46.87 seconds; encoder scope returned about three seconds after Send.
- Decoder-side interval included ANE compiler-service activity from about 15:03:09 to 15:03:43, before decoder model loading completed.
- Second/third Send-to-final: 5.54/5.84 seconds.

The observed delay is on the existing Core ML decoder cold-preparation path, deferred to Send. These logs do not isolate every decoder subphase or prove that compilation will never recur. Moving prewarm into Prepare and releasing it before encoding would shift the wait, not remove its total cost. No such latency change was made here.

## Background failure and pending correction

The user reported losing active Talk after roughly one minute in the background. Captured logs show PID 45747 paused, briefly resumed preparation, paused again, and a new PID 45813 later opened the app. No matching new Mural crash or Jetsam report was exposed in the retrieved inventory. The reason for process replacement is unknown; do not label it a proven Core AI crash or Jetsam.

The durable text path was already separate from active Talk state. `LearningStore.init` finalized all unfinished records, while the coordinator only resumed an in-memory session. Implemented a small persistence correction:

- Optional `SessionRecord.localPausedAt` marks an explicitly background-paused local conversation.
- Preserve only the newest resumable local record on startup; premium, ended, unmarked and greeting-only sessions retain their existing behavior.
- Restore the existing session identity, text and turn offset into paused Talk, then use the existing preparation/resume path. Do not replay old speech, a greeting or unfinished inference.
- Clear the marker on successful resume and explicit End.
- Old archive records without the field still decode; the focused regression checks local eligibility, stable IDs, ended/premium exclusion and legacy decoding.

**The final phone replay is pending.** The paired form timed out with no reported result and no captured new ASR/lifecycle actions. A passing build and 64 passing core tests are not proof that the background fix works on the phone. The requested replay is: completed turn -> background one minute -> return and second turn; background again -> close/reopen -> same session without repeated speech; End -> reopen -> history retained but not active.

## Rollback and remaining release gates

A current-source default Release app is preserved locally at `.build/verification/coreai-load-reliability/default-release/Mural.app`. The default/Debug/explicit-Release backend selection is covered by executable tests, and both default and opted-in Release builds compile. **An end-to-end baseline-ASR rollback is not yet tested.** Do not mislabel a built rollback artifact as a demonstrated warning-free rollback.

Rollback procedure: End/Stop and wait for hybrid work to drain, install the default build in place and launch a fresh process. Preserve assets/history. Verify history and then qualify baseline ASR safely; its earlier fresh comparator warned during model preparation. The asset-hashing fix addresses the separate observed Talk verification failure, not proof that the comparator's prewarm warning is resolved. Never load fallback models while hybrid work is still active.

Before recommending default rollout, still require:

- Actual replay of the background/restoration correction, prolonged suspension and app lifecycle behavior.
- Integrated cancellation across preparation/decoder phases, beyond the user-tested Finalizing stop and bounded probe checks.
- End-to-end rollback and missing/changed-asset failure checks without deleting user assets.
- Silence/Yes/No coverage, sustained coexistence/thermal testing and a supported OS/device matrix.
- Controlled Release cold/cached/full Send-to-final distributions and a safe comparator. Debug samples are not these distributions.

## Validation and evidence

Evidence root: `.build/verification/coreai-load-reliability/`. Includes preserved cache bytes/hashes, Apple API documentation, source/AOT fingerprints, compiler/build/install logs, all run reports/events, corpus comparison, cancellation checks, scoped app/ANE logs and private phone-check evidence. No personal transcript/audio dump was added to Talk logging. All owned captures were stopped.

Passed:

- Debug, default Release and explicit opt-in Release builds.
- `swift test`: 64 tests, zero failures.
- CoreAI cached-load, product-config, tensor-layout, probe-contract, Talk opt-in and bounded asset-verification-memory checks.
- `git diff --check` and staged diff whitespace check.

Existing staged/unstaged work remains preserved. The original ANE-backed loading defect remains unresolved; the GPU-preferred path is a qualified alternative for the limited evidence above, not a blanket production-readiness claim.
