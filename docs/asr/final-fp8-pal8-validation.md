# Local-agent prompt: final FP8/PAL8 iPhone validation

Continue `aidynamicsolutions/mural`, branch `mvp`. This is final validation of
**packed-v3 FP8 Core AI encoder + PAL8 Core ML decoder**, not FP8 on both halves.
Keep `prewarm=always`. No PAL4/PAL6, mixed-precision, prewarm-policy, conversion,
model-family or silence/VAD experiment. Do not promote the normal Talk default.

## 1. Integrate the reviewed fixes safely

The remote engineering review started at
`65c96f6df18b99eee3739081d064c74b2b3ba326`. Its connector exposed no GitHub write
actions, so its patch was prepared/tested but **not pushed**. Read
`final-engineering-review-20260919.md` and the supplied `asr-final-review.patch`.

Inspect the existing Mac checkout, branch, worktree and effective configuration.
Fetch `origin/mvp`; record HEAD and remote SHA. Review every intervening commit.
Preserve unrelated local work and all history. Never reset, force-push, delete a
branch, rebase away work, clear caches, uninstall the app, change signing, replace
accepted assets, or edit old private `.build/verification` material.

Review the patch before `git apply --check`. Apply only missing, still-applicable
fixes on the current parent; do not overwrite later work or duplicate fixes that
already landed. The substantive changes are Release-only helper isolation,
restored legacy h18p/fingerprint admission, complete v3 AOT inventory hashing,
truthful measurement labels, regression tests and concise current documentation.
Do not broaden the cleanup. If a conflict cannot be resolved safely, report the
specific blocker rather than proceeding to a misleading phone pass.

## 2. Host and Release gates

Use existing pinned environments, not upgrades or new conversion runs. Run the
repository's applicable host tests, including runtime/legacy/packed-v3 identity,
new final-review checks, product configuration/residency policy, decoder/combined
and PAL6 analysis contracts, cached-load, hybrid/layout, Talk opt-in/default,
bounded asset-verification memory and the core Swift tests. Inspect each entry
point: run its unit/static checks, not its model builder or corpus campaign.
Record commands, failures and skips. Linux synthetic passes are not Apple passes.

Build ordinary Release without the ASR opt-in conditions to verify the missing-
probe compile regression. Then build the selected Release with both
`MURAL_COREAI_TALK` and `MURAL_COREAI_W8`, preserving all other inherited conditions
and the existing local bundle/signing override. Record effective build settings,
source SHA, executable SHA-256 and warnings. Do not regenerate the project or
modify private configuration merely to set these two existing build conditions.

Commit only reviewed task files after successful preflight. Immediately before
commit/publication fetch again, verify the intended parent is current, inspect
new commits and preserve them. Push fast-forward only; re-fetch and verify the
exact remote SHA. A rejected push requires inspection, never force. Record the
actual tested source SHA; a later code change requires a new relevant preflight.

## 3. Verify artifacts and the actual phone path

Rediscover the connected iPhone 17 and its current OS/build/architecture. Do not
reuse a historical device ID or PID. Install in place into the existing test
bundle only after owned work drains; retain user data and model caches.

Independently verify the retained artifacts against current source and manifests:

| Item | Expected identity |
|---|---|
| FP8 full manifest | `73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13` |
| PAL8 support manifest | `430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336` |
| FP8 AOT fingerprint | `c5c7d3264c7256fc50c37e4e4a3471ec69c278397f1887cca65b96a6ee796c65` |
| FP8 AOT native hash | `e7f2444e520608250ec7e8e11d820af9b1b19e3b813021b2e5acd700dee33485` |
| Named function | `mural_v3_encoder_fp8_packed_6ac300f97511fb8879a6` |
| PAL8 directory | `phowhisper-cs-pal8-g16-v1` |

Rehash the complete AOT inventory, native hash, source provenance and PAL8 used
support files with the existing canonical algorithms. Verify retained bytes on
the phone as well as the Mac. Do not rewrite pinned manifests to fix relocated
paths, infer identities from filenames alone, or substitute another artifact.
Confirm h18p, FP16 input `[1,80,3000]`, challenge `[1,40]`, packet `[1,1920040]`,
finite FP16 hidden states `[1,1500,1280]`, and decoder bridge `[1,1280,1,1500]`.
Verify successful runtime response and exact named entrypoint; no `main` fallback.
Use existing live diagnostics plus source/asset checks. Do not run another
multi-arm native probe or repeated historical corpus solely for identity proof.

Launch the selected Release with exactly these ASR-selection arguments:

```text
--coreai-w8-v3-encoder=fp8
--coreai-w8-v3-decoder=pal8
--coreai-w8-v3-prewarm=always
```

Do not include tiny/product/hybrid-corpus/combined trial flags. Use **normal
On-device Talk**, not the speech-recognition laboratory UI. Both build conditions
and both precision flags matter: ordinary Release is eager Core ML, and an
omitted decoder flag selects FP16. Verify the live process/selection on Prepare
and each turn. An icon relaunch may lose arguments; do not credit a wrong-path run.

Create only one new, uniquely named ignored local evidence directory. Preserve
all prior verification material. Use a bounded Mural-only log capture and retain
its owned handle for cleanup; no device-wide archive, private store export or
request to upload recordings, screenshots or full logs.

## 4. One preloaded interview block

Show the complete block below to the user **before the first Record**. Explain
all actions and the feedback form now. Do not insert an agent/browser exchange
between tapping Record and speaking. The user speaks immediately once capture
is visibly active, taps Send, and waits for the reply and Ready before proceeding.
No coaching, expected-word prompt injection or transcript editing. Keep every
first attempt. Allow at most one retry for a genuine capture/protocol interruption,
not repeated attempts until recognition becomes correct.

Use English learning language, Vietnamese support and On-device mode. With all
accepted models and voices already available, disable Wi-Fi and cellular before
Prepare and keep them off for the block. USB diagnostics are allowed, but no
network ASR/tutor fallback. Confirm normal Prepare, greeting and Ready succeed.

### Speech block - same conversation, consecutive turns

| ID | Speak exactly this | Delivery |
|---|---|---|
| F01 | Yesterday I went to the supermarket. | Normal English. |
| F02 | Sau giờ làm, mình đi siêu thị rồi về nấu cơm. | Normal Vietnamese. |
| F03 | Hôm qua I went to the siêu thị, but I forgot my ví. | Natural switching. |
| F04 | I need fifteen, not fifty, because the bus is late. | Normal; preserve number and negation. |
| F05 | Tôi không mua hai chai nước; tôi mua ba chai. | Normal Vietnamese numbers and negation. |
| F06 | Can you explain sự khác nhau giữa borrow and lend? | Natural switching. |
| F07 | Yes. | Quiet but audible, not exaggerated or silent. |
| F08 | No. | Quiet but audible. |
| F09 | Yes. | Normal volume. |
| F10 | No. | Normal volume. |

### Fresh conversation, cancellation and recovery - also preloaded

After F10 and Ready, End normally. When actual workers have drained, start a fresh
conversation. F11: **“This is a new conversation. I have two questions.”** Confirm
normal preparation/greeting, one new user turn, and no old turn leaking into it.

At Ready, F12: **“Please cancel this practice turn.”** Tap Send, then End while the
app is still processing. Confirm End remains responsive and no canceled late
recognition/tutor audio appears. Text genuinely finalized before End may remain;
do not call that a phantom turn. Use timestamps to establish whether End actually
overlapped ASR or only later tutor work. If too late, mark that boundary untested;
one targeted timing retry is permitted, not a cancellation campaign. Never claim
native interruption merely because the UI stopped.

Wait for actual owner/native drain, not an arbitrary sleep used as permission.
Start fresh and say F13: **“I am back. I have two questions.”** Confirm one clean
recovery turn. At Ready, background once and return; follow the normal resume
flow. F14: **“Hôm nay I feel ready to continue.”** Confirm recovery without old
text, late speech, duplicate turns or a stuck owner. Remain offline.

Do not record a silence test. Observe ordinary idle/End transitions for unexpected
turns without changing thresholds or starting VAD work.

### Feedback to collect after the block

For each attempted item record privately: finalized content preserved, formatting
only, wrong content, missing finalization, or interrupted. Record changed numbers,
negation/Yes-No polarity, language spans and `siêu thị` separately. Retain first
attempts and any retry with its reason. Prior `siêu thị` failures are known, not
permission to label a wrong transcript correct. Record whether the user accepts
any remaining known limitation. A new critical content regression is not a pass.

Ask whether Prepare, first turn and later replies felt reasonably responsive;
whether waiting worsened across turns; and whether warmth became uncomfortable.
Separate that human report from objective thermal state and measured intervals.

## 5. Measurement and stop rules

Correlate `asr_trial_capture`, `asr_trial_send`, `asr_trial_final` and
`asr_trial_audio` using actual capture IDs and monotonic timestamps, not completion
order or browser feedback time. Verify the first tutor-audio association is the
reply, not the greeting. Report valid count, first-turn value and warm median/range
for Send-to-final and Send-to-first-tutor-audio. Keep canceled/incomplete attempts
in the ledger but outside successful latency summaries. Missing correlation is
unmeasured, not a reconstructed pass. Do not claim a stable p95 from this block.

Keep encoder function load, native execution, validation/copy, decoder prewarm,
load, prediction/loop, replay/transcription wall time, staged harness interval and
real app timings distinct. Do not add overlapping timers. Phase-specific process
footprint is not process-lifetime RSS, continuous peak or model-only RAM. This is
not a new speedup, energy or sustained-thermal comparison against PAL4/FP16.

Stop on an identity/ABI mismatch, native abort, memory warning, unsafe overlap,
stale/cross-session turn, or failure to drain. Preserve evidence; do not clear the
warning latch, force-kill native work to manufacture recovery, delete caches,
silently fall back or repeatedly relaunch an unchanged native failure. A cache
miss or unavailable asset is a preparation blocker, not authorization to convert
or begin another research campaign. Stop for uncomfortable heat too.

## 6. Sanitized result and closure

Stop every owned log capture. Commit one concise
`docs/asr/fp8-pal8-final-validation-result-YYYYMMDD.md` with tested source/build and
artifact hashes, actual path, build results, completed/failed/interrupted counts,
check outcomes, measurement scopes, warning/abort coverage, human acceptance and
residual risks. Keep raw audio, full logs, screenshots, stores and private content
local. Do not flatten first attempts/retries into an unexplained all-pass result.

Distinguish engineering safety PASS/FAIL/BLOCKED, content findings and human UX
acceptance. Known accepted errors require an explicit qualified result. If a gate
was not observed, say NOT TESTED. Do not claim production-default deployment,
zero cold-cache risk, perfect bilingual accuracy or a long soak.

Before publishing the result, fetch again, inspect later commits, commit atop the
current parent and push fast-forward only. Re-fetch and report the exact ending
remote SHA. End with what passed, what did not, any remaining known limitation,
and whether optimization can close on the selected FP8/PAL8 baseline. Do not
start silence/VAD or any other next project.
