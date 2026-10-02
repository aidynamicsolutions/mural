# Online-agent handover: review Breeze PAL4 and research an optimized export

## Copy/paste prompt

Review `aidynamicsolutions/mural`, branch **`trial/breeze-pal4`**, without merging or promoting it. This branch is a source/research checkpoint, not production qualification. Read repository `AGENTS.md`, `docs/asr/chinese/breeze-pal4-loading-checkpoint.md`, `docs/asr/chinese/breeze-pal4-trial-plan.md`, current local-conversation/physical guides, and relevant Apple/concurrency/testing skills before proposing changes.

### User objective

Reduce three distinct costs on iPhone 17:
1. Initial public model download size.
2. Whole-process physical memory footprint while preparing and speaking.
3. First-ever Prepare & start latency, not just subsequent cached loading.

The user tolerates a modest accuracy loss if useful, but no numerical acceptance thresholds have been approved. Their proposed next direction is to obtain the authentic full-precision FP16 Breeze checkpoint and build an independently pinned, better-optimized PAL4 export. **Evaluate that hypothesis rather than assuming it will work or that smaller files imply faster initialization.** Research/recommend first; do not start paid compute, large conversion/training jobs, publish weights, change defaults or deploy a release without a separately reviewed plan. Do not resume FireRed.

### What this branch implements

- Build-gated PAL8/PAL4 selection with explicit launch arguments, default PAL8, independent candidate pin and asset directory; production PAL8 pin unchanged.
- Public immutable-HF inventory resolution, verified download/package tooling, exact baseline tokenizer/support reuse, review-bound candidate pin generation, benchmark schema/comparison tool and synthetic contract tests.
- Existing physical runner integration, not a second runner: exact compiled arm/manifest/executable/PID proof; candidate/source/prepared-artifact fingerprints; one-install reuse between arms; actual turn/timing/memory export; existing playback completion/nonce, capture, timeout, ownership and cleanup gates.
- Trial-only diagnostics; shared Chinese ASR owner and raw recognition versus display-only OpenCC unchanged.
- Fix for a real Apple `/var` versus `/private/var` inventory-path alias, retaining symlink/extra-file refusal, with a production Swift regression test.
- Narrow explicitly authorized retained-session End/owned failed-setup recovery and one PAL4 first-load budget option. These flags do not constitute authorization for a future agent to end personal sessions or extend budgets automatically.
- Report/export schema repair after the comparison tool rejected descriptive fixture categories and absolute WAV paths. Original categories/references/source paths remain recorded; original exports retained privately.

Primary files: `App/BreezeTrialSelection.swift`, `App/BreezePAL4TrialPin.swift`, `App/BreezeEnglishRecognizer.swift`, affected `LocalConversationEngine`/`RootView`, `scripts/verify_device.py`, `UITests/MuralUITests.swift`, `scripts/test_breeze_trial_runner.py`, and `Tools/ChineseASR/breeze*` / `test_breeze_pal4_trial.py` / review template.

### Exact candidate and runtime

- Community export: `weiren119/Breeze-ASR-25-coreml-4bit-palette` at `3fc162355f3460de6b1e53518a1678cea06464d9`.
- Source-lock SHA-256: `2400153765be7bbb932818d944f40ce915860b6f67aa4c392770903b3284eae1`.
- Candidate packaged manifest: `5ed79986de6ae21ca1ea8798e49e38d7c06a3ff9635ac6ef59ade5531cca0f5e`; 28 files, identity `breeze-asr25-weiren-pal4-3fc162355f34-5ed79986de6a`.
- Baseline manifest: `64021fb776ee2ef4cf02c05b2a9dafde0e0700e9bf7d967b4bc5302558b5fdb4`, revision `cffe7ccb404d025296a00758d0a33468bec3a9d0`.
- WhisperKit `1e2a163736dfa5a198e637ae44c114e1c6d5cc2d`; iPhone18,3 / iOS 27.2 build 24B5084k. Encoder/decoder CPU+Neural Engine, frontend CPU+GPU, M5 voice.
- Runtime input contract: mono 16 kHz, full waveform up to 30 seconds, 80 mel, width 1280, 32 encoder/decoder layers, vocabulary 51,865. Preserve exact cache/tensor/control-token/tokenizer contracts, automatic-language transcription, no expected-answer prompt and English output.
- Source card claims Apache-2.0, but community export has no separate LICENSE/NOTICE or established exact conversion recipe/source lineage. Baseline notices retained. Review provenance before redistribution.

### Actual measurements, with limitations

| Metric | PAL8 | PAL4 |
| --- | ---: | ---: |
| Runtime payload | 1,657,744,068 bytes | 1,115,606,230 bytes |
| Fresh-process warm native load, one AB pair | 3.102 s | 3.202 s |
| ASR preparation surrounding that load | 3.453 s | 3.516 s |
| Whole-process physical-footprint peak | 2,085,980,408 bytes | 1,532,037,344 bytes |
| RSS peak, separate from footprint | 368,017,408 bytes | 445,956,096 bytes |

The payload is about 33% smaller; actual initial wire transfer was not measured. Physical footprint was about 27% lower in that sample, while RSS was higher. Both load intervals were nominal thermal state, but PAL8 later reached fair state during the longer generated reply/cleanup. Do not generalize one pair or compare different reply durations as an ASR speedup. Retaining both packages uses 2,773,350,298 payload bytes before app/cache/staging; installed total was not measured.

Initial observations were unpaired: PAL4 prewarm ran 269.14 s and returned canceled after the readiness deadline; decoder 57.698 s, encoder 211.076 s. PAL8's first observed current-install load was 156.14 s. The subsequent successful PAL4 preparation benefited from previous native work, so it was not pristine cold. The user-approved longer readiness allowance enabled a bounded attempt; it was not a performance optimization. Existing historical PAL8 post-install 161-172 s is not a new regression.

Actual graph audit found PAL4 encoder/decoder 388/640 convolutions versus PAL8 194/320, plus 192/321 sparse-to-dense operations absent in PAL8. Candidate LUTs really contain 16 FP16 palette entries and two packed 4-bit indices per byte; residual FP16 remains. Tensor/cache metadata matched; frontend outputs on a fixed waveform matched exactly on Mac CPU/GPU. These are different exports, not a controlled bit-width-only comparison. More specialization work is plausible, not profiler-proven causal attribution.

Both arms passed a physical English-number acoustic turn with matching raw recognition and normal End/settings/cleanup. A second PAL4 warm run produced an incorrect transcript, despite completed playback and nonce gates. Keep that failure; compression versus acoustic variation is unresolved. Mac CPU/GPU ran all six approved clips for both packages, retaining empty/incorrect outputs. Mac Neural Engine probing timed out and is unqualified. No human listening confirmation is supplied for these runs.

The next PAL8 BA partner was interrupted by the **host limiter**, before XCTest/preparation/playback, not by Core ML. Original failure/cleanup failure is retained, and independent owned-process recovery confirmed cleanup. No automatic retry. Thus there is one complete AB pair, not the proposed AB/BA/AB series, no physical mixed-speech qualification, no broad accuracy or lifecycle claim, no qualified profiler trace, and no +30 s post-drain/storage/cache/network measurements.

### Review tasks

1. Review source correctness, failure paths and unchanged production behavior. Pay particular attention to trial selection, fail-closed pin/inventory checks, prepared-artifact reuse, current-PID proof, capture/playback nonce gates, first-load cancellation/drain and cleanup.
2. Treat the exporter as intentionally narrow: it currently requires completed recognition and does not export VAD-rejected/failed turns as complete runs. Extend failure/silence support with tests before broad corpus work, without hiding failures. The comparison tool supports more schema cases than the native exporter currently produces.
3. Inspect offline re-export provenance: policy hashes currently come from the checkout, so saved evidence must not be re-exported against changed model/VAD source. Existing re-export changed metadata only while those sources were unchanged. Consider enforcing this explicitly before future reuse.
4. Inspect `breeze_load_profile`, which still specializes on PAL8; candidate native component timings were read from exact candidate log events, not that summary helper. A generic summary must retain exact identity/PID checks.
5. Verify tests and distinguish historical failures from regressions. Do not resurrect an obsolete memory-warning pause. Current advisory warnings log/continue; sampled 3 GB and serious/critical thermal guards remain mandatory.
6. Do not treat the committed report, private review hash or synthetic test booleans as independently accessible native evidence. An online-only reviewer can verify source and public artifacts but cannot claim to have rerun the iPhone or read private logs.

Focused host checks:

```sh
python3 -m unittest discover -s Tools/ChineseASR -p test_breeze_pal4_trial.py
python3 scripts/test_breeze_trial_runner.py
python3 scripts/test_verify_device.py
```

Latest local results: 38 tests passed (including actual Swift parser in both build modes and alias inventory regression); 4 runner integration tests passed; existing host runner checks passed. Swift checks may skip without an Apple toolchain, which must be reported. Full signed trial app/runner build and native model-free arm checks passed before replay. Last exporter repair was host-only, so future phone replay requires refreshed source fingerprints/model-free checks. Historical `test_prepare.py` had 4 failures and 1 error in 17 tests **before patching**; the full historical suite is not green.

### Research the next export

Use authoritative Apple/Core ML documentation and pinned conversion/runtime source, with links and availability details. Produce a short ranked plan, not a speculative framework:

1. Locate the authentic upstream Breeze full-precision checkpoint. Pin exact revision, inventory, license/notices, architecture and tokenizer. Verify whether usable FP16 PyTorch/safetensors or an exportable uncompressed Core ML model exists; a compiled `.mlmodelc` is not automatically a supported re-quantization source. Never dequantize PAL8 and call it original FP16.
2. Reconstruct the smallest trustworthy conversion path compatible with the pinned WhisperKit decoder/cache interface. Investigate why the community export doubles convolution/sparse operations, what those operations do, and whether a newer deployment target/compression representation can avoid that topology without changing behavior. Do not assume graph counts alone identify the culprit.
3. Compare full-precision and controlled PAL8/PAL4 variants from the **same source and graph**. Review per-tensor/grouped palettes, sparse-plus-palette composition, sensitive layers retained at higher precision, and data-free versus calibration-dependent methods only where evidence justifies them. No recipe is selected yet. Calibration data must be licensed and separate from held-out frozen evaluation references.
4. Separate offline conversion time, device-specific initial specialization, native load/validation, full UI Prepare-to-ready, first/warm inference and whole-process memory. Core ML may still require first-device specialization even for precompiled bundles. Do not promise that shipping a compiled model eliminates it.
5. Propose a small native Mac screen, then fresh authorized iPhone smoke with one signed binary across arms and stable paths/caches. A true cold-cache study may need a separately approved isolated identity or device plan, not erasure/reinstallation of personal data. Make the causal comparison fair while preserving the existing app slots.
6. Freeze accuracy criteria with the user before acceptance. Preserve numbers/names/negation, English, short replies and silence. Start with the existing approved corpus and add only missing coverage; expand toward 60-100 clips and 20-turn/lifecycle only after favorable smoke. No OpenCC scoring cleanup, expected-answer hints or dropped failures.

Deliver: prioritized source review with file/line evidence, public-source research on conversion options, expected risks rather than promised speedups, a concrete bounded experiment and go/no-go gates. Keep this branch review-only until authorized otherwise.

### Local-only evidence and cleanup context

Original worktree was `/Users/tiger/.treehouse/mural-92c3ee/1/mural`, leased exclusively for this trial. Its private evidence is preserved outside the worktree at `/Users/tiger/Dev/ios/mural/.build/verification/breeze-pal4-handover-20261002/`. This archive is **not uploaded** and is unavailable to the online agent. Reports retain original absolute paths for provenance; use the archived matching relative suffix, never rewrite original logs to fabricate portability. Runtime build receipts cease to be reusable once their artifact directories are removed.

Cleanup removes the pushed worktree's disposable DerivedData, package/snapshot/readback copies and worktree-local package caches, not the main checkout's baseline package, shared HF cache, phone models/history/voices/settings or original approved recordings. The existing signed trial remains installed with icon launch defaulting to PAL8; no final manual PAL4 smoke is claimed. No extra app slot was created. PAL4 manual use requires an explicit coordinated trial launch, not just tapping the icon.

The installed host `active-ios-simulator-limit` received a narrow EPERM/exited-process patch during debugging; its original backup, reproducer and logs are archived. A later EPERM still interrupted a run, so that patch is incomplete. It is outside this branch and must be repaired/reviewed in the tool's own project before further unattended device work; do not bypass the limiter or stop other agents. Wrap complete builds/runtime with the required limiter and existing ownership-aware runner. Restore/rebuild only through authorized current device procedures.

Wrap-up read-only status on October 2 found a new Mural process after the completed owned runs. It was not adopted, captured or terminated. The earlier owned cleanup remains separately evidenced; cleanup authorization for the worktree is not authorization to stop a new personal phone session.
