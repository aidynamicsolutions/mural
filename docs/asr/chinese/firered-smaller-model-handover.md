# Local-agent handover: smaller FireRed research and CTC host gate

Retained FireRed research/support, not normal Breeze Talk. Use [the current Chinese index](README.md#retained-firered-support) for disposition. Dated approvals/pending steps do not authorize a new run; recheck current routing and qualification gates before expensive work. Code, pins and tooling remain intact.

Work in `aidynamicsolutions/mural`, branch `mvp`. Review anchor is
`a73d8163355fb2137d552196677c1b722840d9df`. Preserve unrelated work/history; no
reset, rebase, stash, force push, deletion of assets or replacement app slot.
Use ordinary Git review and separate commits. This packet did not change origin.

## Goal and decision already established

Mural already runs FireRedASR2-AED INT8, not the 8B+ LLM. Do not implement a
same-model “LLM to AED” swap. The newly identified smaller alternative is the
**CTC-only** sherpa export derived from FireRedASR2-AED. It excludes the attention
decoder, so it is a different recognition path requiring a matched quality gate.
The user prioritizes memory and sustainable use while preserving reported good
Mandarin recognition. No automatic backend substitution or transcript repair.

Implement the host comparison first. Only a useful, quality-reviewed candidate
should lead to a separately identified, compile-gated phone variant. Preserve the
existing native memory STOP until that named continuation is ready and reviewed.
The user requested a build/test path for their iPhone 17, not an unchanged retry,
public promotion, an unattended audible window or permission to erase data.

## Read and verify before changes

Read current `AGENTS.md`, the complete `docs/asr/chinese/firered-memory-research-handoff.md`,
`simplified-talk-qualification-plan.md`, linked historical investigations, the
verification skill and physical lessons. Inspect current affected source rather
than assuming this review anchor remains HEAD. Carry forward the three distinct
memory outcomes, missing +30-second sample and original profiler cleanup failure.

Review `RESEARCH.md` and `VALIDATION.md` in this packet. They distinguish verified
source support, community claims and actual missing evidence. The numbered patches
are source changes, not validation of native performance or model accuracy.

## Apply the two source patches

From the real checkout, using the actual unpacked packet path:

```sh
git status --short
git branch --show-current
git rev-parse HEAD
git apply --check /absolute/path/to/patches/01-ctc-host-comparison.patch
# Review the patch before applying it.
git apply /absolute/path/to/patches/01-ctc-host-comparison.patch
python3 -m unittest discover -s Tools/ChineseASR -p 'test_firered_ctc_candidate.py' -v
git diff --check
```

If context or new paths conflict, inspect the divergence. Do not overwrite entire
files or use three-way/whitespace options to hide a mismatch. Patch 01 was checked
against an exact reconstruction of the reviewed `run_reference.py` blob
`94db2df4d48d86293e558e7532cecf3e98dd4e70`, not a full repository checkout.
Commit only these intended files after local review:

- `Tools/ChineseASR/run_reference.py`
- `Tools/ChineseASR/firered_ctc_candidate.py`
- `Tools/ChineseASR/firered-ctc-pin.example.json`
- `Tools/ChineseASR/test_firered_ctc_candidate.py`

Patch 02 adds `docs/asr/chinese/firered-smaller-model-review.md` and
`docs/asr/chinese/firered-smaller-model-handover.md`. Check/apply it separately and
record a separate documentation commit. Do not commit private reports, audio,
references, downloaded weights, signing configuration or model binaries.

## Gate 1: establish a real CTC artifact identity, without running a model

The documented release is:

`https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-fire-red-asr2-ctc-zh_en-int8-2026-02-25.tar.bz2`

This release-tag URL is not an immutable byte identity. The review did not obtain
its full archive/file hashes. Do not invent them, substitute AED filenames, assume
token identity, or treat a freshly self-generated hash as upstream attestation.

Use the existing scoped host acquisition/evidence workflow to resolve the exact
upstream asset and acquire it into a new ignored research location. Record asset
identity, provenance, actual size and SHA-256; corroborate any published digest.
Preserve the archive. Inspect members and reject absolute/traversal paths,
symlinks/hardlinks and unexpected payloads before bounded extraction to a fresh
directory. Do not extract over AED, the runtime tree or managed phone data.

In the retained ONNX inspection environment, inspect the graph **without creating
an inference session**. Confirm metadata `model_type=fire-red-asr-2-ctc`, CMVN,
feature dimensions, inputs/outputs, vocabulary/blank IDs, embedded/external tensors
and all actual operator/dtype requirements for ORT 1.28.2. Preserve tokens exactly.
The byte-verification helper does not perform this semantic review.

Create a private frozen staging directory containing exactly `model.int8.onnx`
and this export's `tokens.txt`. Use a canonical non-symlink path; the helper rejects
symlinks in file/directory ancestry. Keep any README/test audio outside that two-file
directory. No other process may modify the staging files during verification/replay.

Copy `firered-ctc-pin.example.json` into private evidence, fill actual byte counts,
SHA-256 values and the reviewed archive SHA-256. Change `reviewed_for` to
`host_comparison_only` only after the preceding review. Independently review and
record the complete pin's SHA-256. The template intentionally fails admission.
A pin is a local review trust boundary, not a new signed upstream manifest.

## Gate 2: one bounded host comparison through the existing replayer

Reuse the retained source-built sherpa environment and actual native linkage
receipt: sherpa 1.13.8 at `a5b4a944c5186a68bcdc0ac3011e4c541781ac84`, linked
ORT 1.28.2. Do not install an arbitrary latest wheel. The helper's Python package
version check alone cannot prove linked ORT identity; importing a separate
`onnxruntime` Python package does not prove what sherpa links either.

Select reviewed frozen audio/references already present locally, starting with the
six MELI clips. Keep references immutable before output inspection. Run AED and
CTC in separate fresh processes, serially, using the same hardware, audio and CPU
thread policy. Never keep both models loaded for the comparison. No phone needed.

The new invocation, after setting the real local paths and reviewed digest, is:

```sh
"$REVIEWED_PYTHON" Tools/ChineseASR/run_reference.py firered-ctc-onnx \
  "$FROZEN_CORPUS" "$AUDIO_ROOT" \
  --model-dir "$FROZEN_CTC_TWO_FILE_DIRECTORY" \
  --candidate-pin "$REVIEWED_CTC_PIN" \
  --candidate-pin-sha256 "$INDEPENDENTLY_REVIEWED_PIN_SHA256" \
  --output "$NEW_PRIVATE_EVIDENCE/ctc-predictions.json"
```

There is deliberately no invented `--revision` for the CTC release archive. The
report pins actual candidate bytes and records that producer reproducibility is
not attested. The original `firered-onnx` AED command and full immutable revision
contract are unchanged.

Use a finite, ownership-aware host command budget with retained output and cleanup.
The existing replayer is not a watchdog, and the 30-second input bound cannot
interrupt synchronous native inference. Do not claim partial output is a pass.
Do not retry a timeout/crash automatically. Use the established host measurement
workflow (for example saved Darwin process-RSS instrumentation); do not compare
peak memory across overlapping runs or call host RSS an iPhone footprint.

Record first/warm decode and preparation timing, process memory phases where
available, and native library/model/pin/corpus identity. The supplied replayer
records raw text/timing, **not full memory phase attribution**. No such memory
measurement is implied by a passing replay.

Use existing scoring with frozen human references. Review Mandarin CER, English
WER, both switch directions and script behavior. Names/numbers and brief Yes/No
remain coverage gaps to fill narrowly. Define acceptable regression before looking
at results; do not select a tolerance after seeing a preferred candidate. Model
agreement is not human-reference accuracy. Stop the CTC track if quality is not
acceptable, regardless of size. Retain AED and pursue weight-preserving residency
or separately reviewed selective AED quantization instead.

## Gate 3: only if host evidence is useful, implement the distinct phone variant

Do not edit the current pin in place or reuse package ID
`firered-asr2-int8-374cff18-v1` for CTC bytes. Suggested separate identity pattern:
`firered-asr2-ctc-int8-<reviewed-hash-prefix>-research-v1`.

Minimal change map:

1. `Core/SpeechPackage.swift` and `Core/SpeechPackageCatalog.swift`: add an explicit
   research-only two-file CTC contract and separately pinned identity. Preserve
   existing AED validation and defaults. The existing installer expects direct
   files, not a tar archive. Resolve reviewed immutable raw-file origins/hashes
   before in-app acquisition; otherwise stop for a separately reviewed acquisition
   change. Do not point an ONNX URL at a tarball or add broad redirect exemptions.
2. `App/FireRedEnglishRecognizer.swift`: make selection explicit in a dedicated
   experiment build. For CTC, zero-initialize the config and set only
   `config.model_config.fire_red_asr_ctc.model`, the candidate tokens, CPU, one
   thread and greedy decoding. Leave `fire_red_asr.encoder/decoder` unset. For
   AED, preserve the original path unchanged. Bind the validated model identity to
   selection; no flag may relabel arbitrary weights. Reuse native owner, 16 kHz
   capture, 30-second turn cap, VAD, cancellation, thermal/warning gates and raw text.
3. `scripts/generate_project.py`, the bridge/build receipts and native tests:
   introduce a clearly named compile-gated candidate selection only where needed.
   Check the actual static C API/CTC link path against the pinned arm64 runtime.
   Regenerate in the existing isolated output, preserve Core AI Release/Vietnamese,
   signing/app identities and ordinary project. Update notices only for actual new
   artifacts. Do not upgrade runtime or combine allocator/Q4 changes in this run.
4. `scripts/verify_device.py`, `UITests/MuralUITests.swift` and coordinator/owner
   identity reporting: extend only the existing scenario identity/admission needed
   to distinguish the candidate. Preserve resource budgets, completion nonce,
   backend assertions and complete-owner drain. No second harness or file-probe
   workaround. Read physical lessons completely before any runner change.

Write changed-contract failure cases first: mismatched/missing pin/files, wrong
model kind, fallback, partial activation, cancellation while loading/decoding,
stale generation, memory-warning stop and preservation of the existing pairs.
Do not enable the new candidate publicly merely because it builds.

## Gate 4: one proposed physical iPhone 17 experiment

First resolve/qualify the existing profiler-finalization and owned-process cleanup
failure with the closest **model-free** runner regression. Build and prepare the
selected candidate/fixtures before arranging the physical window. Rediscover the
phone and current ownership; obtain fresh exclusive idle/unlocked/cool readiness,
agreed playback/listening and closed mirroring. No room recording.

Use only `make agent-verify-device` and the reviewed current skill. Preserve
`com.kevintruong.mural.dev` and its intended runner, data/history/preferences,
voices, valid AED content and Vietnamese Core AI Release. No fourth app or uninstall.

The named experiment is CTC-only INT8, original runtime session defaults, original
voice/VAD, one reviewed acoustic M00A-switch turn, actual response completion,
**360 seconds loaded idle after all completed turn/voice work**, then safe complete
owner drain and **+2/+10/+30-second** samples. Retain current reviewed budgets:
1,020 seconds overall, 780 command, 720 XCTest and 660 app observation. These are
bounds, not targets. Never omit idle/drain/cleanup to force success.

Stop on the first warning, crash, serious thermal state, model/resource fault or
native operation over the reviewed 60-second threshold. A timeout is not permission
to destroy native handles before a C call returns. Preserve failed original and
separate recovery records. No automatic retry. A successful bounded run would not
complete multi-turn, offline, lifecycle, quality or public-release qualification.

## Rollback and report

For host-only patch rollback, retain private evidence, then revert the isolated
source commit; app behavior was never changed. For a later phone candidate,
complete owned drain and restore the reviewed AED selection/build through the
existing workflow. Preserve both artifact sets and all failure evidence. Do not
turn AED into an automatic runtime fallback for failed CTC tests.

Return exact source commits, artifact/runtime/corpus identity, test scope/results,
raw-output quality comparison, phase memory/timing/thermal observations, warning
count, cleanup status and remaining gaps. Distinguish “smaller file,” “lower host
memory,” and “safe sustainable iPhone use.” They are three different claims.
