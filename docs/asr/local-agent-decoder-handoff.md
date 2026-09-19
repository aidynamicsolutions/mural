# Local agent: decoder precision, trustworthy timing, natural interview pacing

> **Delivery status:** Prepared against `eb2675980cd9c944cd376d7bb70e4d2800f15df8`. The GitHub connector rejected the remote write, so these changes are **not committed or pushed**. Apply the delivered `decoder-next.patch` using the package’s `DELIVERY.md` before running this handoff.

Continue `aidynamicsolutions/mural`, branch `mvp`. Read
`docs/asr/decoder-first-review.md` first. This handoff supersedes the earlier
encoder-acceptance prerequisite and one-action-per-interview rule for this task.
The user explicitly authorizes PAL6 **decoder** investigation with the accepted
FP8 encoder even when the PAL6 encoder is not worthwhile.

## Goal and ownership

Deliver accurate English/Vietnamese conversation with less real waiting and
lower measured resource use. Do the implementation/build/logging; the user
operates phone microphone/UI. Continue through recoverable tooling problems to
a real result, not another plan or a list of suggested tests. Do not promise a
pass, reinterpret missing evidence as a pass, or repeatedly retry unsafe native
failures. Keep the single recognizer owner, native-drain semantics and latched
memory-warning behavior. No normal/default Talk switch occurs automatically.

The prepared implementation adds host tools and a generated runtime patch,
**not** a converted/qualified decoder or installed app. Apple tooling, actual
manifest format/ABI, the full patch/build and device behavior remain local gates.

## 0. Preserve the checkout and recover the missing report

Record `git status --short --branch`, `git rev-parse HEAD`, `git diff`, staged diff
and current remote head. Fetch `origin mvp`; fast-forward only if safe. Preserve
unrelated work. No reset, automatic stash, force push, rebase of published work,
uninstall, cache deletion, model replacement, signing change or learning-data
reset. Re-discover the current phone, architecture, OS, Xcode and toolchains.
Do not use a historical device ID/PID as current evidence.

The reviewed local-agent commit was `eb2675980cd9c944cd376d7bb70e4d2800f15df8`.
It contains source changes and a PAL6 pin, but **no new result report**. Locate the
actual latest local PAL6 encoder run directories, console logs, asset manifests,
corpus JSON and interview records. Search the local `.build/verification` tree by
names/content; do not guess a successful run from its timestamp or reconstruct
numbers from the user's summary. Record which files exist and SHA-256 each.

Also preserve/recover the known FP8/PAL8 evidence roots:

```
.build/verification/w8-v3-native-20260917-2130/
.build/verification/w8-v3-fp8-pal8-corpus-20260917-0000/
.build/verification/w8-v3-live-20260918-0020/
.build/verification/w8-v3-final-20260918-0035/
```

The current source pins full packed FP8 manifest
`73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13`,
full PAL6 encoder manifest
`b3437340b110c14349cd3f12ae0955adb8254fdc277e263907eaa3d96e651966`,
and PAL8 support manifest
`430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336`.
These pins identify expected artifacts; existence/native success still needs
verification. Never overwrite them or relax a pin to make loading succeed.

Check the earlier encoder conclusion against: actual executable/build flags;
FP8/PAL8 versus PAL6/PAL8 selections; matching corpus input hashes; new native,
validation-copy and full-staged fields; encoder-stage versus decoder-stage
footprint; process-lifetime RSS measured in comparable new processes; token
counts; thermal conditions; first and subsequent turns; and interview pacing.
Do not call an average difference within ordinary run variation an established
win or an established equivalence. Record an honest uncertainty interval/range.

If these were matched, retain the negative encoder result and proceed. If
identities/scopes/pacing were mismatched or raw evidence is incomplete, do one
bounded paired recheck of the **already built** encoders. No encoder rebuild or
restart of the solved cache-identity investigation. Do not let an unavailable
historical report prevent a new, correctly measured decoder experiment.

## 1. Recover the existing six-bit decoder before converting anything

Historical artifact root (verify, do not assume):
`/Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/pal6-g16-v1/`.
Historical full support manifest SHA:
`13f9bbd0d08bf0b6a111f8415ddffad158f8d1fb4e4014c17585066e37fd23bb`.
Inspect its result/commands/manifest and recover exact settings, skipped tensors,
source package hashes and tool versions. Its whole-pair 19/21 agreement and 011
lexical change are historical, **not** the FP8/PAL6 decoder trial's outcome.

The economical first decoder candidate is its exact `TextDecoder.mlmodelc`,
paired with the unchanged successful FP8 encoder. Do not load its old Core ML
AudioEncoder. Verify vocabulary 51865, all input/output names/shapes/dtypes,
cache tensors, tokenizer, suppression, frontend and task/language handling.
Use the existing Mac Core ML/WhisperKit tools to inspect the compiled model and
replay the decoder; simulator or a Python import alone cannot pass this gate.

Run the new tests in the existing compatible environment:

```sh
PYTHONPATH=Tools/CoreAI python3 -m unittest -v test_decoder_trial
```

Discover actual directories containing `manifest.json` and bind these shell
variables to verified paths (not guessed placeholders):

```sh
# REF_SUPPORT: retained PAL8 support root
# OLD_PAL6_SUPPORT: historical PAL6 support root
# FP8_MANIFEST: exact retained full FP8 manifest, with original assets available
# E: new exclusive evidence root for this session
python3 Tools/CoreAI/prepare_pal6_decoder_trial.py \
  --reference-support "$REF_SUPPORT" \
  --historical-pal6-support "$OLD_PAL6_SUPPORT" \
  --fp8-manifest "$FP8_MANIFEST" --repo-root "$PWD" \
  --output-dir "$E/admission" --stage-support
```

This rehashes the pinned artifacts and requires every non-decoder speech support
file to match. The unused Core ML AudioEncoder is explicitly excluded from that
comparison; its bytes are never described as active decoder RAM. Extra cache
files are listed and left untouched; only inventoried originals are staged into
a new directory. Inspect `admission.json`, the actual decoder-only byte totals,
common-file comparison and all extras. Static admission is not a native pass.

If the historical directory/recipe is unavailable, or the actual manifest uses a
slightly different documented layout, diagnose rather than abandoning the task.
A narrow path/inventory-reader correction is allowed if it preserves the exact
pins and file checks and gets a regression test. Do not waive a different
frontend/tokenizer/auxiliary model. Recover original source exports before any
new conversion. The fallback is **decoder-only** PAL6 from the frozen FP16 Core
ML source package, using the installed supported `coremltools.optimize.coreml`
K-means/grouped-channel-16/scalar-LUT path. Never quantize a PAL8 decoder again.
Record actual settings/coverage/ABI/source hashes and produce a new immutable
manifest/identity; the current fixed historical admission tool intentionally
rejects that new identity until its independent audit/pin adaptation is reviewed.
That is a recoverable integration step, not permission to fake the old hash.

Do not compress both components, train, change vocabulary, move the decoder to
Core AI or change compute permissions in this phase.

## 2. Review/apply the generated integration, build in place

Review `$E/admission/runtime.patch` and its recorded source hashes. It adds PAL6
Core ML decoder selection only for the pinned FP8 encoder; extends the sequential
probe; adds app-monotonic timing IDs and phase memory logs; and provides a
**separate**, off-by-default prewarm-once experiment. It includes the portable
policy helper in the existing product-test harness. It does not alter accepted
FP8/PAL8 pins, tokenizer/suppression/decode settings, cache policy, default Talk
selection, model ownership or native drain/unload paths.

```sh
git apply --check "$E/admission/runtime.patch"
git apply "$E/admission/runtime.patch"
python3 Tools/CoreAI/test_product_residency.py
PYTHONPATH=Tools/CoreAI python3 -m unittest -v test_decoder_trial
```

Also run the existing applicable W8 identity/layout/cached-load/opt-in tests.
Use the actual repository's project generation/build instructions. No source
file or dependency was added under App by the patch; `DecoderTrialPolicy` is
appended into the existing source, so do not regenerate/sign/change pins merely
out of habit. If existing extraction tests need the newly added pure helper,
make the smallest correct harness update, not deletion of assertions.

Build the existing Release staged/W8 configuration (`MURAL_COREAI_TALK` and
`MURAL_COREAI_W8` as already used), verify the actual h18p architecture and in-place
bundle ID, install without uninstalling. Record commit plus local diff and
executable SHA. Stage the audited support under:

```
Library/Application Support/PhoWhisperCS/phowhisper-cs-pal6-g16-v1/
```

Do not overwrite any existing directory: if it exists, verify identical bytes
and reuse; if different, stop that staging path and resolve identity honestly.
Keep the exact existing FP8 `CoreAI/W8FullV3/packed/encoder-fp8` assets/caches.

First perform a bounded fixture-001 two-turn run in each configuration with the
same app build, original `always` prewarm policy and sequential owner. PAL6's
changed text is retained for review, not hidden behind the old fixture-001
textual recovery assertion. All shape/finite/identity/warning/native gates still
apply. A serious new speech error ends that candidate until diagnosed.

## 3. Main paired corpus comparison: change decoder precision only

Control launch selections:

```
--coreai-product-mode=staged-gpu --coreai-product-corpus
--coreai-w8-v3-encoder=fp8 --coreai-w8-v3-decoder=pal8
```

Candidate selections:

```
--coreai-product-mode=staged-gpu --coreai-product-corpus
--coreai-w8-v3-encoder=fp8 --coreai-w8-v3-decoder=pal6
```

Do **not** pass `prewarm=once` yet. Keep greedy transcription, automatic language
detection, suppression and all cache/compute choices identical. Do not use old
`--coreai-fixture`, `--coreai-support-dir` or arbitrary decoder-path flags in the
product gate. The current staged decoder gate accepts the full corpus or normal
fixture-001 turns, not arbitrary explicit sequences.

Run at least three matched A/B pairs in balanced order (for example A/B, B/A,
A/B), each in a freshly launched process with retained caches. Never overlap
model owners or processes. Match power/network/foreground conditions and start
in comparable thermal states; record deviations instead of cherry-picking the
best run. OS-managed cache coldness cannot be manufactured by deleting caches.
Treat an actual first specialization as its own measurement, not inference.

Collect each whole UUID run directory, including `report.json`, `events.jsonl`,
`product-report.json` and `transcripts.json`. Before moving or renaming evidence,
record its source path and run ID. Copy `trial-context.template.json` into each
run as `trial-context.json`, replacing every placeholder with observed metadata.
Use **actual launcher arguments**, executable hash, OS/build and PID+start time,
not a manually relabeled model. Preserve build/device/launch receipts next to it.

```sh
python3 Tools/CoreAI/analyze_asr_trial.py corpus --phase decoder \
  --reference-run "$A1" --candidate-run "$B1" \
  --reference-run "$A2" --candidate-run "$B2" \
  --reference-run "$A3" --candidate-run "$B3" \
  --output "$E/decoder-paired.json"
```

The analyzer refuses missing warning evidence, incomplete corpus/timings,
contradictory selectors, mismatched audio/mels/encoder hidden states, simultaneous
precision/prewarm changes, or reused process/run observations. If a report schema
needs a documented adapter, add a tested explicit adapter; never silently rename
an old replay timer to full ASR. Keep uncomparable runs in the ledger.

Review all 22 outputs: 21 scored, diagnostic 017 separately. Ground-truth accuracy
is not normalized agreement with another model. Record every raw/token/language
difference, emphasizing 006/007/011, English/Vietnamese spans, switch boundaries,
negation, numbers, omissions and hallucinations. Do not modify reference text or
use tutor corrections. If a narrow meaningful regression accompanies a real
resource win, at most one evidence-selected mixed-precision decoder candidate is
allowed. Verify exact source-to-compiled tensor mapping before exceptions; no
same-shape/order assumption, broad layer sweep or fitting to test utterances.

Report native encoder, validation/copy, cache lookup, function load, decoder
prewarm/load, decoder time and loop/prediction breakdowns separately. Do not sum
overlapping fields. Full staged time includes synchronous harness writes; it is
not real UI Send-to-final. Use the three fixed phase footprint anchors plus
maximum event-sampled footprint, and process-lifetime RSS in separate columns.
Do not average every logged memory point: event frequency differs by code path.

## 4. Natural live testing: preload a batch, no agent round trips mid-turn

Use the available interview skill/tool, but generate and open the **entire
instruction/feedback batch in the Mac browser before the user starts the phone
session**. Read the interview tool's schema; do not invent its invocation.
Do not put the interview browser on the phone and background Mural. No new
interview request between tapping Record and speaking, or between the consecutive
turns in a measured batch. Ask the user to read all sentences first.

You launch the correct configuration and start bounded Mural-only logging. The
user operates the phone at their normal pace. The static form must say:

> Read this whole block before starting. On the phone, Prepare & start. At the
> first Ready after the greeting, tap Record only when you are ready to speak,
> say the first sentence immediately, and tap Send immediately when finished.
> Wait for Mural's reply and Ready, then do the next sentence without waiting
> for an agent/browser instruction. Stop for an error, crash, severe heat or
> unresponsive controls. Complete the feedback form after the block.

Suggested first six-turn block (one Record/Send per sentence):

1. `Yes.` (short first turn: deliberately does not hide remaining prewarm behind a long recording)
2. `I ordered phở không hành, but they gave me thêm hành.`
3. `Ngày mai I have an appointment, nên em không đi được.`
4. `I need fifteen, not fifty.`
5. `No.` (quiet but genuine speech, not deliberately silent)
6. `Today I went to siêu thị. How do I say that in English?`

Use a second preloaded block for normal English, normal Vietnamese, explicit
negation, quiet Yes, at least two warm mixed turns and the focused offline mixed
turn. Arrange offline setup before that block, not in a timed recording. Retain
fresh-conversation and cancellation checks on the chosen configuration.
Keep Device Hub closed during microphone work. Do not use silence as a PAL6 gate;
record any natural silence hallucination without changing VAD/no-speech settings.

Each per-turn form row needs: sentence actually spoken (editable), **exact ASR
text Mural displayed**, approximate perceived wait, and any error/UI anomaly.
Ask heat before/after the block and which turn felt unexpectedly slow. Include
Not completed/Could not capture text choices; do not coerce a success answer.
Correlate returned feedback with actual app logs before the next block. Build/
install/CLI evidence, human statements and inferred explanations stay separate.

```sh
python3 Tools/CoreAI/analyze_asr_trial.py live \
  --log "$BOUNDED_MURAL_LOG" --output "$E/live-timing.json"
```

Only app-monotonic capture/Send/final events determine timing. The browser's
response arrival time is irrelevant. A gap before Send is not subtracted from
Send-to-final, and capture duration does not prove voice-onset time. Label first
and warm status using the actual process/conversation/prewarm timeline. Record
Send-to-first-tutor-audio separately using existing conversation/TTS logs; a fast
ASR result alone is not a fast complete conversational response.

## 5. Separate lifecycle experiment: remove repeated prewarm hints

After decoder precision has a factual disposition, fix both artifacts to the
selected safe configuration (FP8/PAL8 if PAL6 loses) and compare only:

```
--coreai-w8-v3-prewarm=always
--coreai-w8-v3-prewarm=once
```

Use the same corpus, balanced pairs, metadata and natural live blocks. Run the
analyzer with `--phase prewarm`. The new policy does **not** retain a decoder
across encoding, skip real loads, clear cache or warning state, alter tokens,
change the backend, or reuse another recording's hidden states. Live mode skips
only after a successful same-directory prewarm; corpus mode skips only after the
first successful turn. Cold/first-prediction costs may merely move, so measure
both first and warm turns. Require identical deterministic transcripts/tokens and
safe lifecycle behavior for this non-precision change; investigate differences.

If there is no worthwhile improvement, keep `always` and the original lifecycle.
If it wins consistently without quality/memory/first-turn regressions, report it
as a separate lifecycle result, not a PAL6 speedup. Do not combine effects before
they have independently passed their gates.

## 6. Continue intelligently, then stop at a factual decision

For each substantive blocker record:
`phase -> error -> hypothesis -> changed variable -> prediction -> observation -> next action`.
Ordinary syntax, paths, installed API naming, pin generation from verified bytes,
project/build interfaces, report schema adapters and tool packaging should get
narrow corrections and another check. Try up to three materially different,
evidence-backed hypotheses for recoverable native/exporter problems; routine
syntax fixes do not count. Continue through passed gates without asking for
repeated general approval.

Wrong model/cache identity, nonfinite/wrong numerical output, native crash,
memory warning or unsafe ownership overlap quarantines that candidate. Preserve
evidence and the safe control; do not retry an unchanged unsafe native failure,
clear the latch, delete caches, patch native hashes or hide transcription losses.
A meaningful speech regression requires diagnosis/review, not a forged pass.

If decoding predictions still dominate after these experiments, use the actual
Core ML compute plan and a bounded app-scoped trace to select the next kernel/
representation experiment. If host loop/copy work dominates, inspect existing
within-turn KV transfers/token sampling. Do not add a redundant cache, drop
language detection/important tokens, switch to the historically crashing Core AI
decoder, or enable fastPrediction casually (Apple documents memory/startup costs).
Record the measured next target; do not end the whole optimization effort just
because six-bit storage failed to improve latency.

End with a compact table of exact source/diff/executable/toolchain/device,
encoder and decoder identities/bytes, first and warm timing scopes, phase
footprint, RSS, warning/thermal state, corpus raw differences, human feedback,
exceptions and every unmeasured item. State whether to retain FP8/PAL8,
prefer FP8/PAL6, or pursue one narrowly identified further test; report the
prewarm-policy decision separately. No promise of improvement before measurement.

**Commit a real results summary this time** under a new dated file in
`docs/asr/` plus any narrow corrections. Include reproducible commands, evidence
SHA-256 index, sanitized numeric per-fixture metrics, run exclusions, failed
hypotheses and scope definitions. Keep private audio, personal transcripts and
full device logs outside Git; sanitize reviewed corpus diffs. No artifact/model
publication. Recheck remote head before a normal fast-forward push. Report the
new SHA and all local diffs. Stop only owned logging/capture processes and leave
the phone on the safe retained configuration. Do not begin silence/VAD work.
