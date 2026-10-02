# Breeze PAL4 community-export trial

Current status: **candidate armed for isolated trial; signed iPhone load/acoustic smoke performed, qualification incomplete**. See the [2026-10-02 loading checkpoint](breeze-pal4-loading-checkpoint.md) for actual results, failures and remaining gates. The research-packet scope below describes the original handover, not current completion.
Base: `aidynamicsolutions/mural`, `mvp`, `c3feba0998c1dd366497114ac7e46845b62cdb7a`.
Requested candidate: `weiren119/Breeze-ASR-25-coreml-4bit-palette`.
This is not production promotion, a distribution implementation, or phone qualification.

## Decision and evidence

Try this already-exported candidate before commissioning another quantization run. Its model card claims Whisper-large-v2, Chinese/English, three compiled Core ML bundles and four-bit palette compression, with an Apache-2.0 label [1]. That is a promising match to the current architecture, not proof of compatible tensors, preserved lexical vocabulary, actual bit packing, speed or accuracy.

The research environment could read the card but not HF's file inventory/API/raw metadata. It did not obtain an immutable candidate revision, verify model bytes, execute Core ML, or measure this candidate. Do not invent these missing values. The delivered resolver obtains and locks them locally; the app's empty candidate pin deliberately refuses loading until review. The card does not establish an exact pre-quantization source revision or conversion recipe. This experiment compares **two complete exports**, not four bits versus eight bits with every other graph property proven identical.

Baseline facts, already recorded in the repository [2,3]:

| Baseline | Value |
| --- | --- |
| Identity | `breeze-asr25-pal8-v1` |
| Manifest SHA-256 | `64021fb776ee2ef4cf02c05b2a9dafde0e0700e9bf7d967b4bc5302558b5fdb4` |
| MediaTek source revision | `cffe7ccb404d025296a00758d0a33468bec3a9d0` |
| Runtime file inventory | 1,657,744,068 bytes, excluding manifest and caches |
| WhisperKit revision | `1e2a163736dfa5a198e637ae44c114e1c6d5cc2d` (1.1.0) |
| Frontend / architecture | 16 kHz mono, 80 mel, 30 seconds, width 1280, 32 encoder/32 decoder layers, vocabulary 51,865 |
| Existing preparation distinction | Approximately five-second unchanged-install warm restart; historical post-install load/validation 161–172 seconds. Known distinction, not a newly discovered defect. |

Four-bit weights do not imply half the whole app RAM. Report separately: source/download payload, measured network bytes, allocated model storage, attributable private caches, installation staging, whole-process physical footprint and RSS, preparation, ASR including VAD, WhisperKit transcription and UI Send-to-final latency. The comparison must not substitute one for another. Apple documents preparation-cache and device profiling considerations [6].

## Delivered source changes

1. A build-gated selector: compile `MURAL_BREEZE_PAL4_TRIAL`, then select exactly one launch argument `--breeze-trial=pal8` or `--breeze-trial=pal4`. No argument still means PAL8. Trial arguments in ordinary builds, malformed arguments and duplicates fail closed. No persistent preference, arbitrary path, remote pin override or new provider picker.
2. Existing Breeze actor resolves a separately pinned candidate directory only for the PAL4 arm. Asset preflight and backend labels use the same resolver. Both Chinese writing modes retain their shared actor. The default managed/retained PAL8 path and production pin are unchanged.
3. Full chunked hash, path/symlink, inventory, tokenizer/control-token and native-shape validation remains. Candidate identity includes export revision and packaged-manifest hash; separate preparation receipts follow the existing identity mechanism. Unlisted candidate files are refused. No graph is unloaded underneath inference; the existing owner remains responsible for cancellation/drain.
4. Trial-only, content-free identity/preparation/VAD-inclusive transcription markers complement existing component-loading, decode, memory and Send/final markers. Both arms in the trial binary receive the same instrumentation.
5. `breeze_pal4_trial.py` resolves/fetches immutable public HF files, compares metadata, assembles candidate bundles with the baseline's exact support/tokenizer bytes, and emits a compiled-in pin only after recorded native Mac review. No weight conversion or in-app downloader change.
6. `breeze_ab_report.py` reuses the existing `evaluate.py` metric. It refuses incomplete, mismatched, same-model, unclean and safety-stopped comparisons. Missing resource measurements remain unknown. It reports raw script-sensitive MER, changed clips, silence regressions, optional exact entity presence, duration/language/first-turn timing strata, and separate cold/warm preparation. It does not infer trust from JSON alone or auto-promote a candidate.

**Not implemented in the original packet (see current checkpoint above):** HF live download/inspection, native Mac model execution, Xcode app/runner build, physical launch/install, current native runner's arm/manifest propagation and receipt exporter, full corpus admission, or any measured PAL4 benefit. The local agent must finish the narrow runner adaptation described below. The report consumes evidence-backed records; it is not itself a phone benchmark runner. No public model package/catalog entry is published.

## Gate 1 — Inspect the existing candidate; do not re-quantize

Keep all artifacts under a new ignored directory, for example `.build/verification/breeze-pal4/<unique-id>/`. Preserve prior results. Use the existing compatible model tools environment, with its package versions recorded; only `resolve`/`fetch` require `huggingface_hub`. No `trust_remote_code`, credentials, source training weights, or external inference API are needed.

From the repository root, with `TRIAL` set to the new directory and `BASELINE` set to the independently verified PAL8 artifact directory:

```sh
python3 Tools/ChineseASR/breeze_pal4_trial.py resolve \
  --output "$TRIAL/source-lock.json"
# Inspect the source revision, selected inventory and source bytes. Copy the
# printed lock_sha256 into LOCK_SHA; it is NOT the eventual packaged model pin.
python3 Tools/ChineseASR/breeze_pal4_trial.py fetch \
  --lock "$TRIAL/source-lock.json" --lock-sha256 "$LOCK_SHA" \
  --output "$TRIAL/snapshot"
python3 Tools/ChineseASR/breeze_pal4_trial.py package \
  --baseline "$BASELINE" --snapshot "$TRIAL/snapshot" \
  --lock "$TRIAL/source-lock.json" --output "$TRIAL/package"
```

The resolver reads moving `main` **only to discover a full SHA** and queries that SHA again. Fetches use only the locked revision and verify LFS SHA-256 or Git-blob SHA-1 identities and sizes. Pin the source-lock hash separately. Host Hub cache reuse is not measured network transfer. Retain the exact model card and any exported LICENSE/NOTICE beside baseline notices.

Packaging reads the existing independently pinned PAL8 manifest and verifies all its inventory before reusing lexical/support files. This avoids silently borrowing a stock Whisper/PhoWhisper tokenizer. It checks exact tensor/cache names, dimensions, data types and optional/flexible-shape metadata against PAL8 and requires PAL4 declarations and visible LUT operations for encoder/decoder. These are screening checks, **not independent compression or native execution proof**. A metadata spelling/layout mismatch may require a narrow, tested parser adjustment; an actual tensor/cache mismatch needs adapter review. Do not bypass hashes, change VAD, truncate tokens, substitute models, or automatically start a conversion campaign to get a green result.

On the Mac, inspect actual graph/weight LUT representation and dimensions (including residual higher-precision weights), original versus candidate frontend numerical behavior, source notices and topology. Use the pinned WhisperKit runtime and matching decoder/tokenizer settings for a few fixed clips. Native load, finite outputs, cache/control-token compatibility and short Mandarin/English transcription must work before phone admission. Save the actual command, environment, input hashes, output/shape checks and failures in a local native evidence file. Host speed/RAM is not phone evidence. The review should explicitly acknowledge any source-lineage uncertainty.

Copy `pal4-review.template.json` into the trial directory. Complete only fields supported by the actual inspection; bind the audit and native evidence with SHA-256. Leave failed/unrun fields false. Then:

```sh
python3 Tools/ChineseASR/breeze_pal4_trial.py arm \
  --package "$TRIAL/package" --review "$TRIAL/review.json" \
  --output "$TRIAL/BreezePAL4TrialPin.swift"
```

Review the emitted source before replacing the **unconfigured candidate-only** `App/BreezePAL4TrialPin.swift`. Do not change `SpeechPackagePins.breezeManifest`. Arming records review; it is not cryptographic proof that the reviewer actually ran the tests. Every candidate file is reverified before emitting the pin and again by the app.

Stage the resulting package as regular files in a **new** `Application Support/BreezeASR25/<identity-from-audit>` directory within the existing app container, using the established owned transfer mechanism and independent readback. Do not overwrite baseline files or any active managed pointer. Both packages remain installed during A/B: the experiment temporarily **increases total disk use**. Report each package separately; defer cleanup of any accepted baseline to a separate decision. This is a retained-asset experiment, not App Store first-download qualification.

## Gate 2 — Reuse the real corpora; add only missing coverage

### Existing Mainland-oriented fixtures: MELI

The repository's `simplified-talk-qualification-plan.md` records six human-approved clips from MELI with pre-frozen references [4]. Look locally first for:

```
.build/verification/simplified-talk-meli-20260928/frozen-manifest-v1.json
SHA-256: 11704fc265b19de99b899e668d1b3b3de3d87d1b873c31d3e0406c9811f25cbc
```

Also retain `reviewer-approval.json`, `review-manifest.json` and the original clipping recipe. Selected speakers F00A, M00A and F89A have documented Mainland upbringing; they were recorded in an overseas setting, not a representative mainland-resident population. The six-clip set lacked proper-name and separate Yes/No coverage. Reuse **fixtures and review**, not historical FireRed scripts, backend settings or old device authorization.

These are private ignored artifacts, not audio contained in Git or this patch. A matching manifest alone does not prove its WAVs exist and match. Validate each clip's actual checksum, speaker channel, boundaries, format and duration. If absent, use MELI's official release/annotation metadata and frozen identities to reconstruct only needed clips, preserving the reference-approval requirement. Official MELI download terms specify CC-BY 4.0 [5]; retain attribution and inspect the exact selected release. Do not download the entire corpus unnecessarily.

### Earlier mixed-sentence lead: ASCEND

The historical plan identifies ASCEND as supplementary; its official card contains Chinese, English and intra-sentence mixed speech and marks CC-BY-SA 4.0 [7]. Check for a previously frozen local selection first. This review did **not** establish an available, approved local ASCEND audio set. Use unseen held-out speakers/clips and freeze selection before seeing either arm's results. Account for attribution/share-alike obligations before redistributing adaptations; no audio is distributed in this packet.

The two `taiwan-smoke.template.json` / `mainland-smoke.template.json` files are authored recording templates, not recorded corpora or evidence of accuracy. CS-Dialogue is not a replacement shortcut: retained docs flag commercial-product restrictions; TALCS licensing was not verified [4]. Neither is admitted by this plan.

### Efficient coverage ladder

Start with the six frozen MELI clips plus a small fixed set covering English-only, real short replies, silence/room noise, and at least one name/number/technical-term mixed sentence. Do not build a 420-clip program before discovering whether this candidate loads and is usable.

Only after the smoke passes, expand toward **60–100 fixed clips** across several speakers: Mandarin-only, English-only, Chinese→English, English→Chinese, multiple switches, names, dates/decimals/digits/units, API/version/technical terms, subsecond and longer Yes/No/OK replies, hesitations and quiet onsets, digital silence and environmental non-speech. Include Taiwan and Mainland speech and some near-30-second turns. Use genuine mixed speech; do not stitch separate languages or accelerate audio. Synthetic controls must be labeled, not called human speech.

Preserve all known prerecorded failures. Reference text is scoring-only, never a decoder prompt. Keep exact raw output and existing NFC/case/punctuation scoring rules; no OpenCC conversion in primary ASR scoring. Raw script differences, word errors, English-span errors and user-facing Simplified display must be reported separately. An optional secondary script-normalized analysis needs a separately frozen rule and cannot replace raw scores. The delivered entity measure is token-sequence presence only; human review must catch wrong values, swapped roles and negation.

Export an additional immutable evaluator manifest in `mural.chinese-asr.corpus.v1` format rather than modifying the original frozen MELI evidence. Record its relationship to the original manifest and each audio hash. Use existing `evaluate.py check-audio` for the 16 kHz mono PCM16/30-second checks. No references may be revised after seeing a candidate output without versioning and rerunning both arms on a new held-out set.

## Gate 3 — Native build and the existing runner

Read `AGENTS.md`, the current local-conversation verification guide and physical-device workflow. Work from the full checkout without reset/stash/rebase/force push or overwriting concurrent edits. Preserve the exact signed main app and runner identities, current runtime/dependency pins, voice settings, assets and personal history.

Generate the trial project in an isolated output directory using the existing `scripts/generate_project.py --output-directory ...`. The generator already discovers added `App/*.swift` files. Preserve the phone's explicit `MURAL_COREAI_TALK` Release and add only `MURAL_BREEZE_PAL4_TRIAL` for this experiment. Inspect actual compiler flags, source membership, app/runner signatures and bytes; a requested flag is not proof. Do not use FireRed generator options or hand-edit generated project files. Native typechecking of the complete app is required; Linux syntax parsing is not a build.

**Remaining local implementation:** minimally extend `scripts/verify_device.py` and the corresponding existing `UITests/MuralUITests.swift` path to propagate the selected launch arm, expect the arm's exact identity/manifest, fingerprint the emitted candidate pin and launch configuration, and export the existing exact-PID/turn observations into the report schema. Do not broadly accept either backend/pin in a test that expects one. Use `DEVICE_PAIR=breeze-zh-CN-en`, not legacy `zh-CN-en`. Read actual current stage arguments rather than inventing unsupported Make flags. The provided app recognizes `--breeze-trial=...`; the existing runner does not yet forward it automatically.

Qualify selector/arm propagation, missing pin/assets, mismatched identity, receipt export, timeout and cleanup paths model-free before an expensive model replay. Reuse the current acoustic capture/playback/nonce gates and actual Send/final correlation; do not introduce a second app, runner or audio owner. Fixed file replay is useful for reproducible ASR comparison only if it calls the existing actor/owner; never label file-replay latency as UI acoustic Send-to-final. Keep the mode explicit and compare like with like.

## Gate 4 — Matched iPhone 17 A/B (Phase C)

1. Save the current PAL8 identity and ordinary-app baseline evidence before any candidate activation. This is context. For the causal A/B, install **one signed trial binary once**, with both verified packages retained, and use that exact binary for both arms. Reinstallation between arms would confound preparation and private caches.
2. Refresh device/process ownership, exclusive idle/unlocked/cool readiness and permitted audio playback immediately before the run. Reuse the existing main/runner slots and locks. No room-audio recording, cache deletion, app uninstall, fourth QA slot or unrelated process termination.
3. Run a bounded PAL8 smoke, then PAL4 smoke with the same fixtures, compute units, VAD, 220-token budget, zero temperature fallback, automatic-language transcription, full waveform and selected voice. Record actual raw accuracy, component load times, end-to-end finalization, whole-process memory and faults. Stop on real model errors, the sampled 3 GB limit or serious/critical thermal state; no automatic failed-graph retry.
4. Separate each identity's first observed artifact load from unchanged-install warm restart. Existing warm/cold observations are not a new bug. Do not call a first artifact load a proven internally cold cache. If no like-for-like cold baseline exists, report it as unpaired. A literal clean-install comparison needs separately authorized clean-device conditions, not deletion of this user's app/data.
5. After both are qualified for a short run, use fresh processes for matched warm comparisons, e.g. **AB, BA, AB**, with A=PAL8 and B=PAL4 (three runs per arm). Preserve fixture order within each pair, first/warm inference positions, input duration and acoustic placement/output level. Counterbalance order and let thermal state recover. Each run gets a distinct PID/start identity and exactly one model arm; do not mix process-lifetime memory peaks from both models.
6. Capture the already available kernel process-lifetime physical-footprint peak and phase samples, not just RSS or allocation totals. Use app-scoped Core ML/Allocations/VM traces when the existing profiler capture passes its model-free check; otherwise explicitly report missing placement/cache attribution. No zero-model-event trace is evidence. Instruments-assisted and low-overhead runs must be separate matched strata. Use identical inference instrumentation and report its overhead as a limitation.
7. Report preparation including separate asset verification, VAD initialization, prewarm and model load; first and warm transcription; ASR including VAD; full UI Send-to-final; peak physical footprint; post-End/drain release at +2/+10/+30 seconds where supported; thermal and memory warning events; file bytes/allocated disk/caches/staging/real network bytes. Do not relabel download source bytes as measured network usage.
8. Only after favorable short comparisons, perform the bounded 20-turn/lifecycle checks: End/cancel during preparation and inference, background/foreground, offline restart, no stale completion or overlapping owners, English reply and screen-only Chinese Help, both writing modes, new-UUID raw/display persistence. Preserve canonical/raw before OpenCC projection. Do not inspect or export whole personal history.

Current advisory memory warnings log and continue; do not reintroduce the superseded warning-induced pause or disable genuine safety guards. Record warning events and review stability; a lack of warnings is not a lifetime memory guarantee. Save first failures separately from later fixes/recovery. Reserve bounded cleanup and independently confirm restoration/readback and owned-process cleanup on every outcome. Return the phone to its authorized ordinary configuration when the trial concludes; never silently leave the PAL4-selected process running.

## Gate 5 — Comparison and provisional acceptance

Create one prediction file per real process, following `breeze-ab-run.template.json`. Template false/empty values intentionally fail validation; do not fill them with fabricated success. Export from the owned runner's real logs/results, preserving the underlying evidence. `app_sha256`, install identity, hardware/OS, runtime, VAD/decoder policy, input mode, frozen corpus/audio inventory and meaning pair must match across each compared pair. The baseline model manifest must match the reviewed PAL8 pin; the candidate manifest must match the armed pin. Verify that last requirement in the runner (the general comparator only requires a different valid hash).

Predictions contain all corpus IDs with exact raw `text`, `audio_seconds`, `vad_rejected`, `first_since_prepare` and measured timing fields. Omit unmeasured prediction metrics; do not use zero. VAD-rejected clips have no decoder interval, not a zero-cost decode. The report compares decoder intervals only where both arms accepted the clip, lists exclusions, and still counts false rejections as deletions in accuracy. For acoustic runs, `audio_seconds` is the identical **source fixture duration**; retain actual microphone-capture duration separately in native evidence.

```sh
python3 Tools/ChineseASR/breeze_ab_report.py \
  "$TRIAL/corpus.json" "$TRIAL/pal8-run.json" "$TRIAL/pal4-run.json" \
  --output "$TRIAL/comparison.json"
# --include-text is for a private review report only, never a public commit.
```

Suggested decision criteria, **proposals rather than user-approved numeric limits**:

- A useful first result is at least 15% lower measured peak physical footprint or 15% faster p95 Send-to-final, or at least 20% lower model payload, without a material regression in other important dimensions. Choose the user priority explicitly; a storage-only win must be labeled storage-only.
- To reflect the user's tolerance for a small accuracy loss, provisionally review candidates within +2 percentage points MER overall and mixed-speech strata, and +3 points English-only WER, with manual review of every changed critical number/name/negation and lost short response. These are descriptive screening bands, not proof of equivalence. The delivered scorer reports MER and per-group detail; a separate English-span WER/alignment analysis is still required. If the reference group is all English, its MER tokenization gives a declared word-error measure, not a publisher-standard WER reproduction.
- Require no new nonempty silence/noise output in the fixed suite, no English translation/erasure, and all lifecycle/integrity/display gates. An improved average cannot conceal a failure on critical values. Existing baseline failures remain failed.
- Report each run/pair and small-sample uncertainty. A six-clip p95 is not a reliable production tail estimate. If results vary materially by speaker/order/thermal state, expand the paired test instead of claiming a speedup.

No script changes defaults, promotes models, publishes a package or claims qualification automatically. Present the measured table, actual changed transcripts privately, limitations, failure records and rollback recommendation for a separate promotion decision.

## Sources and local evidence pointers

[1] Candidate model card: https://huggingface.co/weiren119/Breeze-ASR-25-coreml-4bit-palette

[2] `docs/asr/chinese/breeze-native-result-20260920.md` at the base commit: baseline export/runtime/byte identities; historical bounded phone observations only.

[3] `docs/asr/chinese/breeze-simplified-implementation-20260928.md` and `.agents/skills/verify-mural/features/local-conversation.md`: current shared backend, raw/display boundary, warm-load and guard dispositions.

[4] `docs/asr/chinese/simplified-talk-qualification-plan.md`, primary-corpus section and September 28 frozen-reference checkpoint: MELI fixture identities/provenance. Read for corpus evidence only; FireRed runtime work remains out of scope.

[5] MELI official download/citation: https://meli-corpus.readthedocs.io/en/latest/4-download/ ; DOI https://doi.org/10.5683/SP3/5WMRUO

[6] Apple, Improve Core ML integration with async prediction / model loading and cache guidance: https://developer.apple.com/videos/play/wwdc2023/10049/ ; gathering memory information: https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use

[7] ASCEND official card: https://huggingface.co/datasets/CAiRE/ASCEND

[8] HF Hub API reference for immutable metadata and file identities: https://huggingface.co/docs/huggingface_hub/en/package_reference/hf_api
