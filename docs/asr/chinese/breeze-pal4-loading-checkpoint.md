# Breeze PAL4 loading checkpoint, 2026-10-02

Status: isolated signed trial installed in the existing iPhone app slot; **not promoted or fully qualified**. No new app slot, baseline replacement, managed-pointer mutation, cache clearing or model conversion.

## Loading result

Smaller model files did not establish faster first preparation. Core ML loading includes device/compute-specific specialization, not just file I/O. Apple's [WWDC23 Core ML performance session](https://developer.apple.com/videos/play/wwdc2023/10049/) describes specialization and caching around 9:50-11:50.

Actual exported graphs differ materially: PAL4 encoder/decoder contain 388/640 convolutions versus PAL8's 194/320, plus 192/321 sparse-to-dense operations absent in PAL8. Actual candidate LUTs contain 16 FP16 entries with two packed 4-bit indices per byte; residual FP16 constants remain. This is an export comparison, not a controlled bit-width-only experiment. Extra specialization work is a plausible explanation, not a trace-proven attribution.

| Scope | PAL8 | PAL4 |
| --- | ---: | ---: |
| Runtime package payload, bytes | 1,657,744,068 | 1,115,606,230 |
| Observed initial native work | 156.14 s load | 269.14 s prewarm, canceled after readiness deadline |
| Completed fresh-process warm native load, matched AB | 3.102 s | 3.202 s |
| Warm ASR preparation including surrounding work | 3.453 s | 3.516 s |
| UI Prepare-to-ready, including other components | 16.468 s | 12.216 s |
| Whole-process footprint peak, matched AB | 2,085,980,408 bytes | 1,532,037,344 bytes |
| RSS peak, separately measured | 368,017,408 bytes | 445,956,096 bytes |

Initial observations are **unpaired**, not pristine cold-cache measurements. PAL4's first completed preparation followed the canceled specialization attempt: 3.316 s prewarm plus 1.996 s load, 5.625 s ASR preparation total. Increasing the one explicitly authorized first-load readiness allowance did not itself accelerate compilation. A subsequent PAL4 fresh process loaded in 3.397 s; its acoustic recognition failed the reference, and it must not be dropped.

Both AB load intervals were nominal thermal state. PAL8 later reached fair state during the longer reply/cleanup; PAL4 remained nominal. Whole-workflow timing and resources are descriptive, not a thermally identical controlled comparison. Peaks come from actual process instrumentation, not file sizes. No qualified profiler trace, cache attribution, wire-byte measurement, installed-total measurement or post-drain +30 s measurement is available. The two retained packages alone total 2,773,350,298 payload bytes, before app/caches/staging.

The evidence does **not** support a recurring multi-minute PAL4 warm-loading regression. Preserve stable identity paths and real preparation receipts; do not reinstall or invalidate caches between arms. Do not skip native validation or weaken cancellation, memory or thermal guards to improve a timing number. A graph/export optimization would require separate review and new model identity; current measurements do not justify re-quantization.

## Exact trial identities

- Checkout baseline: `138ee4a0e001765b5bfec63a226f180724b20eff`, isolated branch `trial/breeze-pal4`, source/research checkpoint. Packet's touched-source guards passed against requested base `c3feba0998c1dd366497114ac7e46845b62cdb7a`.
- HF revision: `3fc162355f3460de6b1e53518a1678cea06464d9`.
- Candidate manifest: `5ed79986de6ae21ca1ea8798e49e38d7c06a3ff9635ac6ef59ade5531cca0f5e`.
- Baseline manifest unchanged: `64021fb776ee2ef4cf02c05b2a9dafde0e0700e9bf7d967b4bc5302558b5fdb4`.
- Shared executable SHA-256: `9af06dd05ac30248e40b8421ab1c108f62b8ef870da4fd8be029391f29359508`.
- WhisperKit: `1e2a163736dfa5a198e637ae44c114e1c6d5cc2d`.
- iPhone18,3 / iOS 27.2 build 24B5084k; Release `MURAL_COREAI_TALK` plus trial-only `MURAL_BREEZE_PAL4_TRIAL`.
- Same installation `20261001-232605-7177`, prepared receipt `20261001-234220-99963`; encoder/decoder CPU+Neural Engine, frontend CPU+GPU, voice M5.
- Approved MELI manifest SHA-256: `11704fc265b19de99b899e668d1b3b3de3d87d1b873c31d3e0406c9811f25cbc`. Original six WAVs, references, boundaries and approval validated. No references passed to recognition; no script conversion in scoring.

## Retained evidence and qualification limits

Original private evidence paths are the isolated worktree's `.build/verification/breeze-pal4/` and `.build/verification/physical-iphone-e2e/`. Before deleting that worktree, evidence was copied to the main checkout's ignored `.build/verification/breeze-pal4-handover-20261002/`, retaining these relative directories. Disposable build/model copies are excluded; package manifest/audit are retained in `model-package-metadata/`. Original absolute paths in receipts remain provenance, not reusable build locations. Nothing private is uploaded. See the [online-agent handover and next-export research prompt](breeze-pal4-online-handover.md).

- `20261001-232947-28053`: failed PAL4 first prewarm; decoder 57.698 s, encoder 211.076 s, cancellation/drain delay retained. Original cleanup failure retained; separate owned recovery confirmed.
- `20261001-235028-45478`: successful PAL4 preparation/acoustic/End/settings cleanup under authorized first-load budget.
- `20261001-235816-90345`: PAL8 first observed current-install load, successful acoustic/cleanup; not compared as warm.
- `20261002-000847-52588` (PAL8) and `20261002-001154-71125` (PAL4): complete matching AB warm runs, distinct PIDs, identical executable and launch policy. Both recognized the frozen English-number sentence correctly. Native tests, playback acknowledgments, End/drain and settings cleanup passed. Human listening remains separate.
- `20261002-001349-83537`: PAL4 warm repeat, lifecycle passed but raw recognition was wrong. Playback completed with nonce acknowledgment before Send. Accuracy failure preserved, not attributed conclusively to compression versus acoustic variability.
- `20261002-001528-92527`: intended PAL8 BA partner interrupted by host limiter process-inspection EPERM; nested test refused its stale admission token before XCTest began. No playback or preparation. Original run/cleanup failure retained. Status `20261002-001638-99653` independently confirms no main/runner processes; owned host processes exited and only this limiter job was recovered. No automatic replay.
- `warm-pair-1-report.json`: supplied comparison tool on the single complete pair only. Export schema defect reproduced then fixed: descriptive source categories mapped to allowed scoring groups, original categories and source paths retained, relative WAV names supplied. Original exports backed up; metadata-only re-export recorded. No native evidence/reference rewriting.

Host checks: packet/model tooling 38 passed; runner integration 4 passed including real scoring-schema validation; existing host runner checks passed. Historical `test_prepare.py` baseline had 4 failures and 1 error across 17 tests before applying changes; obsolete assertions were not restored. Full app/runner build and matching model-free arm checks passed before physical replay. The metadata-only exporter repair is host-tested; a future physical stage needs a current runner fingerprint/check.

Mac CPU/GPU native probe completed all six clips for both packages, preserving empty and inaccurate outputs. Mac Neural Engine probing did not complete within its bound and remains unqualified. Source card claims Apache-2.0 but lacks its own notices and exact prequantization recipe; baseline support/notices retained. Redistribution not qualified.

Remaining gates: additional matched BA/AB pairs, physical Mandarin/mixed-speech and short/silence coverage, representative names/numbers/negation, warm in-process inference, 20-turn/lifecycle, larger corpus, profiler and storage/cache measurements. No automatic accuracy threshold accepted. Existing icon launch still defaults to PAL8; PAL4 requires explicit trial launch for a coordinated manual smoke.

## Recommendation and unblock plan

Keep PAL4 as an opt-in trial. Its warm load is already around three seconds, not minutes, and this sample has lower physical footprint but higher RSS. Do not call it production-ready or claim accuracy parity from one correct sentence.

Before further unattended device work, repair the shared limiter's transient process-inspection failure in its owning project, qualify live-process fail-closed behavior and short-lived descendants, then refresh the model-free runner check. The earlier installed-CLI race patch (backup retained privately) did not resolve every EPERM case; it is not a complete fix and is outside this repository. Resume the incomplete comparison without reinstalling, retain the English failure, add a small mixed-speech smoke, then arrange explicit PAL4 launch in the existing app slot for the user's final listening check.
