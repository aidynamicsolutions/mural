# Local agent: finish and qualify the PAL6 encoder on iPhone 17

You are continuing authorized work on `aidynamicsolutions/mural`, branch `mvp`.
Read `docs/asr/coreai-pal6-encoder-checkpoint.md` first. The objective is accurate
English/Vietnamese switching with faster readiness/turns and lower resource use.
Do not optimize bit count in isolation or restart the completed W8 investigation.

You own Mac inspection, code/tooling corrections, conversion, building, staging,
in-place installation, bounded Mural-only logging and analysis. The user owns
physical phone/UI/microphone actions. **Use the available interview skill/tool**
to guide those actions and collect feedback, one physical action at a time.
Discover the actual tool/skill name; do not pretend a missing interview API exists.
If unavailable, explicitly report that and use the same single-action structured
question protocol in chat while continuing all safe engineering work.

## 1. Preserve work and recover evidence

Before writes, run `git status --short`, `git branch --show-current`,
`git rev-parse HEAD`, `git diff`, and `git diff --cached`; save the exact starting
commit/diffs outside tracked files. Fetch `origin mvp`, inspect the remote head,
and fast-forward only when safe (`git merge --ff-only origin/mvp`). Preserve local
changes. Never reset, force-push, rebase/rewrite history, auto-stash, delete a
branch or merge unrelated work. If another agent advanced the branch, inspect
and preserve that work rather than replacing it. This task authorizes narrow
implementation corrections and commits, with remote-head verification before a
fast-forward push. Do not commit models, private recordings or large raw logs.

The remote implementation began at
`afa5eee17d6aea686c9e9bc23fc816e4c7da1056`. Read the current commit diff. Its code
adds export/audit/comparison tooling; **native runtime integration is deliberately
emitted locally only after actual PAL6 artifact hashes exist**. Missing generated
PAL6 pins are an expected build step, not a reason to stop.

Recover the actual accepted reference evidence, without reconstructing it from
this prompt:

```
.build/verification/w8-v3-native-20260917-2130/
.build/verification/w8-v3-fp8-pal8-corpus-20260917-0000/
.build/verification/w8-v3-live-20260918-0020/
.build/verification/w8-v3-final-20260918-0035/performance-comparison.md
.build/verification/w8-v3-final-20260918-0035/attempt-ledger.md
.build/verification/w8-v3-final-20260918-0035/evidence-index.md
```

Record each present/missing path. Verify the retained source/AOT artifact,
manifest, build flags, PAL8 support directory and actual phone architecture.
The accepted full FP8 manifest pin is:
`73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13`.
PAL8 support pin:
`430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336`.
The support identity is `phowhisper-cs-pal8-g16-v1`.
Do not modify either manifest, artifact, original build pin, tokenizer or cache.
If raw historical timings are missing but the exact safe control assets exist,
record historical numbers unavailable and collect a NEW explicitly labeled paired
control; do not pretend to reproduce the missing run. If the control assets are
missing, recover them from existing local evidence/backups without silently
re-exporting a different “champion.” Continue independent safe code/tests.

Recover old PAL6 details from:

```
.build/verification/local-mvp-phase-2/phowhisper/pal6-g16-v1/result.md
/Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/pal6-g16-v1/
```

The historical full Core ML PAL6 manifest pin is
`13f9bbd0d08bf0b6a111f8415ddffad158f8d1fb4e4014c17585066e37fd23bb`.
Recover exact commands, group/LUT/threshold settings and incompatible tensors.
Its 19/21 agreement and fixture 011 `I went to` → `I went through` are historical
context, not a result for this new Core AI encoder. Do not reuse that old package.

## 2. Fix the measurement interpretation before comparing winners

Read `productStageEncoder`, `productPrepare`, `productTranscribe`, and
`ProductReplayEncoder` in `App/MuralApp.swift`. The old staged `ProductTurn` total
starts AFTER native encoding and decoder preparation. Determine whether the
reported 1.148 s versus 1.762 s means were drawn from this field. If so, preserve
the values but label them decoder/replay pipeline, not Send-to-final; withdraw
only the unsupported end-to-end label/calculation, not human quality acceptance.
Do not add averages from unrelated live/corpus runs to invent a corrected total.

The generated trial patch adds `staged-asr-full-complete.seconds` from after audio
read through encoder, decoder preparation and transcript. It is **not a UI Send
timestamp**. It also separates native encoder execution from response
validation/unpack/copy in `encoder-response-verified`. Use the same patched build
for both configurations. Keep historical fields intact and separately labeled.
Report actual live Send-to-final independently, plus Prepare-to-ready, first turn
in a fresh process with retained caches, new-conversation first turn, and warm
turns. Never delete caches to manufacture a “cold” measurement.

## 3. Host checks and conversion

Reuse the actual accepted export Python environment. Do not install or upgrade
packages globally. Expected Apple versions: `coreai-core 1.0.0b2`,
`coreai-torch 0.4.1`, `coreai-opt 0.2.1`; verify Torch/NumPy/Transformers and native
compiler against the retained reference manifest too. Recover the environment
path rather than assuming an old cache directory still exists.

Run and retain output:

```sh
"$PY" -m unittest discover -s Tools/CoreAI -p 'test_pal6_experiment.py' -v
"$PY" Tools/CoreAI/test_w8_runtime_identity.py
```

The remote host passed 30 new tests, including real synthetic Torch capture, but
had no Apple compiler or full Swift build. You must perform the real local gates.
Discover current iPhone architecture with the existing probe/tooling; the
exporter intentionally admits only the previously qualified `h18p` target. Do
not guess another architecture, reuse an old UDID, or change compute backend.
A genuine target mismatch requires an explicit recorded compatibility correction.

Set these variables to paths you just verified. `OUT` must be a NEW directory
outside the source/reference/decoder asset directories:

```sh
# MODEL: frozen merged model, not FP8 weights and not a freshly remerged model.
# REF: retained packed-v3 FP8 encoder manifest.json.
# PAL8: retained PAL8 support manifest.json.
# OUT: fresh .build/coreai/pal6-encoder/<unique-attempt> directory.
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 "$PY" Tools/CoreAI/build_pal6_encoder.py \
  --model-dir "$MODEL" --reference-manifest "$REF" --pal8-manifest "$PAL8" \
  --output-dir "$OUT" --architecture h18p --aot
```

Frozen merged `model.safetensors` SHA:
`264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a`.
Base/adapter revisions are in the checkpoint/previous research plan; do not
substitute a model with the same shape. Preserve all original decode/front-end
settings. The initial recipe is six-bit K-means grouped-channel 16, scalar LUT,
FP16 LUT with no LUT quantization (`lut_dtype=None`), no activation quantization,
pruning/training or backend/decoder change. Fast K-means decimal rounding is
explicitly disabled. Verify the installed public API signature before adapting
any spelling or import. Do not invent FP6 or a floating-point LUT dtype argument
when the API expects `None` for an unquantized LUT.

Inspect `audit-before.json`, `audit-after.json`, warnings and `manifest.json`.
The audit checks every large floating tensor rather than merely counting a few
compression operators. Small vectors/metadata remain reported at existing
precision. If an important matrix is skipped, diagnose the actual shape/use and
public API. Legitimate incompatible tensors require an exact tensor-key-to-reason
JSON passed as `--retained-exceptions`, in a **new** output directory/identity.
No wildcard waivers. This option records skips; it does not force layers to stay
FP16 or implement mixed precision. Do not edit a failed manifest to mark it passed.
Do not waive missing or ambiguous learned-weight correspondence.

Confirm actual source/AOT sizes, native identities, source and manifest
fingerprints, compressed/retained tensor counts/elements, logical index/LUT bytes
and source-precision bytes represented. Logical payload estimates are not measured
serialized compression ratio, physical footprint, or RSS. Preserve failed output
and logs; do not rerun a long conversion unchanged after a diagnosed failure.

## 4. Generate the real runtime pin and build

Once AOT and the static pair audit pass:

```sh
"$PY" Tools/CoreAI/prepare_pal6_trial.py \
  --reference-manifest "$REF" --candidate-manifest "$OUT/manifest.json" \
  --pal8-manifest "$PAL8" --output-dir "$PATCH_EVIDENCE"
git apply --check "$PATCH_EVIDENCE/pal6-runtime.patch"
# Read the patch and receipt; verify original FP8/PAL8 pins are unchanged.
git apply "$PATCH_EVIDENCE/pal6-runtime.patch"
```

The generator performs artifact rehashes and refuses colliding source/AOT native
identities. It does not change source itself. An anchor conflict means inspect
current source and make the smallest equivalent change; it does not justify
abandoning the experiment or replacing whole files from an old checkout.

The patch updates the Swift width/packet ceiling, adds only the actual PAL6 pin,
requires explicit PAL8 for PAL6, restricts PAL6 product modes to `staged-gpu` or
`staged-gpu-encode`, and adds measurement-only fields. Existing FP8/INT8/FP16 pins,
normal defaults and tiny-probe order must remain intact. PAL6-only fixture-001
raw differences are collected for corpus review, not automatically declared a
pass and not concealed by changing expected text.

Run the existing relevant identity/residency tests, including:

```sh
"$PY" Tools/CoreAI/test_w8_runtime_identity.py
"$PY" Tools/CoreAI/test_product_residency.py
```

Add a portable Swift test of actual PAL6 identity decoding/challenge/unpack for
`[1,1500,1280]` and the 56-element trailer. Build Release using the retained
`MURAL_COREAI_W8`/staged Talk configuration and existing signing/bundle identity.
Verify generated project configuration, using `scripts/generate_project.py` only
when required, never hand-editing generated project files. Do not change signing,
uninstall, reset learning data, or clear the memory-warning latch.

Stage PAL6 BESIDE FP8 under the existing resolver layout:

```
Documents/CoreAI/W8FullV3/packed/encoder-pal6/manifest.json
Documents/CoreAI/W8FullV3/packed/encoder-pal6/<entrypoint>.aimodel/
Documents/CoreAI/W8FullV3/packed/encoder-pal6/aot/<entrypoint>.<actual-suffix>.aimodelc/
```

Use the actual names in the audited manifest, not a guessed AOT suffix. Do not
rewrite manifest paths to phone paths; the resolver uses bundle basenames.
Preserve original source/AOT files and retained caches, recording runtime-added
cache files separately rather than deleting them to make fingerprints match.

## 5. Serialized phone encoder gate

Use the existing product probe; do not create a concurrent model owner. Example
arguments, after checking the current flag parser:

```
--coreai-product-mode=staged-gpu-encode
--coreai-product-sequence=001.wav,011.wav,001.wav
--coreai-w8-v3-encoder=fp8
--coreai-w8-v3-decoder=pal8
```

Then run the same saved sequence with `--coreai-w8-v3-encoder=pal6`. Do not mix
legacy `--coreai-fixture`, `--coreai-encode-only`, support override or old
compressed-encoder flags with the product gate. Run candidates sequentially in
matched fresh processes and then verify retained-cache hits, not concurrently.
Never fall back to `main`. A missing cache may be prepared only through the
explicit encoder-only specialization gate; Talk/corpus must not silently compile.

Retrieve fresh run IDs and complete run directories, not just the latest pointer:
`Documents/CoreAI/PhoWhisper/Runs/<runID>/`. Saved encoder-only outputs are
`encoder-<NN>.fp16`, with corresponding `mel-<NN>.f32`. Verify native
challenge-response before accepting those outputs. Record actual mel hashes;
compare the SAME input bytes across candidates and repeats.

`compare_pal6_hidden.py --help` documents digest-bound JSON descriptors. Create
those descriptors from actual captures, then run reference/candidate/repeat
comparisons. Finite shape, max/mean error, cosine and repeatability are diagnostics.
Changed hidden states alone are expected under lossy compression; wrong identity,
nonfinite/malformed data or demonstrably wrong execution is not acceptable.
A high cosine cannot establish bilingual quality. A repeat/cache hit must resolve
the same candidate and reproduce its output as required by the existing gates.

Measure cache lookup, specialization separately, function load, native execution,
validation/unpack/copy, event-sampled footprint, process-lifetime RSS peak, thermal
state, warning/error count. A failed specialization interval is not inference
latency. The old `encoder-run-begin/end` interval also includes validation and
potential saved-tensor I/O; use the new separated fields for native execution.

## 6. Corpus, then live interview

After encoder/numeric/identity safety gates pass, run:

```
--coreai-product-mode=staged-gpu
--coreai-product-corpus
--coreai-w8-v3-encoder=pal6
--coreai-w8-v3-decoder=pal8
```

Use the same build, same PAL8 decoder and same retained corpus for the FP8 control.
Run all 22 files: score 001–016 and 018–022; keep 017 diagnostic separate. Verify
fixture digests and completion/error fields. Compare raw transcripts to the
accepted FP8/PAL8 outputs and to the retained human references. Save every raw
difference; do not edit expected text or use tutor/LLM corrections. Watch 006,
007, historical 011, lost English/Vietnamese spans, switch boundaries, negation,
numbers, important deletions and hallucinations. Do not automatically reject a
punctuation change or an equally/more correct transcript, but obtain actual human
review for meaning-sensitive differences. Serious corruption quarantines PAL6.

If there is only a narrow meaningful regression and a substantial measured
resource win, diagnose encoder/token evidence for those fixtures. At most ONE
supported, evidence-selected mixed-precision candidate is allowed; no layer sweep
or training. Preserving sensitive layers requires a real supported precision
selection implementation and a new immutable recipe, not an audit exception
that falsely claims to change weights. Re-run host/corpus gates before phone use.

If corpus quality is acceptable, install Release IN PLACE. Stop any mirroring/
Device Hub workflow known to interfere with microphone capture. Use the interview
tool, with exactly one physical action per request and a Done/Stuck/Error option.
For example, first ask the user to open Talk; after confirmation ask for Record;
then one spoken phrase; then Send. Do not dump the whole checklist at once.
You operate logging/builds; the user operates the real microphone and UI.

For each completed utterance collect through interview fields: what was actually
said (including deviations from the suggested phrase), EXACT displayed raw
transcription, perceived wait, heat, and any UI/error behavior. Preserve their
wording; do not infer acceptance from silence. Correlate the response with bounded
Mural-only logs and one identified turn before asking for the next action.

Cover English→Vietnamese, Vietnamese→English, `siêu thị`, numbers, negation,
normal English, normal Vietnamese, quiet isolated Yes, quiet isolated No, at
least two warm mixed turns, a new-conversation first turn, and a focused offline
mixed turn. Prefer previously used live phrases for a fair replay. Guide offline
settings one action at a time and confirm actual connectivity state. Include a
fresh-process first turn with retained caches; distinguish it from true first-
install/specialization, which must not be manufactured by deleting caches.

Silence is NOT an acceptance gate in this compression phase. Record naturally
occurring hallucinations, but do not change VAD/no-speech/energy thresholds. The
known `Để mình check lại thông tin trước khi thi.` silence failure remains open.
Preserve quiet genuine short answers and do not hide the issue through decoding
changes during PAL6 qualification.

## 7. Continue through recoverable blockers; stop unsafe candidates

Persist through ordinary imports, paths, package-environment discovery, generated
pins, API naming, compiler contracts, build generation, staging and logging
issues. Inspect the installed SDK/API and exact error; make the smallest
supported correction and continue through already-authorized passed gates. Do
not stop with “needs local testing” when you have the Mac and phone access.

For each substantive blocker record:

`phase → error → hypothesis → changed variable → predicted outcome → actual outcome → next action`

Try up to three materially different evidence-backed hypotheses for recoverable
conversion/runtime problems. Routine path/syntax/pin corrections do not count.
Do not repeatedly launch an unchanged native failure. A native crash, memory
warning, wrong model/cache identity, wrong numerical execution, unsafe overlapping
owners or serious speech corruption quarantines that candidate immediately.
Investigate from preserved evidence; testing a corrected graph requires a NEW
identity and repeated earlier gates, not clearing a latch or ignoring the failure.

Never edit native hash files, delete caches for a pass, overwrite FP8 assets,
rewrite expected text, loosen ownership, change backend, or hide regressions.
If a hard external prerequisite truly cannot be recovered, complete every
independent safe check, preserve a precise blocker/evidence inventory and state
what remains unmeasured. Do not manufacture success or promise unattended work.

## 8. Report and stop at the encoder decision

Keep host observations, agent-observed phone evidence and human feedback separate.
Return exact commit/local diff, discovered phone/iOS/Xcode/Core AI versions,
reference/PAL6/PAL8 identities and fingerprints, recipe, actual source/AOT sizes,
coverage and exceptions, 21-scored-plus-017 results, all raw differences, live
feedback, first/warm/new-conversation timing, true live Send-to-final, separately
named full staged ASR interval, legacy decoder/replay timer, native encoder,
validation/copy, decoder time, sampled footprint mean/max and separate process-
lifetime RSS peak, thermal state, warnings/errors, and blocked/unmeasured items.
Use matched cohorts/units and event sampling definitions; do not call every later
corpus fixture a resident-model warm turn when the probe recreates models.

Reported historical footprint (mean/max 1.249/1.285 GB) and RSS (1.432 GB) are
reference context only until recovered. Do not combine footprint and RSS or
publish a blanket “39% lower RAM” claim. Report mean/median/range, first turn and
warm turns separately, and keep 017 out of scored timing aggregates.

Stop all owned logging/capture processes and record cleanup. Commit narrow code/
pin/test/docs corrections with a safe fast-forward push only; keep large/private
artifacts out of Git. End with a factual encoder disposition: retain FP8/PAL8;
PAL6 encoder/PAL8 decoder preferable; targeted mixed precision needs one further
test; or PAL6 not worth the quality/resource tradeoff. Include explicit “pending
qualification” when blocked, rather than implying an unmeasured result.

**Do not build PAL6 decoder until the user/reviewer accepts the encoder result.
Do not begin silence/VAD until the compression configuration is separately
reviewed.**
