# Core AI decoder diagnostic checkpoint 1

Status: **COMPLETE / execution blocked; stopped at the review gate.**
Date: September 16, 2026. Continuation of [the approved handoff](decoder-diagnostic-handoff.md)
and [startup plan](startup-plan.md).

## Finding

The minimal failure is a **single four-token decoder invocation on fixture 001's
saved encoder tensor**, in a fresh process that never loads the Core AI encoder.
The default dynamic decoder aborts in MPSGraph's ANE execution path whether
length 4 is called first or after length 1. Removing dynamic input dimensions
with a fixed-length-4 export still produces the same native ANE failure.

Cause category: **Core AI converted multi-token decoder execution / native
backend failure on this device and toolchain**, not merely encoder/decoder
co-residency, repeated calls, or a 1-to-4 shape transition. Making dimensions
static is not sufficient. A CPU-only source specialization also traps, this time
inside `BNNSCoreAIDelegate` / `CoreAIRuntime`. That distinct trap does not prove
both backends share one root cause.

The frozen PyTorch decoder executes both prefixes with finite outputs. The
precise failing operator and whether the defect originates in export lowering,
delegate compilation, or runtime execution remain unresolved. Compiler warnings
are leads, not proof of an offending operator. This is an isolated reproducer,
not a fixed recognizer or a claim of an independently established Apple defect.

**No Core AI transcript completed. No 22/22 parity or 12-15 second usable-startup
claim. No KV cache or production integration.**

## Frozen identity and preservation

- Source base: `cedc4a6dc918bb561e763edfd10d66e7c3835165`, branch `mvp`.
- Original uncommitted `App/MuralApp.swift`, `App/VietnameseEnglishRecognizer.swift`
  and `Tools/CoreAI/test_probe_contract.py` retained byte-for-byte in this
  continuation. Starting work is backed up under the local evidence directory.
- Reused the already installed Release `com.kevintruong.mural.dev`, executable
  SHA-256 `f0010befefb1ba75734bfdd0c5b8aa7e21f891cb02b88d790071bf303bb29a1e`.
  The app's installed bundle path/process matched the handoff; the local signed
  executable was rehashed. No new app build or install was needed or performed.
- Rediscovered Kevq, iPhone 17 / iPhone18,3; iOS 27.0 `24A435`; architecture `h18p`.
  Xcode 27.0 `27A5252f`, SDK build `24A5422a`; Mac macOS 26.6.2 `25G83`.
- Frozen model: `/Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/merge-fp16/model`.
  Weights freshly verified by reference and both fixed exports:
  `264f797eebbf19149673112abe6ff00edcdfccb5c357a1108a327d2060d9d82a`.
- Fixture `001.wav`: 90,560 samples, 5.66 seconds, SHA-256
  `e9789f09cf31930239ff5842a1b502103844481d4669fb7e0de77b69966b597f`.
- Exact input tensor: finite FP16 `[1,1500,1280]`, 3,840,000 bytes, SHA-256
  `cdf3c3f5300103ad2b0a23e414b070041d21e7f7c0f77f18ce32bc52824957ae`.
  The successful v2 encode-only run is `025C7AA8-6141-4365-A18E-C196F313233A`.
- All cases verified the same fixture, encoder/support identity and tensor hash.
  The probe additionally verified the decoder NDArray preserves every FP16 bit.
- Python 3.11.11, torch 2.11.0, transformers 4.57.3, numpy 2.4.6,
  safetensors 0.8.0, coreai-core 1.0.0b2, coreai-torch 0.4.1; existing export
  environment, no dependency installation. Reference execution used CPU, FP16,
  four PyTorch threads and offline/local-only model loading.

### Artifact caveat resolved

Copied the phone's existing split AOT directory before further inference and
compared every original file's SHA-256 and size to `.build/coreai/split-aot/`.
**No original file differs or is missing**, including resources, manifests,
metadata and executable graph files. The phone has one additional file per asset:

- Encoder: `main-h18p-delegates/MPSGraph/mpsExecutable.mpsgraphpackage/specialized_model_0.mpsgraph`.
- Decoder: `main-h18p-delegates/MPSGraph/mpsExecutable.mpsgraphpackage/specialized_model_1.mpsgraph`.

The existing Swift fingerprint helper, applied to those retrieved directories,
exactly reproduced the phone's hashes:

- Encoder: `b13ccaf3fa91098a21bc81786843e138ad2e6cde4a9fdcccece6d531b0f9d034`.
- Dynamic AOT decoder: `3bf4e2a792a9cd85ff8eac85912b502d0f221be800c6fba10eadc870d39e7dd7`.
- Support fingerprint remained `2985f62e0f71f375d1a05a7af87798a6d13c8cf2ef0e28d4886dfebb46d89446`
  in every phone case and matches the accepted local support tree using the same
  Swift helper (`support-local-swift-fingerprint.txt`).

Thus different tree contents/serialization must not be mistaken for changed
original AOT weights. The origin of the extra specialized files is not proven;
they were retained. No caches or historical assets were deleted or reset.

The CPU control staged the unchanged source decoder under its own `.aimodel`
name. Its local Swift fingerprint matched the phone:
`fdbbedda9f7184fa279374512d57156ec645b472bfea1e6bbe60464a5c000451`.
The fixed exports used separate `decoder-fixed1` and `decoder-fixed4` names,
leaving the default model selection and accepted support assets intact.

## Bounded device matrix

Every row is one fresh app process; the first row was completed before handoff
and was not repeated. All use the identical saved tensor. Times are seconds.
A dash means no successful call returned, not zero inference time.

| Variant | Cache | Specialize | Load function | Successful calls | Outcome |
| --- | --- | ---: | ---: | --- | --- |
| Dynamic default, 1 then 1 | hit | 0 | 3.371 | 9.202, 0.056 | Finite, repeated rows bit-exact |
| Dynamic default, 4 first | hit | 0 | 3.560 | - | SIGABRT, ANE status `0xe00002bc` / `0x12` |
| Dynamic default, 1 then 4 | hit | 0 | 3.382 | 9.648 for length 1 | Same SIGABRT at length 4 |
| Dynamic source, CPU-only, 4 first | miss | 19.175 | 0.017 | - | SIGTRAP in BNNS Core AI delegate |
| Fixed 1 default, 1 then 1 | miss | 8.108 | 6.404 | 6.155, 0.091 | Finite, repeated rows bit-exact |
| Fixed 4 default, 4 first | miss | 69.683 | 5.414 | - | Same ANE error and SIGABRT |

The fixed controls preserve the original FP16 source and decoder wrapper with
`use_cache=False`. Only input dimensions were fixed. PyTorch graph capture was
bit-exact against direct execution before conversion. Both were compiled only
for `h18p` with default compute and reshape options, then selected with explicit
probe paths. Their local Swift AOT fingerprints match the phone's pre-load
fingerprints:

| Asset | Source bytes | Pre-load AOT fingerprint |
| --- | ---: | --- |
| Fixed 1 | 1,812,133,581 | `e2ca88551e2ce57c73b9aa582c011450ddb925a4037d50e1ca45d7bcbdf84bee` |
| Fixed 4 | 1,812,154,793 | `9120c64b8fc6b7dda9eba9294105b6c91114131c44b1e6cc3347bdbd796852d1` |

`coreai-build` exited successfully and produced both assets, but was **not
warning-free**: fixed 1 logged an ANE offline compilation failure and incompatible
element/I/O-cast messages; fixed 4 logged unsupported `mps.and` / ANE I/O-cast
messages. Phone logs also reported specialization for 6 GPU cores versus 5 on
the device. None of those messages alone establishes actual placement or the
crash's exact cause. No compiler-option sweep or retry followed.

### Run and crash correlation

| Variant | Run ID | PID | Crash file |
| --- | --- | ---: | --- |
| Dynamic 1/1 | `95F6A3D8-E141-4363-B885-16EF2A5444AF` | 41625 | None for this completed run |
| Dynamic 4 | `9A63D528-060F-44D3-B3B8-DC02888033EB` | 41660 | `Mural-2026-09-16-075915.ips` |
| Dynamic 1/4 | `7FA8DBA5-E112-4C23-B3C2-B817E6A9D8D0` | 41697 | `Mural-2026-09-16-080107.ips` |
| CPU 4 | `6E91B737-1FB2-44AF-8B3D-96A03DC111D6` | 41748 | `Mural-2026-09-16-080516.ips` |
| Fixed 1/1 | `9C6F9E03-A60A-4E19-A813-F4143378D024` | 41835 | None for this completed run |
| Fixed 4 | `E6106091-614B-4407-961F-11973FE9A9F9` | 41846 | `Mural-2026-09-16-081704.ips` |

Each failure has a persisted `decoder-before` containing exactly
`[50258,50278,50359,50363]`, with no corresponding output/after event. The ANE
crashes contain `MTLReportFailure` and
`GPU::ANERegionCallOpHandler::encodeAsynchronousWithIOFences`; the CPU trap has
unsymbolicated BNNS/Core AI frames. Raw crash files and hashes are retained
locally, not published.

No new Jetsam entry appeared in before/final snapshots. Thermal samples were
nominal (0). The dynamic repeated-one run sampled about 1.912 GB footprint and
3.488 GB process-lifetime RSS peak. Fixed 1 sampled a maximum 0.518 GB footprint
and 3.465 GB RSS peak; fixed 4 reached 1.887 GB sampled footprint and 3.375 GB RSS
peak before its call. These boundary samples are not peak device/driver-memory
measurements, a thermal soak, or a coexistence test with tutor/TTS.

## Numerical reference, not transcript parity

`Tools/CoreAI/compare_decoder_logits.py` uses the saved phone tensor directly.
Loading with the original exporter's implicit attention selection resolves to
**SDPA** in the frozen environment; an additional eager reference records the
accepted Python benchmark's attention choice. The original historical export
report did not record its resolved attention; this is a reproduction of that
loading configuration, not retroactive instrumentation of it.

All PyTorch output rows for both prefixes are finite. At length 1, all successful
phone rows and both references have top IDs:
`[50278,50259,50294,50352,50282]`. The accepted WhisperKit baseline for fixture 001
also records language `vi` and text `Yesterday I went to the supermarket.`
Thus the apparently surprising Vietnamese language token is consistent with
that accepted behavior, not by itself an error.

| Length-1 comparison | Maximum absolute error | Mean absolute error | RMS error | Winner margin |
| --- | ---: | ---: | ---: | ---: |
| Dynamic phone vs SDPA | 0.0234375 | 0.00349694 | 0.00424036 | 8.890625 |
| Dynamic phone vs eager | 0.021484375 | 0.00309002 | 0.00383129 | 8.890625 |
| Fixed phone vs SDPA | 0.0087890625 | 0.00273791 | 0.00307629 | 8.8984375 |
| Fixed phone vs eager | 0.0107421875 | 0.00339082 | 0.00378799 | 8.8984375 |

Repeated phone rows are bit-exact within each variant; dynamic length-1 output
also matches across the 1/1 and 1/4 processes. Neither variant is bit-exact to
PyTorch. No numerical tolerance was invented after observing these differences.
Both references have length-1 winner margin 8.890625.

For the four-token prefix, both PyTorch references have top IDs
`[56,6054,5542,19765,88]`, values
`[17.03125,15.5859375,15.046875,12.328125,10.921875]`, winner margin 1.4453125.
SDPA versus eager maximum absolute difference is 0.00390625 at length 1 and
0.0126953125 at length 4. Winners and top-five order agree. **There is no phone
length-4 row to compare.** Successful references do not validate missing outputs.

The accepted 80-mel frontend and tokenizer were unchanged. This reference
isolates decoder execution; it does not prove encoder numerical parity, greedy
multi-token sequence parity, or detokenization parity.

## Decoding-contract audit

Inspected the actual clean pinned WhisperKit checkout at
`1e2a163736dfa5a198e637ae44c114e1c6d5cc2d`:

- `TextDecoder.swift:176-195,437-460`: language detection uses SOT and only language
  candidates; ordinary prefill is SOT, detected language, transcribe, no-timestamps.
- `TextDecoder.swift:872-915`: suppress blank/EOS at the first sampled token;
  configured suppression excludes IDs at or above `specialTokenBegin`.
- `TextDecoder.swift:576-577,680-698`, `Models.swift:1340`: 224-token internal
  context; stop before appending once current tokens reach 223. The probe's
  lexical append bound matches. WhisperKit can perform one final prediction at
  that boundary; probe `tokenLimit` is not a claim of identical EOS metadata there.
- `LocalConversationEngine.swift:562-575`: PhoWhisper uses greedy/no timestamps,
  no temperature fallback, and disables threshold-based turn dropping. Existing
  suppression, accent-sensitive normalization and known recognition errors stay.

The inherited probe changes correct its old special-token suppression, finite
argmax handling and lexical token bound. The bounded controls bypass generation;
these source checks therefore remain distinct from a complete decoding parity
check. Corpus and long-turn stopping verification are still gated.

## Reproducer and evidence

The minimal isolated failing invocation is documented here for review, **not an
authorization to repeat an unchanged crash**:

```sh
xcrun devicectl device process launch --device "$DEVICE_UDID" --terminate-existing \
  com.kevintruong.mural.dev --coreai-asr-probe --coreai-asr-auto \
  --coreai-fixture=001.wav --coreai-decode-only --coreai-decoder-case=four
```

Required inputs are the original split AOT pair, accepted support directory,
fixture 001 and its matching v2 checkpoint. No encoder inference occurs in this
process. [Tool documentation](../../Tools/CoreAI/README.md) covers unique report
retrieval, CPU/fixed controls and the runnable numerical comparison.

Local evidence root: `.build/verification/coreai-decoder-diagnostic/`.
Continuation evidence: its `continuation/` subdirectory:

- `starting-worktree/`, `artifact-file-comparison.json`, `device-assets-before/`,
  `device-assets-swift-fingerprints.txt`: preservation and original AOT identity.
- `four-run/`, `one-four-run/`, `cpu-four-run/`, `fixed1-run/`, `fixed4-run/`:
  fresh per-run reports, flushed events and available raw logits.
- Corresponding launch JSON/logs, bounded Mural-only runtime logs, observation
  records and capture cleanup files. `four-observation.json`'s `launchUTC` was
  recorded at observation end; use `four-launch.json` for launch timing.
- `crash-summary.json`, four named IPS files, before/final crash inventories.
- `pytorch-reference/comparison.json`, reference `.f32` rows,
  `fixed-reference-comparison.json`: raw numerical comparisons and absent outputs.
- `export-fixed*.log`, `compile-fixed*.log`, `stage-fixed*.log`,
  `fixed-source-files.json`, `fixed-aot-files.json`, fixed AOT fingerprints.
- Fixed source/AOT assets and export metadata:
  `.build/coreai/decoder-diagnostic-fixed/{export,aot}/`.

Checks passed: probe-contract helper, accepted mel-reader helper, comparison
self-test, Python syntax, both fixed exports' full-output PyTorch equality checks,
and whitespace validation. The earlier successful Release build/install remains
the matching app build; no Swift code changed in this continuation. Export logs
retain the existing `torch_dtype` and dependency TreeSpec deprecation warnings.

All owned Mural log captures were stopped. No Mural process remains running.
No full-device log archive, learning-data change, uninstall, cache clearing,
weight/precision change, cloud request, OS/toolchain update, subagent, commit or
publication was performed. Source CPU/fixed diagnostic assets and generated
specializations were retained; normal Talk still selects WhisperKit/Core ML.

## Review gate

Checkpoint 1's deliverable is met by the isolated failing invocation and the
backend-failure category above. **The ASR startup problem is not solved.**
Do not keep retrying full-prefix variants or assume fixed shapes alone repair it.

Review this reproducer before choosing further work. A separately approved
fixed-step candidate can be validated directly against the accepted reference,
first with teacher-forced steps and then 22/22 normalized transcripts, as allowed
by the plan's blocked-full-prefix alternative. That is a new gate decision, not
work performed or approved automatically here. Toolchain changes or external bug
submission also require review. Production integration remains gated on quality,
actual startup/first-transcript latency, memory and lifecycle acceptance.
