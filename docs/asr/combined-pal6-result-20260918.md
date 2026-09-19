# Combined PAL6 qualification - REAL sanitized result

Date: 2026-09-18
Source commit under test: `374a7b3abecc87c9f5b78959f3ab1e48084e18ae`
Source local-diff hash: `a484cdfa5744e2f9a587c2e2ee2ab3a3d1ae3ee1e69d4414037b684cee4e40cc` (SHA256 of the recorded implementation-file hash list)
Release executable SHA256: `91ff230218c2aa87171d52a80ce49fafe2f626f43194316ef2f550876ee34f6f`
Status: native-only. Corpus, live, lifecycle, and prewarm-policy gates were not run.

Device: iPhone 17 (`iPhone18,3`), iOS 27.2 (`24B5084k`), h18p. Xcode 27.0 (`27A5252f`), Swift 6.4. Build was Release with `MURAL_COREAI_TALK` and `MURAL_COREAI_W8`, using the existing `com.kevintruong.mural.dev` bundle override.

## Exact artifact identity

All artifacts below were existing local files. Static admission rehashed the complete encoder bundles and support inventories, ran Core AI AOT inspection, and passed. Device manifest hashes and encoder source/AOT `main.hash` values matched the admitted identities. No encoder was rebuilt, no accepted asset was overwritten, and no cache was deleted.

| arm | manifest | source fingerprint / bytes / native hash | AOT fingerprint / bytes / native hash | used decoder / support |
|---|---|---|---|---|
| A: FP8/PAL8 | FP8 `73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13` | `df7f666667918bbd21b874ff63c5009f970675b1d9ad5fd7336517803a1ec720` / 640,125,893 / `b9754ecc845a0c5da63234a289a83a31593c618a198daf938e230cfdc450bd89` | `c5c7d3264c7256fc50c37e4e4a3471ec69c278397f1887cca65b96a6ee796c65` / 640,483,375 / `e7f2444e520608250ec7e8e11d820af9b1b19e3b813021b2e5acd700dee33485` | PAL8 support `430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336`; support 1,655,763,645 B; used TextDecoder 991,764,466 B |
| B: FP8/PAL6 | same FP8 encoder | same FP8 source and AOT | same FP8 source and AOT | PAL6 support `13f9bbd0d08bf0b6a111f8415ddffad158f8d1fb4e4014c17585066e37fd23bb`; support 1,265,613,461 B; used TextDecoder 769,115,313 B |
| C: PAL6/PAL6 | PAL6 `b3437340b110c14349cd3f12ae0955adb8254fdc277e263907eaa3d96e651966` | `d21cb37056202c34b18591609a10120de675a5dcf708925a7d03435892ccca7a` / 483,765,816 / `0624c87450b8bb98f615cac759a46f3796f570c95fe171d8a29e6a7167e91348` | `661fedd52988829fd1f1fe7df35eebab80990a6fdfc0f69118d62edf06fb1812` / 1,273,967,904 / `fabe774c6ce699e317945479355d434e3a4af47610459875d53f9f0b3f0a3b0b` | same PAL6 support as B |

Runtime encoder entrypoints were `mural_v3_encoder_fp8_packed_6ac300f97511fb8879a6` for A/B and `mural_v3_encoder_pal6_packed_a520a05387bc6baf4af3` for C. FP8 uses challenge `[1,40]`; PAL6 uses `[1,56]`. All native runs reported `cacheHit=true`, specialization `0`, the expected named function, h18p, and the retained-cache/new-process condition.

The relevant logical deployed component sums are A `1,632,247,841 B`, B `1,409,598,688 B`, and C `2,043,083,217 B`. C is `+410,835,376 B` (`+25.17%`) versus A and `+633,484,529 B` (`+44.94%`) versus B. These are AOT plus used TextDecoder bytes, not RAM or speed.

## Native fixture-001 gate

Each arm ran in a separate fresh process with `--coreai-hybrid-product-gate`, `--coreai-product-mode=staged-gpu`, `--coreai-product-turns=2`, the explicit encoder/decoder flags, and `--coreai-w8-v3-prewarm=always`. The explicit sequence flag was omitted, so both turns used the existing default fixture `001.wav`. C additionally used `--coreai-w8-v3-combined=pal6-pal6`.

| arm | run ID | PID | exact transcript agreement | repeated hidden hash | terminal / state / errors / warnings |
|---|---|---:|---|---|---|
| A | `F37BFAA6-8150-41E7-946A-A8BDFE24A6E7` | 8928 | 2/2, `Yesterday I went to the supermarket.` | `102cd6c463d55f4eefa8e16b3c9012d2171665e652517ad558f25a39fd74fdba` | true / idle / 0 / 0 |
| B | `404BD333-45B5-437E-B847-5BF3AECC554B` | 8939 | 2/2, exact | `102cd6c463d55f4eefa8e16b3c9012d2171665e652517ad558f25a39fd74fdba` | true / idle / 0 / 0 |
| C | `B1782B86-D56C-409B-922A-DBE3B83B7AD6` | 8941 | 2/2, exact | `b4a242b303d7bb407692867adb8171efe8e992cafcbc539cfc136ca07cb3e6d1` | true / idle / 0 / 0 |

A and B produced the same hidden hash for the fixed FP8 encoder. C's hidden hash differed from A/B as expected for the changed encoder and repeated exactly within C. D was not run, so no C-versus-D comparison is claimed.

The FP8 arms verified packet element count `[1,1920040]`; C verified `[1,1920056]`. All arms produced 1,920,000 hidden elements with the expected decoder handoff `[1,1500,1280]` to `[1,1280,1,1500]`. Challenge seeds 1 and 2 were recorded for the two turns. Thermal state was 0 before and after each turn. No crash, memory warning, native error, fallback to `main`, or ownership/drain failure occurred.

The following values are means across the two native turns. Percentages are C versus the corresponding arm's mean. The staged timer starts after audio read and is not UI Send-to-final.

| metric / units | A | B | C | C-A | C-B |
|---|---:|---:|---:|---:|---:|
| AOT + used decoder logical bytes | 1,632,247,841 | 1,409,598,688 | 2,043,083,217 | +25.17% | +44.94% |
| native encoder seconds | 0.5131 | 0.5067 | 0.4405 | -14.15% | -13.07% |
| encoder function load seconds | 1.0123 | 1.1030 | 1.8525 | +83.00% | +67.95% |
| validation/copy seconds | 0.0099 | 0.0064 | 0.0112 | +13.82% | +75.36% |
| decoder prewarm / load seconds | 8.7143 / 0.1079 | 10.0668 / 0.1069 | 0.3997 / 0.1011 | -95.41% / -6.34% | -96.03% / -5.44% |
| decoder seconds | 0.8426 | 0.7942 | 0.7770 | -7.79% | -2.17% |
| full staged harness seconds | 11.5725 | 12.9360 | 3.9275 | -66.06% | -69.64% |
| encoder-response footprint B | 423,954,884 | 423,684,572 | 242,076,628 | -42.90% | -42.86% |
| post-release footprint B | 200,001,496 | 199,952,368 | 174,180,276 | -12.91% | -12.89% |
| decoder-loaded footprint B | 1,227,589,652 | 986,843,180 | 1,005,750,232 | -18.07% | +1.92% |
| decoder text-end footprint B | 1,286,113,444 | 1,061,251,284 | 1,035,094,168 | -19.52% | -2.46% |
| process-lifetime RSS peak B | 1,356,152,832 | 1,346,371,584 | 2,583,658,496 | +90.51% | +91.90% |
| warnings / errors | 0 / 0 | 0 / 0 | 0 / 0 | - | - |

A/B first-turn prewarm was 16.994 / 19.677 seconds while C was 0.555 seconds. The full staged comparison is therefore cache and schedule sensitive and is not treated as a C speed result. C's native encoder interval was lower, but its function load was materially slower than B and its lifetime RSS was about 1.24 GB higher. The only incremental decoder-phase differences versus B were small and mixed: loaded footprint was 1.92% higher, text-end footprint 2.46% lower, and decoder time 2.17% lower. This does not establish a worthwhile incremental benefit beyond B.

## Paired corpus, real app, human feedback, and lifecycle

Not run. The native C-versus-B gate was safe, but it showed no worthwhile incremental benefit and the handoff directs stopping rather than spending a long corpus/live exercise to obtain a favorable number. No recording was started, so no interview form was opened; the complete batched interview requirement was not bypassed. No prewarm `once` comparison was run because the precision result was not accepted for a follow-on policy experiment.

## Failures, exclusions, uncertainty, and local evidence

Attempt ledger:

| phase | error or observation | hypothesis / changed variable | result / next action |
|---|---|---|---|
| remote/tooling setup | `git fetch origin mvp` succeeded; HEAD and `origin/mvp` both remained `374a7b3`; starting worktree was clean | none | preserved history and local diff; continued |
| tooling patch | supplied patch applied after `git apply --check`; 70 combined and decoder host tests passed after the runtime patch | none | continued |
| guarded runtime patch | generator accepted both complete App blob hashes and produced a two-file patch; patch review showed only explicit pair policy, native gate guard, and ID-correlated first-audio logging | none | applied and built; defaults, VAD, silence, caches, warning latches, and drain behavior remained unchanged |
| static admission | exact FP8/PAL6 encoder and PAL8/PAL6 support identities passed; AOT inspection passed | none | continued without conversion or staging replacement |
| identity test | system Python lacked `torch` (`ModuleNotFoundError`) | use the retained matching conversion virtual environment | `/Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/.venv/bin/python` passed all 8 runtime identity tests; no code or artifact change |
| native A/B/C | all three two-turn gates completed, exact, terminal, idle, drained, warning-free | none | C was safe but stopped as insufficient incremental benefit versus B |

The initial `test_w8_identity.py` run passed 9 tests with 1 environment skip. No unchanged native crash was relaunched. No failure, warning, or memory sample was averaged away. The three bounded Mural-only captures were stopped after their owned processes drained. Private recordings, app stores, screenshots, and full device evidence remain local under the ignored evidence root.

Key local evidence:

- `.build/verification/combined-pal6-20260918-local/admission/admission.json` SHA256 `4e65ca2247bfec82bd94a2473aa88d2e894302f66edf5872d4bf95a62c45a969`
- `.build/verification/combined-pal6-20260918-local/runtime.patch` SHA256 `f3b3f7c0157fe8938c40e9e6e3f97e5ce67ca537913e80e73109733b9dcd9cf2`
- `.build/verification/combined-pal6-20260918-local/native-C-vs-A.json` SHA256 `4a32c3e78531bf804db09f75f82ea1b511f3c3813ed0e0b73948cd19ada36c1c`
- `.build/verification/combined-pal6-20260918-local/native-C-vs-B.json` SHA256 `9a0df230e8ffd6d8ec54c9b26fc2e62e924ad2d5af21d5aa90e603727131d586`
- `.build/verification/combined-pal6-20260918-local/executable.sha256` records `91ff230218c2aa87171d52a80ce49fafe2f626f43194316ef2f550876ee34f6f`

## Disposition

**C provides insufficient incremental benefit. B remains the better lab candidate.** C passed the bounded native safety and quality gate, but compared with B it had slower encoder function loading, approximately 91.90% higher process-lifetime RSS, no meaningful decoder-phase saving, and a 44.94% larger AOT-plus-used-decoder component sum. C is not promoted or retained as a recommended lab pair. Normal/default Talk, default prewarm, silence/VAD, caches, warning latches, accepted artifacts, and native-drain behavior are unchanged.

Final branch head: this report is included in the local commit at `HEAD`; its exact value is checked before the fast-forward publication. Publication will be a normal fast-forward push only; no force push or history rewrite.
