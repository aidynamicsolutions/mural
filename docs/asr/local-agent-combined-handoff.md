# Local execution: bounded PAL6 encoder + PAL6 decoder qualification

Read `combined-pal6-review-20260918.md` and the committed
`decoder-qualification-20260918-real-results.md` first. This is an implementation
handoff, not permission to switch production defaults. All new device outcomes
are pending. Do not ask the user to upload private recordings, app stores or logs.

## Scope and working policy

A = explicit FP8 encoder + PAL8 decoder, safe fallback.
B = explicit FP8 encoder + PAL6 decoder, accepted isolated-decoder lab candidate.
C = PAL6 encoder + PAL6 decoder, new joint trial.
D = PAL6 encoder + PAL8 decoder, optional diagnostic intermediate only.

GO for C's existing-artifact admission and a native fixture-001 two-turn gate.
Only continue a safe, correct candidate. Keep A available and leave normal/default
Talk, prewarm default, suppression, language detection, VAD and silence unchanged.
Do not rebuild the encoder, convert new weights, retain an encoder function across
decoder work, clear a warning latch, delete caches, uninstall, replace accepted
assets, alter signing or reset learning data. Never force-push or reset work.

Your job is to build, stage only missing verified artifacts, operate the probe,
measure and troubleshoot ordinary tooling errors. The user operates the phone.
Do not stop at another plan or ask permission repeatedly for already-authorized
passed gates. But successful native execution is not a resource or quality pass.

## 0. Apply the supplied implementation, preserving all work

The reviewed remote commit is `374a7b3abecc87c9f5b78959f3ab1e48084e18ae`.
The remote-review session had read/search GitHub tools but no write/push action.
Its delivery is NOT a remote commit. Do not assume it has been pushed.

```sh
git status --short
git branch --show-current
git rev-parse HEAD
git fetch origin mvp
git rev-parse origin/mvp
git diff --stat
```

Fast-forward only when safe. Keep any unrelated local changes, no auto-stash or
reset. If already ahead or remote moved, inspect the ancestry and specific diff;
do not overwrite it. Save a local diff and its hash under the new evidence root.

Apply the delivery's `combined-tools.patch` after review and `git apply --check`.
It adds tools/tests/docs and updates the portable policy; it does not silently
modify the app. Do not copy the entire previous decoder delivery over the repo.

```sh
E=".build/verification/combined-pal6-$(date +%Y%m%d-%H%M%S)"
mkdir -p .build/verification
mkdir "$E"  # A NEW directory; failure means choose a new run name.
git diff --binary > "$E/starting-local.diff"
git apply --check /absolute/path/to/combined-tools.patch
git apply /absolute/path/to/combined-tools.patch
PYTHONPATH=Tools/CoreAI python3 -m unittest -v test_combined_trial test_decoder_trial
python3 Tools/CoreAI/combined_runtime_patch.py --repo-root "$PWD" --output "$E/runtime.patch"
git apply --check "$E/runtime.patch"
# Review the small runtime patch; it must not change artifacts, model ownership,
# decode settings, default flags, existing manifest pins or cache policy.
git apply "$E/runtime.patch"
git diff --check
PYTHONPATH=Tools/CoreAI python3 -m unittest -v test_combined_trial test_decoder_trial
python3 Tools/CoreAI/test_product_residency.py
python3 Tools/CoreAI/test_hybrid_layout.py
python3 Tools/CoreAI/test_cached_load.py
python3 Tools/CoreAI/test_talk_opt_in.py
```

The generator checks the entire two App file Git blob hashes against 374a7b3 and
refuses drift. This is intentional. On genuine source drift, adapt only the small
patch after inspection; do not reset or change the expected hash to suppress a
real unreviewed change. The baseline policy fixture is test data, not a second
runtime policy. Both the embedded app policy and the Tools policy must agree.
No project regeneration is required for these changes: the app still embeds the
policy in its existing file. Do not compile a second duplicate enum into the app.

Changes add the explicit C flag `--coreai-w8-v3-combined=pal6-pal6`, preserve old
rejections without it, permit D with explicit prewarm=always, preserve the native
001 oracle for C, and add ID-correlated first-audio timing. They do NOT assert
that C is safe before the following real gates.

## 1. Admit the exact already-existing artifacts

Resolve paths locally by exact manifest SHA, not just folder names. Expected:
FP8 manifest `73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13`;
PAL6 encoder manifest `b3437340b110c14349cd3f12ae0955adb8254fdc277e263907eaa3d96e651966`.
The known FP8 path is `.build/coreai/w8-id-v3/packed/encoder-fp8/manifest.json`.
Locate the PAL6 path within the existing `.build/coreai` artifacts; do not scan or
export the private app store. The exact PAL6 AOT identity is in `combined_trial.py`.

Set these to recovered existing paths:

```sh
FP8_MANIFEST=.build/coreai/w8-id-v3/packed/encoder-fp8/manifest.json
# Set PAL6_MANIFEST to the existing manifest whose SHA matches the value above.
# Set PAL8_SUPPORT and PAL6_SUPPORT to the existing verified support directories.
# Historical support parent:
# /Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/phone-assets/
: "${PAL6_MANIFEST:?Resolve the pinned existing PAL6 encoder manifest}"
: "${PAL8_SUPPORT:?Resolve existing phowhisper-cs-pal8-g16-v1}"
: "${PAL6_SUPPORT:?Resolve existing phowhisper-cs-pal6-g16-v1}"
PYTHONPATH=Tools/CoreAI python3 Tools/CoreAI/combined_trial.py \
  --fp8-manifest "$FP8_MANIFEST" --pal6-manifest "$PAL6_MANIFEST" \
  --pal8-support "$PAL8_SUPPORT" --pal6-support "$PAL6_SUPPORT" \
  --inspect-aot --output-dir "$E/admission"
```

If manifests retain old absolute paths but byte-identical artifacts were moved,
use `--fp8-root` or `--pal6-root`: each root contains the source bundle and
`aot/<bundle>`. This verifies copies without editing the manifest. No fabricated
pins, native hash edits, or automatic export. Missing/mutated source or AOT is a
blocker to resolve from retained originals, not a generic invitation to rebuild.
Only a concrete verified identity/missing-artifact problem can justify revisiting
conversion, and then preserve the old assets and document the new candidate.

The tool rehashes the complete bundles and shared support inventories. Extras in
support directories are reported separately and left alone. It excludes the
unused Core ML AudioEncoder from the speech-variable comparison; do not call that
component byte-identical without checking it. Record source/AOT/support/used-decoder
bytes separately. C's known used AOT+decoder sum is 25.17% larger than A, not smaller.

Static AOT inspection cannot prove runtime compatibility with iOS 27.2/24B5084k.
Discover the actual connected iPhone again, verify iPhone18,3/h18p, OS/build and
current developer tools, and record them. Do not label historical caches current
merely because their source manifests match.

## 2. Build once for all precision arms and install in place

Use existing signing/bundle overrides. The last reported device ID and bundle are
shown below, but verify the connected target before using them. Do not request
new signing identities or install a different app bundle to manufacture a pass.

```sh
DEVICE=00008150-000D25942278401C
BUNDLE=com.kevintruong.mural.dev
DD="$E/device-derived-data"
xcrun devicectl list devices --json-output "$E/devices.json"
xcodebuild -version
swift --version
xcodebuild -project Mural.xcodeproj -scheme Mural -configuration Release \
  -destination "platform=iOS,id=$DEVICE" -derivedDataPath "$DD" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" \
  OTHER_SWIFT_FLAGS='$(inherited) -D MURAL_COREAI_TALK -D MURAL_COREAI_W8' build \
  > "$E/build.log" 2>&1
xcrun devicectl device install app --device "$DEVICE" "$DD/Build/Products/Release-iphoneos/Mural.app"
shasum -a 256 "$DD/Build/Products/Release-iphoneos/Mural.app/Mural"
```

Both controls and C use the same executable. Record actual HEAD plus local diff
hash and executable hash. Staged encoder/support folders already used by the
prior trials should remain in place. Verify exact identities on the device; copy
only missing immutable artifacts to an absent destination, never overwrite A.

## 3. Smallest native gate: two fixture-001 turns per arm

No corpus or live user microphone yet. Run A, B, then C in separate processes.
Terminate only the prior owned, drained Mural process, not unrelated applications.
The existing probe auto-runs product modes. Use these app launch arguments:

```text
A:
--coreai-product-mode=staged-gpu --coreai-product-turns=2
--coreai-w8-v3-encoder=fp8 --coreai-w8-v3-decoder=pal8
--coreai-w8-v3-prewarm=always

B:
--coreai-product-mode=staged-gpu --coreai-product-turns=2
--coreai-w8-v3-encoder=fp8 --coreai-w8-v3-decoder=pal6
--coreai-w8-v3-prewarm=always

C:
--coreai-product-mode=staged-gpu --coreai-product-turns=2
--coreai-w8-v3-encoder=pal6 --coreai-w8-v3-decoder=pal6
--coreai-w8-v3-combined=pal6-pal6 --coreai-w8-v3-prewarm=always
```

The empty sequence defaults to fixture 001. Do not combine turns=2 with corpus.
For example, after A and B finish, launch C with the existing devicectl workflow:

```sh
xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE" \
  --coreai-product-mode=staged-gpu --coreai-product-turns=2 \
  --coreai-w8-v3-encoder=pal6 --coreai-w8-v3-decoder=pal6 \
  --coreai-w8-v3-combined=pal6-pal6 --coreai-w8-v3-prewarm=always
```

If C lacks a current-OS cache, this is NOT inference latency or proof of numerical
failure. The already-existing encoder-only mode may specialize the exact artifact
once: use `staged-gpu-encode`, same C precision flags and always, then verify
successful response/hidden output, absence of warnings and repeatability. No
source re-export, cache deletion or decoder concurrency. A thrown ordinary path
error may be fixed and tested; a native crash/wrong output quarantines C.

Recover each UUID run's `report.json`, `events.jsonl`, and actual
`trial-context.json` locally. Do not use only the latest-pointer file. Context
keys are the existing template: source_commit, app_executable_sha256, device_model,
os_build, cache_condition, measurement_protocol, process_session_id,
prewarm_policy, launch_arguments. Use retained-cache-new-process conditions and
same protocol across arms. Record source local-diff hash in an additional field.

Required native observations: terminal=true, complete, stateAtEnd=idle, zero
errors/warnings, exact expected 001 transcript twice, repeated same-input hidden
hash within each arm despite different challenge seeds, correct named entrypoint,
FP16 [1,1920056] C packet -> [1,1500,1280] hidden -> [1,1280,1,1500] decoder input.
No fallback to main. C versus A may have different hidden hashes; B versus A must
not, and C versus D must not. Do not require FP8/PAL6 hidden bit equality.

```sh
PYTHONPATH=Tools/CoreAI python3 Tools/CoreAI/analyze_combined_trial.py \
  --kind native --contrast combined --reference-run "$A_NATIVE" --candidate-run "$C_NATIVE" \
  --output "$E/native-C-vs-A.json"
PYTHONPATH=Tools/CoreAI python3 Tools/CoreAI/analyze_combined_trial.py \
  --kind native --contrast encoder-at-pal6 --reference-run "$B_NATIVE" --candidate-run "$C_NATIVE" \
  --output "$E/native-C-vs-B.json"
```

This verifies a gate, not statistical speed. Inspect function load versus native
execution and phase footprints. If C is already operationally unsafe, stop it.
If correct but evidently dominated by B (slower load/full path, larger RSS, no
incremental decoder-phase saving), report that and avoid a long exercise solely
to obtain a favorable number. A single native pair is noisy, so an otherwise safe
candidate can proceed to the first matched corpus to resolve the tradeoff.

## 4. Matched corpus, bounded continuation

Replace `--coreai-product-turns=2` with `--coreai-product-corpus` in each arm. Keep
all precision/policy flags, retained caches, fixture order, and the same binary.
Run exactly the retained 001-022 corpus. Score 001-016 and 018-022; 017 diagnostic.
Do not ask for new recordings or change references. First run A/B/C once. Stop on
an unsafe native result or serious new speech corruption.

If the first complete comparison shows no worthwhile incremental C advantage,
report C as not worthwhile and retain B as the smaller decoder lab candidate;
no requirement to burn through more runs. If a plausible benefit remains, collect
three complete matched triplets, counterbalanced A-B-C, C-A-B, B-C-A. Fresh
processes each time, retained caches throughout, comparable thermal/rest conditions.
Do not count these as six independent C runs when reusing them for two contrasts.

```sh
PYTHONPATH=Tools/CoreAI python3 Tools/CoreAI/analyze_combined_trial.py \
  --kind corpus --contrast combined \
  --reference-run "$A1" --candidate-run "$C1" \
  --reference-run "$A2" --candidate-run "$C2" \
  --reference-run "$A3" --candidate-run "$C3" --output "$E/C-vs-A.json"
PYTHONPATH=Tools/CoreAI python3 Tools/CoreAI/analyze_combined_trial.py \
  --kind corpus --contrast encoder-at-pal6 \
  --reference-run "$B1" --candidate-run "$C1" \
  --reference-run "$B2" --candidate-run "$C2" \
  --reference-run "$B3" --candidate-run "$C3" --output "$E/C-vs-B.json"
```

With one triplet, omit second/third arguments and label exploratory. D is useful
only to isolate a concrete new combined quality difference or unresolved memory
interaction; it is not an automatic full conversion ladder. The analyzer also
supports `--contrast decoder-at-pal6` with D as reference and C as candidate.

Every raw/token/language/termination difference remains visible. A known 007
variation is not a waiver for different new corruption. Inspect English/Vietnamese
span losses, negation, numbers and content deletion. No tutor corrections, noisy
retry substitution, training or broad precision sweeps.

Report separately: cache lookup, specialization, function load, native encoder,
validation/copy, decoder prewarm/load/loop, full staged harness, encoder-response
and post-release footprint, decoder-loaded and text-end footprint, lifetime RSS,
thermal state and warnings. Keep first turn and warm turns separate. The new
analyzer rejects unpinned encoder hashes even when a report's expected hash agrees
with the wrong hash. Missing measurements are a blocker, not zeros.

## 5. Live and lifecycle only after corpus/resource review

Use the installed interview tool/skill. Prepare the complete instructions and
feedback form on the Mac BEFORE the user begins. Do not open a new form between
Record and speech or between each turn. The user should see the sentence first,
then press Record, speak immediately, press Send, and wait only for Mural's actual
reply/Ready state. Do not introduce silent lead-in delays. Do not subtract browser
or agent response time from app measurements.

Give this six-turn block in one form:
1. Yes.
2. I ordered phở không hành, but they gave me thêm hành.
3. Ngày mai I have an appointment nên em không đi được.
4. I need 15, not 50.
5. No.
6. Today I went to siêu thị. How do I say that in English?

Collect actual speech deviations, exact displayed text, wait, heat and errors
AFTER the block. Keep first attempts and all retries. Use the same environment,
voice volume and app-paced procedure for A/B/C comparisons. Do not simulate real
user pacing with artificial multi-second sleeps. A short first utterance is
important: long reading can conceal unfinished greeting-time preparation.

Run bounded Mural-only logging. In the patched build `asr_trial_audio` has the
same capture ID as Send/final and is emitted once for that capture. Use:

```sh
PYTHONPATH=Tools/CoreAI python3 Tools/CoreAI/analyze_combined_live.py \
  --log "$OWNED_MURAL_LOG" --output "$E/correlated-live.json"
```

Missing ID-correlated audio must be reported, not joined by row number. Save
ASR-only success separately if the tutor/audio step fails. Send-to-first-audio
includes tutor/TTS/coordinator work; do not call the residual pure tutor time.
The callback is not a microphone measurement of acoustic onset.

Before promotion, separately test End during encoder/decoder work, backgrounding,
return/reprepare, a fresh conversation and focused offline mixed speech. Verify
native work actually drains before a new owner starts and no late transcript/audio
appears in a new session. Keep cancelled/recovered tests separate from successful
latency distributions. Quiet Yes/No remain valid; silence/VAD thresholds unchanged.
If lifecycle safety cannot be established, C is not promoted even with good words.

## 6. Prewarm only after the precision decision

Use the interview tool for one explicit review of the precision result. No
normal/default promotion. Only after a precision pair is accepted for this next
experiment, compare always versus once with BOTH model artifacts fixed. The code
permits C+once explicitly, but it must not be mixed into the precision comparison.
Always remains the default. Existing B+once is also available if B remains the
chosen lab pair; no reason to force the slower C simply to test policy.

For corpus policy checks use `--contrast prewarm`; for a product decision also run
matched natural-pace live blocks with ID-correlated app timings. Keep the real
load/unload/native-drain path and successful-prewarm latch behavior unchanged.
Do not implement decoder residency or model overlap as a hidden second variable.

## 7. Recoverable errors and completion

Use an attempt ledger:
phase -> error -> hypothesis -> changed variable -> predicted result -> actual
result -> next action. Correct clear syntax/path/SDK-signature/staging errors and
continue. At most three materially different evidence-backed hypotheses for a
recoverable native/compiler contract problem. Ordinary typo fixes do not count.
No unchanged crash relaunch, no hash edits, reference changes, cache deletion,
warning-latch clearing or claims that a failed specialization was inference.

Quarantine the candidate on wrong identity/ABI/numerical output, crash, memory
warning, unsafe ownership or serious new speech corruption. Preserve safe work
and A. Do not ask the user to take over engineering; use the interview tool for
physical actions and feedback only.

Stop owned captures/logging on completion. Publish only a sanitized report using
`combined-result.template.md`, alongside the narrow code changes after testing.
Private recordings, full logs, the app store and screenshots remain ignored.
Use aggregate/per-fixture numeric results and necessary consented text differences,
plus hashes for local evidence. Record exact command lines, app/source/diff hashes,
model identities, tool/device context, excluded runs and all failures.

Before any commit/push, review `git diff --check` and `git diff --stat`; stage only
explicit implementation and sanitized-report paths. Fetch origin/mvp again. Push
only a normal fast-forward `git push origin HEAD:mvp` after ancestry review; never
force. If remote advanced incompatibly, preserve the local commit and report the
conflict rather than reset, auto-stash or merge unrelated work. The remote review
itself did not create a commit.

End with one precise disposition: C is preferable to both A and B; B remains the
better lab candidate; C is unsafe/blocked; or C provides insufficient incremental
benefit. Never declare a speed win from the replay timer or a RAM win from AOT size.
