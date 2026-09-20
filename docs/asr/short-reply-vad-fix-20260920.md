# Short-reply VAD fix - 2026-09-20

## Disposition

**USER-APPROVED, SHARED POLICY FIX; FOCUSED PHONE VERIFICATION PASSED.** This supersedes the no-policy-change disposition in the [initial investigation](short-reply-vad-investigation-20260920.md). The user explicitly approved changing the gate after reviewing matched probability results, then approved local `mvp` integration if the changed gate passed the final phone check. No push was authorized.

The old rule rejected 3/9 human-labeled spoken replies in the new, untuned comparison set. The proposed rule accepted those same three probability sequences while retaining rejection of all five new nonspeech controls and the earlier hard-noise regressions. After implementation, the changed gate accepted four fresh normal/quiet Yes/No replies and rejected four fresh noise controls on the physical phone. Eight final audio fixtures were retained with explicit consent and verified byte-for-byte at the PCM level.

This fixes the demonstrated **VAD policy rejection**, not an AED recognition or formatting error. It is not a guarantee for every short utterance, speaker, microphone or noise source. **No ASR, tutor or TTS ran in qualification.** FireRed's separate memory STOP remains unresolved. The final four saved speech recordings also satisfy the old aggregate rule; they confirm operation of the deployed gate, not matched acoustic rescue of the missing earlier WAVs. The matched rescue evidence is the old/new policy comparison on identical real logged probabilities, backed by failing-before/passing-after shared-core tests.

## Smallest shared change

`Core/SpeechPresencePolicy.swift` retains the existing three-strongest-window mean threshold of `0.85`. It adds one alternative for complete valid evidence:

- Two **consecutive** windows, each containing **4,096 actual samples**, must each have probability `>= 0.999`.
- One isolated peak does not qualify. Two separated peaks do not qualify. A padded partial window cannot supply either member of the pair.
- `0.999` is a detector-score cutoff, not a calibrated claim of 99.9% recognition accuracy.
- The existing acceptance path remains intact. This is not the old any-window gate, a globally lowered aggregate threshold, a recording-length bypass, or another detector.

The candidate definition was frozen in private `plan.json` before the 14 follow-up recordings. It fits the earlier examples, so those earlier examples are not held-out validation. The 14 new, individually labeled recordings were the untuned follow-up; this remains a small same-speaker/device convenience set. Default promotion was approved only after presenting its measured speech/noise tradeoff and limitations.

The original `.30` active-window threshold, default gate mode, off/observe behavior, fail-open evidence rules, per-recording recurrent state and cancellation/draining ownership remain unchanged. PhoWhisper retains 512 ms pre-roll, 1,024 ms hangover and 2,048 ms minimum removed gap. FireRed and Breeze still pass full accepted PCM, with no trimming. Their actors were reviewed and are unchanged; both use the same shared `Evidence.rejects(in:)` decision. No ASR default or transcript normalization changed.

Two full windows imply a remaining capture-geometry limitation: less than 8,192 captured samples cannot use this exception. This is not a measured 512 ms spoken-word minimum. Surrounding quiet, window alignment and recurrent probabilities differ from word duration.

## Evidence and matched comparison

Original FireRed recordings remain unavailable. Their logs prove rejection before native decode, not complete acoustic cause. No retrospective timestamp labels, lost audio or probability traces were invented. The initial report retains those exact limits and identities.

Each cell below is false rejections / labeled speech; false acceptances / labeled nonspeech. Evaluation uses the actual compiled shared Core policy on the same logged probability sequences, with the old arithmetic rule evaluated alongside it. Probabilities were logged to six decimals. No new model inference or transcript comparison is implied by this replay.

| Evidence set | Old aggregate rule | Fixed rule |
|---|---|---|
| Initial September 20 labeled set, used to develop candidate | 2/12; 0/5 | 0/12; 0/5 |
| Retained historical quiet-speech/noise regressions | 0/2; 0/3 | 0/2; 0/3 |
| New 14-recording untuned comparison | **3/9; 0/5** | **0/9; 0/5** |
| Final changed-gate phone check, eight new recordings | 0/4; 0/4 | 0/4; 0/4 |

The replay covers 47 complete sequences, of which 44 have retained human labels. Two original unlabeled submissions and one historical unverified speech-block row are excluded from accuracy denominators. The original cancelled capture has no probability sequence. Do not pool these selected sets into a population accuracy claim.

The old breathing/movement peaks `[0.990723, 0.993164, 0.424805]` remain rejected. Lowering the old scalar cutoff enough to rescue the original failed Yes would accept that noise; the new rule instead requires a stricter adjacent full-window pair. A fresh throat-clear with peak `0.996582` was also rejected. This evidence supports the focused exception, not immunity to future high-scoring nonspeech.

### New untuned comparison

All 14 completed captures had complete evidence, exact source -> converter body plus tail -> VAD sample accounting, and human labels recorded one card at a time. Durations below are capture lengths, not voiced duration. No PCM was retained during this phase, in accordance with the user's choice at that time.

| Class | Turn UUID | Samples / captured s | Old score | Old / fixed gate | Probability SHA-256 prefix |
|---|---|---:|---:|---|---|
| Normal Yes | `CDCC5E1F-A3E4-4415-9414-949A3BAC9B5F` | 28,800 / 1.8 | 0.997396 | Accept / Accept | `93dc557f09c7044a` |
| Normal No | `72A2B33E-E2EC-4C70-B319-2FECC429A6BA` | 36,800 / 2.3 | 0.744629 | Reject / Accept | `7c4af69cd1dbd728` |
| Breathing/handling | `8F20B597-D7EF-4C91-9DFF-4EA82D2EACB0` | 99,200 / 6.2 | 0.144206 | Reject / Reject | `641a2570936fa1cf` |
| Fan | `5604F2EF-C53F-4EBF-ACAC-399275B6A6B5` | 96,000 / 6.0 | 0.083984 | Reject / Reject | `4cda932bdda9f93d` |
| Quiet Yes | `DE7FD4E0-09B3-4170-BC93-332DBFF821AB` | 43,200 / 2.7 | 0.751302 | Reject / Accept | `234ba918d52128ef` |
| Quiet No | `42BA5229-8402-4F31-92AA-AD4455B710FA` | 36,800 / 2.3 | 0.770833 | Reject / Accept | `2bb8bb47da43c669` |
| Throat clear | `559D9CD5-E144-426A-B95F-A1360D88BD8A` | 43,200 / 2.7 | 0.653971 | Reject / Reject | `e97df1de1f9362f8` |
| Room silence | `BD5D12B5-4D19-49B2-9958-12DFB1C07844` | 59,200 / 3.7 | 0.046875 | Reject / Reject | `937563daddddb09d` |
| Short negation | `83D54330-2A28-4FA1-B218-296F0D2BE62F` | 36,800 / 2.3 | 1.000000 | Accept / Accept | `6fea46643fbb64b2` |
| Short number | `94C8E6FA-768F-41FE-888B-902754AA3C8F` | 32,000 / 2.0 | 1.000000 | Accept / Accept | `927bd58d1190bb3a` |
| Record-boundary Yes | `1543228E-8A3C-4098-9F31-29DA933EE66D` | 33,600 / 2.1 | 0.967448 | Accept / Accept | `643482612ef4c01f` |
| Send-boundary No | `5421451B-1B51-4380-ABDF-D0A1103C2012` | 27,200 / 1.7 | 0.959798 | Accept / Accept | `f0d7dd19a684b524` |
| Longer reply | `670770D0-C2B3-4FFA-B9F4-260D626C5E57` | 75,200 / 4.7 | 1.000000 | Accept / Accept | `73c0c925af348731` |
| Quiet background noise | `D2C76449-24DA-4A6C-AAE8-EA015CB1C7EE` | 70,400 / 4.4 | 0.050781 | Reject / Reject | `b87588c85f7f0b57` |

The rescued normal No, quiet Yes and quiet No had old scores `0.744629`, `0.751302` and `0.770833`, respectively. Each had two neighboring full windows at `1.0`. The actual probability sequences are regression tests, not synthetic substitutes. The new test failed three assertions before the shared policy correction and passed afterward.

### Final changed-gate phone check

The user then explicitly approved the default change and a final phone check. The app was rebuilt, installed in place and launched in VAD-only mode. The displayed gate result now came from the changed Core decision, not merely a host-side candidate calculation. Every final turn matched the frozen rule and the human-observed result.

| Class | Turn UUID | Samples / captured s | Fixed gate | WAV SHA-256 prefix | PCM SHA-256 prefix |
|---|---|---:|---|---|---|
| Normal Yes | `DBADB81D-6B3D-4CF2-9C3A-732DBB79EE45` | 33,600 / 2.1 | Accept | `209936aec8e00421` | `3ef85ef89a034e2b` |
| Normal No | `94937738-70A5-4E1E-88FA-FC446F3D7B92` | 28,800 / 1.8 | Accept | `116a3ea6cb5a4055` | `9d1b7902ef6006a6` |
| Quiet Yes | `6C9CD906-853A-4759-B8B3-3C5F9460FC29` | 48,000 / 3.0 | Accept | `c0322f4db041f505` | `c7b0e5b7834a8f0f` |
| Quiet No | `26D5A0AA-4A09-4DC4-9124-6EA6574BEF53` | 38,400 / 2.4 | Accept | `d279ed709fac94ef` | `3b313b951c443102` |
| Room silence | `60CEDCD8-6E50-4887-A931-43F15CDA37E2` | 62,400 / 3.9 | Reject | `5b24b8043ac0722b` | `a512f22073c19f57` |
| Breathing/handling | `F9539F6D-3AE5-440D-BD5E-C444E039BA78` | 83,200 / 5.2 | Reject | `a84e7c47b28d3af3` | `4dfff9a09d463dae` |
| Fan | `909F5BB1-27EC-4543-84AA-BB97645F9BFE` | 75,200 / 4.7 | Reject | `88be88cb0a1ad593` | `c7bd771e86a6ed19` |
| Throat clear | `4BC3E88A-37B2-4469-A8D2-524E14DCACD7` | 40,000 / 2.5 | Reject | `0d1c6da2faa1e12c` | `ae675bc7beb5d62f` |

Hash prefixes in the turn tables are the first 16 hex characters; the private manifests below retain complete SHA-256 values.

No warning, native recognition, tutor or TTS event was recorded in the bounded comparison/final captures. The first log process exited with a device disconnect while idle after the comparison. A fresh scoped capture was established before final testing; the intervening idle interval is not continuous log coverage. One launch was blocked by the locked phone; it succeeded after the user unlocked it. No recording was assigned a label from that gap.

## Private recordings and future use

The user initially declined PCM retention. Therefore neither the earlier investigation audio nor the 14 comparison recordings can be recovered. Their labels, sample counts and probability fixtures remain available. Do not claim those probabilities can reconstruct a waveform.

Before the final check, the user explicitly requested future-reusable recordings, approved the disclosed phone/Mac locations, and allowed more than six if needed. The final set was bounded to **eight submitted recordings**, not continuous capture:

- Phone: `Documents/VADQualification/D3CF8C44-793E-4D7B-AD4A-0811B273A541/` inside Mural's private container.
- Mac: `.build/verification/short-reply-vad-followup-20260920-084826/final-fixtures/` in the main `mural` checkout. All private verification evidence was moved here and hash-verified before removing the investigation worktree at the user's request.
- Eight WAVs, 1,671,168 file bytes in total; 16 kHz mono Float32, full converted PCM before rejection or trimming.
- Manifest contains per-file labels, sample counts, file/PCM SHA-256 and probability-fixture hashes. Copies remain private until the user requests deletion. No agent upload, commit or push of audio was performed. Preserve this private evidence directory when cleaning build caches; the temporary investigation worktree is no longer needed.

All eight WAVs were decoded on the host with AVAudioFile, draining partial reads. Each reconstructed PCM hash exactly matches the hash logged from the phone's full input array, and all counts match. Independent WAV data-chunk inspection also matched. A single `AVAudioFile.read(into:)` can return fewer frames than capacity; the verifier was corrected to keep reading. This was a verifier assumption, not missing samples in the saved WAVs. Native writer tests now cover a larger file and partial-read drain.

The recorder is compiled only with `MURAL_VAD_PROBE`, requires `--asr-vad-only` and an explicit `--asr-vad-fixtures=<UUID>` launch argument, and caps each private session at eight files of at most 30 seconds. It validates finite samples, refuses overwrites, checks cancellation, and removes only its own unfinished temporary file on failure. Ordinary Release contains no fixture writer. The UI clearly indicates whether retention is on; it no longer describes VAD-only output as a transcript.

Do not run the existing full-ASR replay facility merely to inspect these recordings: that loads a recognizer and remains subject to the separate memory gate. Same-byte VAD-only replay is now possible with these files, but no new acoustic model replay or matched ASR transcript result is claimed here.

## Converter correction and downstream review

The separate `LocalConversationEngine.convert` correction described in the initial report is included. It preserves an input packet when AVAudioConverter first fills the output using previously buffered samples, and drains output/tail until input runs dry or EOF. It is not the cause of the logged short-reply rejections with intact sample counts.

Its exact native Mac edge case fails before/passes after: 24,576 source frames in 4,800-frame packets previously produced 8,000 rather than 8,192 output samples. Thirty-two synthetic packetizations pass count/sample parity. The corrected converter was also exercised by all 22 follow-up phone captures with exact counts; the specific 576-frame remainder edge case was not independently reproduced on the phone.

Explicit cross-caller review covers Nemotron's arbitrary-size streaming sample buffer and the accumulated PCM paths for Parakeet, Whisper/PhoWhisper, Breeze and FireRed. The shared gate change applies to PhoWhisper, Breeze and FireRed without actor changes or backend substitution.

Source contracts and existing tests verify that empty local turns return before saving a user fragment, replying, TTS or automatic meaning, and that publication checks cancellation/generation after work drains. The initial paired Stop-during-capture check had no late result. New native fixture-writer cancellation tests pass. This is **not** a fresh normal-Talk persistence/tutor/TTS E2E pass or in-flight AED cancellation test. Those inference paths were not run because of the safety boundary.

## Artifact/build identity and verification

- Base: current local `mvp` `185696849b35fd6b70474f8929232b3a88cb2ec1`, with isolated branch `short-reply-vad-investigation`. No reset to an older remote head, fetch, signing change, asset regeneration, model/cache/store deletion or user-change overwrite.
- Phone: iPhone 17 / `iPhone18,3`, iOS 27.2 (`24B5084k`); input 48 kHz mono, converted to 16 kHz mono. Xcode 27.0 (`27A5252f`), iOS SDK 27.0, signed Release.
- FluidAudio 0.15.7, commit `41540ea237350afe5117a082b5c28eda642d0612`.
- Used Silero cache was copied read-only again before this session: `silero-vad-unified-256ms-v6.2.1.mlmodelc`, five files / 1,063,425 bytes. Inventory SHA-256 `11924cda2c126851cff8f07353dfe39edc30cfd183965ce0bc2a3a2845647024`. The direct loader does not repair/delete/download assets. Package revision alone is not a model-byte pin.

| Executable | SHA-256 | Use |
|---|---|---|
| Follow-up old-gate comparison, corrected converter | `20843e1097e82527f138faa57370327ebaabf7b3f61af8b1279d9ee03cc595b1` | Phone, 14 labeled recordings |
| Fixed gate + explicit private fixtures | `b12045a90e71653d3553848180e017319afda8859df9225d58e211a0f9714861` | Phone, eight labeled recordings |
| Ordinary Release with fixed gate | `15b541df9361fa9ab2c7ff77f9501bfbd06a1e6987312c9007f23f8c8729f036` | Restored in place and launched without arguments |
| Affected FireRed opt-in Release | `65aa0008a8fc9b8192192e293a43778cd56a1b8873eb800f489ddfdbfdef3319` | Built only, never installed/run |

Final source hashes:

| File | SHA-256 |
|---|---|
| `Core/SpeechPresencePolicy.swift` | `4951aa87c38f32bae8c9d6a2dd307c6d6ea0f46f730bd0606ec393e765d146db` |
| `App/LocalConversationEngine.swift` | `029900f066dc84956db9670c1a340f80fd03712fe27c7478490beb290f584b6c` |
| `App/RootView.swift` | `703612095f7155711b055d0e63e018b74ed56ae5d39046d143a26b83f07075ef` |
| `App/MuralApp.swift` | `36a345825922ec69bec0c1202acb55ce318618c8fbdc3817d0d071d6d07d0ecf` |

| Check | Result |
|---|---|
| `swift test --filter SpeechPresencePolicyTests` | 26 passed |
| `swift test` | 91 passed |
| `python3 Tools/CoreAI/test_asr_final_review.py` | 16 passed; includes native converter/writer and source contracts |
| Chinese ASR unittest discovery | 47 passed |
| Actual shared-Core probability replay | 47 complete sequences; 44 labeled; denominators above |
| Ordinary, VAD-only and FireRed opt-in Release | All built successfully |
| Native reread of eight saved WAVs | Exact phone PCM hashes and sample counts |
| `git diff --check` | Passed |

The project was generated/restored through `scripts/generate_project.py` for the affected FireRed build; no generated project diff remains. Existing interruption/async-alternative/AppIntents warnings remain, with no new app warning. No unrelated build settings changed. Exact commands and full logs remain private alongside the evidence.

Highest logged VAD-phase footprint: 37,537,608 bytes in the comparison, 39,372,640 bytes in final verification. Highest logged lifetime footprint peak: 47,974,264 and 39,815,008 bytes, respectively. These are instrumented VAD-only observations, not a FireRed safety finding or proof of unlogged allocation peaks. No new ASR latency, WER or transcript-format accuracy result is claimed.

### Private evidence identities

| Private file | Full SHA-256 |
|---|---|
| `plan.json` | `8177b491b82e1106c231e1bae9926132b88f66fa4a4943d6779e8c92ce10f4ca` |
| `labeled-probabilities.json` | `b9839558dbbcca040052ec2d6b4a3f59aea0599a3337fb99cc489f6ec65b20c1` |
| `final-labeled-probabilities.json` | `84c2e138321c2e6b854a42851475db8842d80021b62ebb9446c50512881ca0ca` |
| `all-policy-results.json` | `ba09b59d7f6ed92b1c985e41cbb221b2198460019bc0551f613d15f1de7e3e4e` |
| `final-fixtures/manifest.json` | `fb8a925c093ea5e3b680b13d20b35a6645d0dd4bef0a88debe043735917dc0ea` |
| `comparison-complete.log` | `a4f4be2f5645f2c02bcdf3e89fae3fa6166cd311af015ce92c7969b2ba7b0af0` |
| `final-complete.log` | `0dc0bcf9cfb523de452336fa386840ccf39b94d0fda4f47eb4fae878944e9920` |

Fixture hashes identify retained files or logged probability evidence as labeled, never nonexistent original WAVs. Full logs, voice recordings and human text stay private. English capitalization, Simplified/Traditional output and Breeze spacing remain separate deferred model/formatting issues.

Ordinary Mural with the fixed gate was restored without probe/retention arguments. The owned log capture was stopped and the phone released. No existing user file was staged, deleted or overwritten by this investigation. The three initially untracked handoffs were already absent at final merge preflight; their removal is outside this patch and was not reverted. Main `mvp` remained at the original base with a clean tracked tree. Accepted model assets, signing and stored data were not changed. Integration is local only; FireRed memory safety has not been relaxed.
