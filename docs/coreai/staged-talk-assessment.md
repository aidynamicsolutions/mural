# Staged ASR: cached-load diagnosis and Talk assessment

Historical assessment, superseded by [GPU Talk checkpoint](gpu-talk-checkpoint.md). The original failed cache remains preserved; a separate GPU-preferred compilation subsequently enabled a partially verified normal-Talk opt-in. Existing WhisperKit/Core ML remains the repository default.

Status at this assessment: **Do not enable normal-Talk opt-in yet. Existing WhisperKit/Core ML remains the default.**

This assessment continues the staged investigation using preserved evidence and source inspection only. No new phone inference, installation, cache mutation, signing change, or user-data change was performed. It is not a completed integration or tested rollback.

## Cached-loading evidence

The closest preserved reproduction is the failed fresh-process probe, not normal Talk (which does not use Core AI). Compare these two runs in `.build/verification/coreai-staged-remaining-gates/`:

| Evidence | Successful cached load | Subsequent failed load |
|---|---|---|
| Directory | `coexistence-cold-prewarm-overlap/` | `coexistence/` |
| Run | `BDAA39AC-492B-4D8E-A786-56E6D95DB629` | `441D285E-5605-46E0-A3D8-2B1BEEB1B866` |
| System-log encoder delegate time | 14:18:52 | 14:20:04 |
| Process | 45328 | 45341 |
| Result | Exact fixture 001; cached encoder load confirmed by event | Function-load throw before encoder execution or decoding |

Both reports verify encoder artifact SHA-256 `b13ccaf3fa91098a21bc81786843e138ad2e6cde4a9fdcccece6d531b0f9d034` and support manifest SHA-256 `7b0bff2652daa1198cf476609001a87b42518a9854bf2416c728a72778c92b52`.

Both system logs name the **same full encoder delegate path**, including data container `D240EDB5-DD83-4D85-9CA6-2B24A018087A` and cache suffix:

```
coreai-cache/24A435/com.kevintruong.mural.dev/
e10a76a007043a451767ff2a9950cd23451c7ed144e0549c5796cdbf10aa1251/
3EED337528B9C2FCA4B6816CDCDED1FEC0A9E9EBA265A286147FA655E86F35B1/
model.aimodelx/main-this-delegates/MPSGraph
```

The failure is about 72 seconds after the successful delegate initialization, across processes. A changed container/path is therefore not necessary for this recurrence. Matching paths do **not** prove unchanged cached bytes or unchanged system-service state.

The failed log shows `Loading function 'main'`, ANE service connections, then `MPSGraphNDXRuntime.mm:603: Error, could not load model for cacheIdentifier: <private>` (`coexistence/system.log:300-306`). The associated report records `Foundation._GenericObjCError(0) [:]`. This localizes the observed failure to cached-function loading, not the mel, tensor bridge, encoder inference, or decoder.

The MPSGraph error appears before `coexistence_begin` in this log and before `model_request` at 14:20:07. Companion scheduling had already been requested by the app, so this ordering does not exclude every interaction, but it does not establish active tutor generation as the cause. The earlier encoder-only failure (`19A61F9E-05B7-4156-883F-AF5C76C28B2C`) also produced the same MPSGraph message without the coexistence experiment.

Zero recorded iOS memory warnings and no crash accompany the latest failure. Its last event-sampled footprint, before loading, was 35,571,552 bytes; that is not a failure-time or continuous peak. Neither cache corruption, memory pressure, tutor causation, nor signing failure is established.

### What the evidence cannot answer

- The internal MPSGraph cache identifier is redacted; do not equate it with the visible Core AI cache directory hash.
- `cache-inventory.txt` in `coreai-residency-load-diagnosis/` establishes file presence for the earlier failure, not integrity of the latest failed entry. There is no paired successful/failed cache-content hash comparison.
- The generic thrown error has empty userInfo. The captured app logs do not supply the underlying ANE service rejection reason.
- The one approved delete/rebuild restored loading but did not establish a cause or durable repair. It is not permission to repeat invalidation.
- CLI trust errors cleared without trust/signing changes and are separate from an executing app's function-load failure.

`loadAsset` in `App/MuralApp.swift` returns timing/cache-hit details only after `loadFunction` succeeds. The failed staged event stream ends at `encoder-load-begin`; it lacks a cache-lookup-complete event and a post-unwind memory sample. `stateAtEnd == idle` is not a measured resource-retirement guarantee: staged references are scope-local and the owner teardown can take its empty/idle early return.

### Next bounded diagnostic, before more inference

1. Preserve a read-only inventory and hashes of the currently implicated specialized entry, plus source artifact/support identities and the installed build identity. Do not replace files, respecialize, or delete anything.
2. Add development-only failure-path events for cache lookup result, function-load begin/end/error and encoder-scope return on both success and throw. Record bounded stage/error metadata and post-unwind memory, not audio or transcripts. Keep native-runtime retirement explicitly unverified.
3. Use a **cache-hit-required, loading-only** diagnostic once, with no tutor, TTS, decoder, or encoder execution. The existing `encoder-only` mode is not strictly read-only: `loadAsset` specializes on a miss. Require a hit and stop on a miss before using it for this investigation.
4. Capture bounded relevant runtime/service diagnostics if accessible without broad private-log collection. Stop on a throw, warning, or crash; no automatic retry. If loading succeeds, that single result does not clear reliability. Review evidence before a separately bounded cross-process reload qualification.

This sequence is proposed, not executed. A cache mutation would still need explicit approval. If service rejection details remain unavailable, retain the blocker and prepare a minimal vendor report rather than inventing a cache-repair policy.

## Existing Talk owner is sufficient

The real path is `ConversationCoordinator.startLocal/recordLocal` -> `LocalConversationEngine.prepareConversation/recordConversationTurn` -> `prepareASR/record` -> private `WhisperRecognizer.prepare/transcribe`.

Useful existing guarantees in `App/LocalConversationEngine.swift`:

- `asrTask` serializes preparation/recording, and remains non-nil until its deferred cleanup completes. `canPrepare` and `canRecord` reject a new operation while it drains.
- `stop()` cancels the task, invalidates the generation, finishes capture, and drops the UI owner's recognizer reference. The active task retains its local recognizer; this is not an immediate unload during inference.
- Generation and cancellation checks reject stale results. The coordinator waits for the ASR task and checks session identity before persisting text or requesting a tutor reply.
- `pauseLocal` stops audio/work; `resumeLocal` waits for the old conversation task before preparing the same in-memory session. Finalized passages are saved through `appendLocal`; unfinished ASR has not yet become a passage.

No provider registry, additional public protocol, or new decoder is needed. A future development-only backend choice can be fixed when the existing private recognizer is created. Absence of the opt-in must select today's path; do not persist a sticky user preference or change the public conversation mode.

### Required staged behavior inside that owner

1. Prepare verifies architecture-bound FP16 encoder and support assets and loads reusable tokenizer/configuration only. It must not retain the baseline encoder/decoder or advertise fully warmed ASR when work is deferred to Send.
2. Each bounded, finite 16 kHz turn runs the accepted mel frontend and Core AI encoder in one awaited scope. Only owned FP16 embeddings and mel identity cross its return boundary.
3. Only after that scope returns, create WhisperKit with the replay encoder and existing Core ML decoder. Keep the exact tokenizer, suppression and decoding options. Require replay mel identity; fail rather than decode mismatched or unsupported additional windows.
4. Await transcription on success, cancellation and error; unload/release decoder, replay embeddings and turn state before finishing `asrTask`. The next turn recreates model resources. Retaining the tokenizer is optional, not grounds to retain a decoder.
5. A cancellation request keeps the operation busy until underlying work returns. An unstructured encoder worker, if needed to preserve the tested drain semantics, must always be awaited, including throws. Actor isolation alone does not prevent overlap across awaits; preserve the existing single-task admission rule.
6. Do not transplant the entire development harness into Talk. Extract only the required loading/tensor/replay helpers after reliability clears; leave probe flags, corpus assertions, file dumps, cache deletion and unrelated decoder experiments unreachable from the product path.

The current roughly 41-second preparation cancellation drain is a real interaction constraint. End/Stop may update immediately, but Prepare/Record/retry must remain unavailable with truthful stopping feedback until cleanup completes. Do not make a timeout clear the busy handle or start the baseline backend.

## Conditional opt-in and rollback contract

A development-only opt-in is a reasonable *next integration experiment after the loading blocker is cleared*, not currently a safe enabled feature or a default-rollout recommendation.

- Default and missing opt-in: existing WhisperKit/Core ML implementation.
- Load failure: surface an actionable error, drain and release hybrid resources, and stop. No automatic fallback, cache repair, or repeated retry.
- Manual rollback: End/Stop, wait for the operation and all hybrid resources to drain, then relaunch without the opt-in. Keep model assets and learning data. Process separation avoids concurrent app-owned hybrid/baseline residency; it does not establish that the baseline itself is warning-free.
- Before calling rollback tested: complete an opted-in synthetic conversation, return to the default without the flag, verify saved history and a new recording; repeat after controlled load/asset failure and cancellation. Confirm no stale turn or speech and no overlapping loads. Missing-asset testing must use an injected test condition or disposable assets, not remove the user's installed models.
- The fresh baseline comparator previously warned before transcription. Do not repeat that configuration unchanged as a rollback test. First explain or avoid its loading envelope using source/evidence analysis; a separately staged reference is not proof of normal-backend rollback.

Rollback remains **untested**. The helper/config tests below cannot establish resource lifetime or phone UI behavior.

## Required actual-Talk checks before any default recommendation

Paired phone verification must cover End/Stop during preparation, encoding and decoding; blocked retry while draining; retry afterward; a second distinct recording without stale tokens/text; short background return and prolonged suspension; finalized history after relaunch; offline launch and two turns with networking human-confirmed disabled; and tutor/TTS coexistence with interval evidence. Check supporting meaning/lookup/assessment work as well as the primary half-duplex reply path. Full tutor generation plus active decoder overlap remains unproven.

Also retain silence/Yes/No, sustained thermal, supported OS/device and Release timing/memory gates. Quality is **21 exact historical-reference matches plus the explicit user-approved fixture-007 exception**: both `seal tea` and `seoul tea` misrecognize Vietnamese `siêu thị`. It is not 22/22 exact parity, same-device parity, or waiver of lifecycle/reliability gates.

Existing device runs are Debug. Approximately 2.096 GB is the highest event-sampled corpus footprint, not a continuous peak. WhisperKit transcription timing excludes earlier staged frontend/encoder and preparation work; use the complete Send-to-final timeline, including recreation, for product latency.

## Validation of this assessment

Re-ran successfully, without phone inference:

- `python3 Tools/CoreAI/test_product_residency.py`
- `python3 Tools/CoreAI/test_hybrid_layout.py`
- `python3 Tools/CoreAI/test_probe_contract.py`
- `python3 .build/verification/coreai-staged-remaining-gates/check-evidence.py`
- `git diff --check` and `git diff --cached --check`

No runtime source changed in this assessment. Existing staged and unstaged implementation work was preserved. No commit or publication. The cached-load root cause and actual-Talk acceptance remain unresolved, so no new runtime or rollout pass is credited.
