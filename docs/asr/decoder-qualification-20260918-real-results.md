# Decoder qualification real results - 2026-09-18

Status: REAL local-device evidence, sanitized summary. Raw recordings, the private app store, and full device logs remain under the ignored `.build/verification/decoder-qualification-20260918-052154/live-pal6-always/private/` directory and are not committed.

## Decision

- The isolated decoder result qualifies the accepted packed-v3 FP8 encoder with the PAL6 decoder as the lab candidate: all native, corpus, and live gates completed without a decoder quality difference in the scored corpus, while decoder-phase loaded and text-end footprint medians were about 18.9% lower than PAL8.
- Keep the accepted FP8 encoder plus PAL8 decoder fully available as the safe control. Do not switch normal/default Talk, default decoder precision, silence handling, or VAD behavior.
- Keep `--coreai-w8-v3-prewarm=always` as the normal explicit policy. `prewarm=once` remains an opt-in experiment only: it removed repeated prewarm work, but this run did not establish a clean UI latency win and the full staged scope remained harness-sensitive.
- The result is a qualification decision for this isolated experiment, not a default product promotion.

## Provenance and safety stops

The reviewed remote head was `eb2675980cd9c944cd376d7bb70e4d2800f15df8` on `mvp`. `git fetch origin mvp` found no movement, and the worktree was an ancestor of the remote before applying the connector-delivered patch. The patch was checked and applied without reset, stash, rebase, force push, cache deletion, accepted-asset replacement, warning-latch clearing, or learning-data deletion.

The runtime work is explicit-flag-only. The accepted PAL8 support stayed in place. The candidate PAL6 support was copied only into its previously absent identity directory after the static admission check. The app was built and launched as a new process on the physical device; no historical PID or device identity was reused.

## Artifact identities

| artifact | identity | measured bytes/scope |
|---|---|---:|
| accepted packed-v3 FP8 encoder manifest | `73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13` | manifest SHA256 |
| accepted FP8 h18p AOT encoder | `c5c7d3264c7256fc50c37e4e4a3471ec69c278397f1887cca65b96a6ee796c65` | 640,483,375 logical AOT bytes |
| accepted PAL8 support manifest | `430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336` | 1,655,763,645 logical support bytes |
| historical PAL6 decoder support manifest | `13f9bbd0d08bf0b6a111f8415ddffad158f8d1fb4e4014c17585066e37fd23bb` | 1,265,613,461 logical support bytes |
| PAL8 `TextDecoder.mlmodelc` | manifest component | 991,764,466 logical bytes |
| PAL6 `TextDecoder.mlmodelc` | manifest component | 769,115,313 logical bytes |
| Release app executable | `ea49040554518d349b1d832452e09ac46583b2fe4cad976838ec11597f0af90b` | SHA256 |

The PAL6 decoder component is 222,649,153 bytes smaller than PAL8, or 22.45% smaller by manifest logical bytes. These are asset sizes, not physical RAM. The support manifests otherwise passed decoder-only admission; the staged PAL6 root included the historical shared files, while the runtime supplied hidden states from the fixed FP8 encoder and did not use the support `AudioEncoder.mlmodelc`.

Device: iPhone 17 (`iPhone18,3`), UDID `00008150-000D25942278401C`, iOS 27.2 build `24B5084k`. Build: Xcode `27A5252f`, Swift 6.4, Release, `MURAL_COREAI_TALK` and `MURAL_COREAI_W8`. The corpus contexts recorded source commit `eb2675980cd9c944cd376d7bb70e4d2800f15df8`, the executable hash above, retained-cache/new-process conditions, and the explicit run arguments.

## Recovered PAL6 encoder evidence and measurement audit

The actual local report was recovered at `.build/verification/pal6-qualification-20260918-report/qualification-report.md`. It is not a reconstructed result and was not present in the latest commit. Its raw evidence includes `event-metrics.json`, `resource-metrics.json`, and `live-timing.json`; hashes are listed below.

The report's audit covered 194 compressed matrices, 293 retained dense tensors, 7 below-threshold tensors, and 3 explicit retained rank exceptions. It measured logical tensor payload bytes only, not serialized/AOT bytes or RAM. The corrected audit had no warnings. The prior accepted FP8 versus PAL6 encoder corpus used run IDs `62D9E992-0CB1-4432-88FF-4886B32420A9` and `8D299A43-1435-48D1-BF2D-8CFD5BD3A63F`; audio, mel, language, and termination matched 22/22, raw/normalized/token fields matched 21/22, and the known fixture-007 error was retained rather than hidden. No encoder was rebuilt or retested for this decoder experiment because the recovered evidence had no concrete identity mismatch or missing measurement scope.

The same prior instrumentation showed PAL6 encoder native time lower but full staged time slower: median staged full `2.877399 s` FP8 versus `3.438254 s` PAL6, native encoder `0.563554 s` versus `0.433748 s`, and function load `0.222565 s` versus `1.228565 s`. Phase-specific footprint medians were encoder-response `434,752,000 B` versus `235,154,352 B`, post-release `214,181,920 B` versus `168,445,912 B`, and staged-full `1,253,918,932 B` versus `1,253,337,252 B`. Process-lifetime RSS was `1,406,582,784 B` versus `2,603,810,816 B`, about 85.1% higher for PAL6. The phase samples and RSS are reported separately and are not combined into a physical-footprint claim.

## Implementation, admission, and validation commands

The supplied tests and the narrow host checks passed:

```text
PYTHONPATH=Tools/CoreAI python3 -m unittest -v test_decoder_trial       # 32 passed
python3 Tools/CoreAI/test_product_residency.py                          # PASS
python3 Tools/CoreAI/test_w8_identity.py                                # OK, one environment skip
python3 Tools/CoreAI/test_hybrid_layout.py                              # PASS
python3 Tools/CoreAI/test_cached_load.py                                 # PASS
python3 Tools/CoreAI/test_talk_opt_in.py                                # PASS
/Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/.venv/bin/python \
  Tools/CoreAI/test_w8_runtime_identity.py                              # 8 passed
```

Static decoder-only admission was run before staging:

```text
PYTHONPATH=Tools/CoreAI python3 Tools/CoreAI/prepare_pal6_decoder_trial.py \
  --reference-support /Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/phone-assets/phowhisper-cs-pal8-g16-v1 \
  --historical-pal6-support /Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/phone-assets/phowhisper-cs-pal6-g16-v1 \
  --fp8-manifest .build/coreai/w8-id-v3/packed/encoder-fp8/manifest.json \
  --repo-root "$PWD" \
  --output-dir .build/verification/decoder-qualification-20260918-052154/admission \
  --stage-support
# static-only gate passed; only TextDecoder.mlmodelc differed
```

The final device build was:

```text
xcodebuild -project Mural.xcodeproj -scheme Mural -configuration Release \
  -destination 'platform=iOS,id=00008150-000D25942278401C' \
  -derivedDataPath .build/verification/decoder-qualification-20260918-052154/device-derived-data \
  PRODUCT_BUNDLE_IDENTIFIER=com.kevintruong.mural.dev \
  OTHER_SWIFT_FLAGS='$(inherited) -D MURAL_COREAI_TALK -D MURAL_COREAI_W8' build
# BUILD SUCCEEDED; only pre-existing WebRTC, AVAudio, and AppIntents warnings remained
```

The native ABI/control gate ran two fixture-001 turns per artifact with the same fixed FP8 encoder, retained cache, and `prewarm=always`:

| decoder | run | result | transcript agreement | decoder seconds, turn 1 / 2 | errors | memory warnings |
|---|---|---|---|---:|---:|---:|
| PAL8 | `A18811CF-110B-484D-909C-F76516F70859` | complete, terminal | exact / exact | 0.816 / 0.836 | 0 | 0 |
| PAL6 | `22FD6718-6370-4913-A77B-C5EE150D37FD` | complete, terminal | exact / exact | 1.383 / 1.018 | 0 | 0 |

## Main isolated experiment: FP8 encoder with PAL8 versus PAL6 decoder

Each side ran the frozen 22-fixture corpus in three matched new processes. Fixture 017 stayed diagnostic and was excluded from the 21-fixture scored set. Each report was complete, terminal, error-free, and memory-warning-free. The analyzer treated normalized agreement as comparison evidence, not accuracy.

| pair | PAL8 run | PAL6 run | normalized agreement | staged full change | decoder change | loaded decoder footprint change | process-lifetime RSS, PAL8 / PAL6 |
|---|---|---|---:|---:|---:|---:|---:|
|1|`CF85EBA7-32A6-4D3E-93D2-BAB623C3C463`|`CE928F9A-E795-4AA4-9FBF-4C4C87D14DA1`|21/21|-2.52%|-0.79%|-18.50%|1,445,216,256 / 1,451,393,024|
|2|`03400FEA-7DBE-4C5B-BFF9-D4A2C042890F`|`8C319975-DDAE-4A92-8C0F-02992458AE6B`|21/21|+3.24%|+4.45%|-20.87%|1,408,073,728 / 1,401,716,736|
|3|`39559411-2278-44B2-A273-4C14AC65E2DD`|`4B013D52-8A37-4363-A4DD-DE02A64CA10E`|21/21|-21.22%|-5.17%|-17.43%|1,452,294,144 / 1,450,967,040|

Run-level descriptive results across the three matched pairs:

| metric | PAL6 change versus PAL8 | pair range |
|---|---:|---:|
| staged full harness interval | -6.83% mean | -21.22% to +3.24% |
| decoder seconds | -0.50% mean | -5.17% to +4.45% |
| decoder loaded footprint sample | -18.94% mean | -20.87% to -17.43% |
| decoder text-end footprint sample | -18.92% mean | -19.90% to -17.99% |
| encoder-end footprint sample | -3.74% mean | -7.30% to -0.97% |
| process-lifetime RSS | not a saving claim | PAL8 1,408,073,728 to 1,452,294,144 B; PAL6 1,401,716,736 to 1,451,393,024 B |

The process RSS values are lifetime peaks for each process. They are not per-turn RAM and do not cancel or replace the phase-specific decoder footprint samples. The staged full timer includes audio read, encoder preparation, decoder work, and synchronous diagnostic/report writes; it is not app Send-to-final.

### Per-fixture metrics

The following values are medians across the three matched runs for each fixture. `staged` is the full lab harness interval in seconds, `decoder` is decoder seconds, and the two byte columns are phase-specific footprint samples. Fixture 017 is shown for diagnostic visibility and is not included in scored aggregates.

|fixture|PAL8 staged s|PAL8 decoder s|PAL8 loaded B|PAL8 text-end B|PAL6 staged s|PAL6 decoder s|PAL6 loaded B|PAL6 text-end B|
|---|---|---|---|---|---|---|---|---|
|001.wav|4.099|0.825|1,156,417,568|1,262,717,080|3.660|0.810|966,576,160|1,039,386,824|
|002.wav|2.482|0.868|1,285,785,632|1,256,016,048|2.506|0.871|1,041,467,352|1,019,185,400|
|003.wav|2.660|0.964|1,314,670,600|1,275,201,688|2.583|0.967|1,028,933,616|1,015,400,672|
|004.wav|2.335|0.835|1,276,381,240|1,261,783,216|2.431|0.879|1,048,791,144|1,017,186,480|
|005.wav|2.246|0.780|1,289,848,840|1,257,785,520|2.281|0.780|1,027,278,832|1,013,188,856|
|006.wav|2.687|0.778|1,286,375,432|1,265,027,272|2.347|0.791|1,038,665,832|1,012,730,056|
|007.wav|3.145|1.647|1,283,131,400|1,255,082,136|3.244|1.721|1,023,756,272|1,021,954,200|
|008.wav|2.823|1.240|1,287,063,560|1,289,291,976|2.758|1.253|1,019,938,800|1,006,520,496|
|009.wav|2.812|1.363|1,279,215,672|1,251,330,224|2.858|1.374|1,040,648,296|1,011,812,552|
|010.wav|2.399|0.947|1,298,565,128|1,267,222,728|2.415|0.934|1,040,222,192|1,009,076,472|
|011.wav|2.699|1.134|1,306,150,920|1,274,808,520|2.627|1.133|1,022,380,016|1,009,191,160|
|012.wav|2.549|1.117|1,293,600,776|1,262,258,376|2.643|1.126|1,040,074,736|1,008,847,120|
|013.wav|2.923|1.509|1,293,731,848|1,254,787,272|3.024|1.517|1,039,124,464|1,008,748,816|
|014.wav|2.344|0.951|1,286,572,088|1,255,246,024|2.443|0.931|1,039,009,776|1,008,847,120|
|015.wav|2.415|1.002|1,262,209,032|1,242,335,408|2.504|0.996|1,040,549,992|1,009,092,856|
|016.wav|2.878|1.401|1,273,759,800|1,235,585,224|2.912|1.370|1,039,190,120|1,007,733,008|
|017.wav|6.149|4.514|1,277,659,192|1,243,613,408|5.906|4.389|1,037,944,936|1,005,963,536|
|018.wav|2.987|1.360|1,275,627,600|1,239,927,008|2.730|1.306|1,040,910,320|1,009,469,640|
|019.wav|3.192|1.736|1,259,374,600|1,243,711,712|3.254|1.745|1,037,289,576|1,010,452,680|
|020.wav|3.205|1.584|1,268,107,320|1,254,983,880|3.060|1.524|1,020,463,208|1,014,614,192|
|021.wav|4.808|1.536|1,180,649,552|1,267,239,136|2.958|1.458|1,037,142,120|1,010,485,448|
|022.wav|4.740|2.005|1,194,330,120|1,250,887,904|3.370|1.851|1,018,939,352|1,005,799,696|

Scored transcript comparison: 21/21 normalized agreements in every pair, zero raw/token/language differences, identical fixed FP8 hidden-state hashes, mel hashes, and audio hashes. This is not a ground-truth accuracy test; every raw difference would have required review.

## Separate prewarm policy experiment

After fixing the decoder decision to the PAL6 candidate, three matched PAL6 pairs compared `always` versus `once`, with the exact same FP8 encoder, PAL6 support, corpus, retained cache condition, app executable, and process-isolation rules. `once` skipped the repeated prewarm operation after the first successful turn but still loaded and unloaded the decoder and kept native drains.

| pair | always run | once run | normalized agreement | staged full change | prewarm change | decoder change | loaded footprint change |
|---|---|---|---:|---:|---:|---:|---:|
|1|`CE928F9A-E795-4AA4-9FBF-4C4C87D14DA1`|`3D941E6F-27CA-4AF1-B71E-C6612EDEA751`|21/21|-0.71%|-79.51%|+1.83%|+0.58%|
|2|`8C319975-DDAE-4A92-8C0F-02992458AE6B`|`0ABE7D8C-1517-4273-BB16-3A34405AB329`|21/21|-28.36%|-96.69%|-1.81%|+3.90%|
|3|`4B013D52-8A37-4363-A4DD-DE02A64CA10E`|`34778F95-9006-4AD4-BDCB-46133B2347FC`|21/21|-4.09%|-89.34%|+1.49%|+0.89%|

Run-level descriptive summary for `once` versus `always`: staged full `-11.05%` mean, range `-28.36%` to `-0.71%`; prewarm `-88.52%` mean, range `-96.69%` to `-79.51%`; decoder seconds `+0.50%` mean, range `-1.81%` to `+1.83%`; loaded footprint `+1.79%` mean, range `+0.58%` to `+3.90%`. All three pairs had 21/21 normalized agreement and zero raw/token/language differences. The policy result is therefore useful as a separate opt-in optimization observation, not evidence to change normal/default Talk.

### Per-fixture prewarm metrics

These are medians across the three policy pairs. The first fixture includes the one required prewarm; later `once` rows are near zero because the policy reuses the successful prewarm hint while still performing the real load/unload path.

|fixture|always prewarm s|always decoder s|always staged s|once prewarm s|once decoder s|once staged s|
|---|---|---|---|---|---|---|
|001.wav|0.557|0.810|3.660|0.359|0.848|3.369|
|002.wav|0.129|0.871|2.506|0.000|0.983|2.503|
|003.wav|0.129|0.967|2.583|0.000|1.005|2.420|
|004.wav|0.128|0.879|2.431|0.000|0.840|2.195|
|005.wav|0.116|0.780|2.281|0.000|0.804|2.169|
|006.wav|0.128|0.791|2.347|0.000|0.815|2.180|
|007.wav|0.124|1.721|3.244|0.000|1.718|3.139|
|008.wav|0.119|1.253|2.758|0.000|1.250|2.628|
|009.wav|0.118|1.374|2.858|0.000|1.363|2.713|
|010.wav|0.115|0.934|2.415|0.000|0.907|2.278|
|011.wav|0.122|1.133|2.627|0.000|1.132|2.511|
|012.wav|0.121|1.126|2.643|0.000|1.129|2.529|
|013.wav|0.119|1.517|3.024|0.000|1.526|2.913|
|014.wav|0.116|0.931|2.443|0.000|0.944|2.322|
|015.wav|0.114|0.996|2.504|0.000|1.010|2.394|
|016.wav|0.118|1.370|2.912|0.000|1.430|2.831|
|017.wav|0.116|4.389|5.906|0.000|4.527|5.942|
|018.wav|0.116|1.306|2.730|0.000|1.299|2.644|
|019.wav|0.127|1.745|3.254|0.000|1.848|3.247|
|020.wav|0.133|1.524|3.060|0.000|1.593|2.997|
|021.wav|0.121|1.458|2.958|0.000|1.553|2.957|
|022.wav|0.116|1.851|3.370|0.000|1.977|3.390|

## Live app gate and natural-pace interview

The app was launched explicitly with:

```text
xcrun devicectl device process launch --device 00008150-000D25942278401C \
  --terminate-existing com.kevintruong.mural.dev \
  --coreai-w8-v3-encoder=fp8 --coreai-w8-v3-decoder=pal6 \
  --coreai-w8-v3-prewarm=always --timeout 30
```

The interview form was presented once with the complete short block before the user pressed Record. No new form was shown between Record and speech. The user completed the block at the app's natural pace. The local store and bounded Mural-only log recorded eight completed app turns: six planned turns plus two repeat attempts. No failed or incomplete ASR turn, memory-warning line, or trial failure was present.

The exact app transcript text and direct app timings below are evidence from the local store and log, not guessed browser or interview delays. `Send-to-final` is emitted at ASR finalization. `Send-to-first-tutor-audio` is emitted by the first playback callback. The latter event has no ASR ID in this app build, so it is paired in completed-turn order; all eight completed turns and eight audio-start events are present.

| turn | exact app transcript | Send-to-final s | Send-to-first-tutor-audio s |
|---:|---|---:|---:|
|1|Yes.|2.699|5.340|
|2|I ordered phở không hành, và đẻ cho y mi thêm hành.|2.910|4.857|
|3|Ngày mai I have an appointment nên em không đi được.|3.888|7.567|
|4|I need 15, not 50.|3.292|5.223|
|5|No.|2.447|3.920|
|6|Today I went to siêu thị how do I say that in English.|3.338|5.482|
|7|Ngày mai I have an appointment nên em không đi được.|3.110|5.273|
|8|I ordered phở không hành but they gave me thêm hành.|3.092|6.299|

Live timing summary: Send-to-final mean `3.097 s`, median `3.101 s`, range `2.447-3.888 s`; Send-to-first-tutor-audio mean `5.495 s`, median `5.307 s`, range `3.920-7.567 s`. These two measures are intentionally separate. The replay timer was not labeled as full ASR, no instruction or browser delay was subtracted, and no physical footprint claim was made from process-lifetime RSS.

Human feedback was qualitative: the user reported no visible errors or UI anomalies on the successful turns; one first attempt was described as inaccurate, with pronunciation and fan noise suspected, and a repeat after moving away from the fan was described as accurate. The remaining turns were described as accurate. The user reported normal temperature before the block and only a little warmth afterward, no unexpectedly slow UX, and an overall positive result. The screenshot after the block showed the app ready to record with no visible error state.

## Exclusions and uncertainty

- The first native PAL8 sequence run `D3C4E63D-2EDD-4068-B214-6FE1FF3989CA` was excluded because it hit the pre-fix sequence guard before inference. It is retained and hashed below. The guard was narrowed to permit the documented fixture-001 two-turn gate, then the PAL8 and PAL6 sequence gates were rerun successfully.
- One attempted later launch occurred while the phone was locked and produced no run; it is not counted as evidence.
- Fixture 017 is a diagnostic long/thermal fixture and is excluded from scored quality/performance aggregates.
- The three-pair analyzer reports descriptive run-level changes, not confidence intervals. Footprint samples are event-boundary observations, not continuous peak physical RAM. Decoder loop and prediction fields overlap and were not summed.
- The PAL6 encoder evidence was not retested or rebuilt because its recovered report already covered the relevant identity, corpus, live, phase-memory, and RSS scopes.
- The live interview form did not collect user-entered exact display text. Exact transcript rows above come from the private app store/log evidence; the private store and full raw device log remain local.
- No objective skin temperature, battery, sustained thermal throttling, or statistically matched live FP8/PAL8 versus FP8/PAL6 corpus was claimed.

## Evidence hashes

These hashes identify the local evidence without committing private recordings, the app store, or personal logs.

### Key outputs

| path | SHA256 |
|---|---|
|`.build/verification/decoder-qualification-20260918-052154/admission/admission.json`|`c332702c6b89d5198947cd2e0abb094ba5f4358a977e9b6b3b23f271ea64b6a8`|
|`.build/verification/decoder-qualification-20260918-052154/decoder-analysis-3pairs.json`|`37b41e3d7ef2120b5e3b7fa818964417a17239c23ce635ca94c8ab920524e2af`|
|`.build/verification/decoder-qualification-20260918-052154/prewarm-analysis-3pairs.json`|`4118d26325db2121dc76e7a0a81dca76b3e55d1e9ee82132897f9b9c2727ff83`|
|`.build/verification/decoder-qualification-20260918-052154/live-pal6-always/live-timing.json`|`2e760bcc920e7f20d36696e26f143ac08f17d5767328b66d53fab323d3aa74fe`|
|`.build/verification/decoder-qualification-20260918-052154/live-pal6-always/live-send-timing.json`|`944b8a429455363ebfe5d652c068c1647cb56f95d918ab1db61f44437eeb23ee`|
|`.build/verification/decoder-qualification-20260918-052154/live-pal6-always/mural-device.log`|`704ccc3c03151b02d51297e422bef9f7744ee5412dcc03011d59360ad59ffec1`|
|`.build/verification/decoder-qualification-20260918-052154/live-pal6-always/after-block.png`|`672f49575637972af69bc6f50af73f1a7f75ec8820ba77972eeceb2b76e8f52c`|
|`.build/verification/decoder-qualification-20260918-052154/build-sequence-fix.log`|`7feb10d76d35324aa035e76cd265a33e8a837e9dba15c9175956bb0eaf2a3e29`|
|`.build/verification/decoder-qualification-20260918-052154/test_decoder_trial-final.log`|`7bd0476ee4df7338257ce813bc47b7615b897219b2f95c59a5b664948881379a`|
|`.build/verification/decoder-qualification-20260918-052154/sequence-pal8-fix/run-A18811CF-110B-484D-909C-F76516F70859/report.json`|`f6d1f26b9bf53c2e0fd7b870115ae6c844710fee085778f3feb662252480c148`|
|`.build/verification/decoder-qualification-20260918-052154/sequence-pal8-fix/run-A18811CF-110B-484D-909C-F76516F70859/events.jsonl`|`fd68faa77acaf7838351b5524541623ae8d37c731b1c3662c84daf14625e8aa9`|
|`.build/verification/decoder-qualification-20260918-052154/sequence-pal6/run-22FD6718-6370-4913-A77B-C5EE150D37FD/report.json`|`a8270824898763e20f637704810c8f360d252f683c95efe67133be283700cbc4`|
|`.build/verification/decoder-qualification-20260918-052154/sequence-pal6/run-22FD6718-6370-4913-A77B-C5EE150D37FD/events.jsonl`|`25968befe51a9569eea032a98cea447709c1cbb36d3139503d024668f88b80da`|
|`.build/verification/decoder-qualification-20260918-052154/sequence-pal8/run-D3C4E63D-2EDD-4068-B214-6FE1FF3989CA/report.json`|`e5a9fd7d10bd78f9edb62a069d4c95b227b99adaa31b64afa063ef9b530d1b23`|
|`.build/verification/pal6-qualification-20260918-report/qualification-report.md`|`2b2042000f65c876d8ea7da3daaf022081e9ca4fb12664e0731edcd9a49835a4`|
|`.build/verification/pal6-qualification-20260918-report/event-metrics.json`|`315a2ee81b82ab4eb0539a3c74b23f25835bb51607b16c1ac3f5f39608e5b307`|
|`.build/verification/pal6-qualification-20260918-report/resource-metrics.json`|`dc87101049ee5f2889dbdd571b4413292f8d79636ab3599d8bc755dc0228c157`|
|`.build/verification/pal6-qualification-20260918-report/live-timing.json`|`6eb73d3c778ff6906ab3ab7743437f6745cad9be0fade6a29a6227cdaf73ff9c`|

### Matched run evidence

| group | run | file | SHA256 |
|---|---|---|---|
|decoder PAL8|`CF85EBA7-32A6-4D3E-93D2-BAB623C3C463`|`report.json`|`e15402322e1009e9a868a88e4b1e25a79e731bed3f6ab91a79ee1a8cdd8ef71a`|
|decoder PAL8|`CF85EBA7-32A6-4D3E-93D2-BAB623C3C463`|`events.jsonl`|`aca665f078ed827810b21b6fdb47d07865125787ade10d23116bb8e5263cff74`|
|decoder PAL8|`CF85EBA7-32A6-4D3E-93D2-BAB623C3C463`|`trial-context.json`|`b9a958731b7eed567a4e869cb5998e57c1ebef94c58e4f5af24b15900e2df90b`|
|decoder PAL8|`03400FEA-7DBE-4C5B-BFF9-D4A2C042890F`|`report.json`|`eadb18e4be74f34f21f05f1fdee98830b4f31dad2753143026aa9b88409f6dfb`|
|decoder PAL8|`03400FEA-7DBE-4C5B-BFF9-D4A2C042890F`|`events.jsonl`|`328180727db5f93e7ea01697dabd55f040da058807eb7b3036fdbdb520491802`|
|decoder PAL8|`03400FEA-7DBE-4C5B-BFF9-D4A2C042890F`|`trial-context.json`|`aae5e28da55d22a4848bbaff2a3d1fcb4e96d5a34486cd9f8da7c9243c5211b0`|
|decoder PAL8|`39559411-2278-44B2-A273-4C14AC65E2DD`|`report.json`|`812ea4931175ee1fd20cf1d7461b68d411396efbf3eb6e6a8890d53a86ba0f42`|
|decoder PAL8|`39559411-2278-44B2-A273-4C14AC65E2DD`|`events.jsonl`|`f396e5eac3913dfc06affa6d77e4ecbc5c057646a249927d27d2a1d694205f45`|
|decoder PAL8|`39559411-2278-44B2-A273-4C14AC65E2DD`|`trial-context.json`|`239939c2a5dff75eb8583242891fa07bc29bbf6d98179543f78679d51fa99924`|
|decoder PAL6|`CE928F9A-E795-4AA4-9FBF-4C4C87D14DA1`|`report.json`|`f80cbacbce3448e52d3fb856af3c5f792575247a9a462937ebb63d9ef32ec88b`|
|decoder PAL6|`CE928F9A-E795-4AA4-9FBF-4C4C87D14DA1`|`events.jsonl`|`7f889b3795bd36edac807bca735a52df9c3eca63a8b8f154eec9f8f5f38f37ef`|
|decoder PAL6|`CE928F9A-E795-4AA4-9FBF-4C4C87D14DA1`|`trial-context.json`|`97912ea63e0e891aa1ed867cbf2d46dd171965fc2985e488c971aff3026a0b3d`|
|decoder PAL6|`8C319975-DDAE-4A92-8C0F-02992458AE6B`|`report.json`|`d8509c540372dc311e290621e7050b60f5dd6fd410625112770a1023efd0ef3c`|
|decoder PAL6|`8C319975-DDAE-4A92-8C0F-02992458AE6B`|`events.jsonl`|`7b584201df3d5cf006ebeefdebfe05cb9c5c168f76e2d46b2e445d3b6b429aad`|
|decoder PAL6|`8C319975-DDAE-4A92-8C0F-02992458AE6B`|`trial-context.json`|`58ab24aebcf08ccfb7fc81a084e521024b91eedaa0715834ef54b21d335a27e2`|
|decoder PAL6|`4B013D52-8A37-4363-A4DD-DE02A64CA10E`|`report.json`|`991ca463efe20be1e2d129221157cdc1bc504c08439e9a1afd4ff041f681cfc0`|
|decoder PAL6|`4B013D52-8A37-4363-A4DD-DE02A64CA10E`|`events.jsonl`|`9fa7876e5b9818d94cb5ff95eb2d3afd2bfbe7bff4401801a587eb1240417dbb`|
|decoder PAL6|`4B013D52-8A37-4363-A4DD-DE02A64CA10E`|`trial-context.json`|`2873cceb27d7583c467a9d8d26f397e2f6ea70fd5a84964bb96e39df4cae672a`|
|prewarm once|`3D941E6F-27CA-4AF1-B71E-C6612EDEA751`|`report.json`|`671d428e7ed8631b97d981d53fc37b879085ee846bd2ffa33df0bc3d2fbe6c9d`|
|prewarm once|`3D941E6F-27CA-4AF1-B71E-C6612EDEA751`|`events.jsonl`|`4f62a5b3ef9544153d39a507969508f8152609ea65292c74b645bba45aea9555`|
|prewarm once|`3D941E6F-27CA-4AF1-B71E-C6612EDEA751`|`trial-context.json`|`87255efd21fdea7ac49397259dd3c92d6cfdb8e84599c2aa61b830af576445f3`|
|prewarm once|`0ABE7D8C-1517-4273-BB16-3A34405AB329`|`report.json`|`167063497401b3062e23d00a41660de175611194621ca7411ebcae1a4190690a`|
|prewarm once|`0ABE7D8C-1517-4273-BB16-3A34405AB329`|`events.jsonl`|`91bee930a83c707a0f04ab3e5011546ca6eb6ec1f6f9a6cd9ba2a68b2adb1f1a`|
|prewarm once|`0ABE7D8C-1517-4273-BB16-3A34405AB329`|`trial-context.json`|`e840254c6f055c4f3c6291ca05c5534fa7e17e4d1e947b2153f9d08603ab088a`|
|prewarm once|`34778F95-9006-4AD4-BDCB-46133B2347FC`|`report.json`|`78029d6503bbb450bae1524db4b84f25a09ebf2ca2643008aa1edeec8cf7f9e4`|
|prewarm once|`34778F95-9006-4AD4-BDCB-46133B2347FC`|`events.jsonl`|`24f14fcc8fb182e713c25b79b836cb0fccaa223c0a053d80cc285ab93504770b`|
|prewarm once|`34778F95-9006-4AD4-BDCB-46133B2347FC`|`trial-context.json`|`64730f942f831875ec2f585ee620386ae3680bc884fb0ceca01c5da5182e5d41`|

The app executable hash, model manifest hashes, and AOT fingerprint are also recorded above and in every run context. The full ignored evidence tree remains available locally under `.build/verification/decoder-qualification-20260918-052154/`.
