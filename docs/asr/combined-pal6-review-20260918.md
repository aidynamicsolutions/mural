# PAL6 encoder + PAL6 decoder: review and bounded-trial decision

Date: 2026-09-18. Reviewed remote head: `374a7b3abecc87c9f5b78959f3ab1e48084e18ae`.
Status: repository/sanitized-evidence review and host-tested trial implementation.
**Not a new iPhone qualification, model conversion, benchmark or promotion.**

## Decision

**GO for one bounded, current-OS native gate of the existing PAL6/PAL6 artifacts;
NO-GO for promotion or a speed/storage-saving claim on current evidence.**
If the gate is safe and the incremental tradeoff still warrants investigation,
continue to matched corpus runs, then live/lifecycle gates. Stop the candidate
on identity/ABI failure, crash, warning, unsafe overlap or meaningful new speech
corruption. Do not rebuild a model just to pursue a positive result.

Keep A = **FP8 Core AI encoder + PAL8 Core ML decoder** available throughout.
B = **FP8 encoder + PAL6 decoder** is the already qualified decoder lab candidate.
C = **PAL6 encoder + PAL6 decoder** is the new, unqualified joint candidate.
D = PAL6 encoder + PAL8 decoder is the historical encoder intermediate, not a
promoted configuration. FP8 is not PAL8. All feature boundaries remain FP16.

B is indispensable: C-versus-A changes two components. The decoder's established
saving must not be credited to adding the PAL6 encoder. C-versus-B tests whether
the additional PAL6 encoder actually improves the best decoder lab configuration.

## Reviewed evidence, without private uploads

The committed `decoder-qualification-20260918-real-results.md`, its recorded
commands, source and the user's complete sanitized context were sufficient for
this review. Private recordings, app store, screenshots and full logs were not
requested or accessed. Their hashes are provenance references, not independent
verification of inaccessible bytes. No reported phone run was repeated here.

The isolated decoder conclusion is proportionate: three complete 22-file pairs,
21 scored fixtures, no raw/token/language differences, matching inputs and FP8
hidden hashes, no warnings/errors, and consistent lower decoder-phase footprint.
This is agreement with a control, not 100% ground-truth accuracy. The live fan/noise
attribution is a hypothesis; the inaccurate first attempt remains a real recorded
outcome and the successful retry must not replace it.

The PAL6 encoder did not show "no benefit": its native median was 0.433748 s
versus 0.563554 s and encoder-response footprint was 235,154,352 B versus
434,752,000 B. But function load was 1.228565 s versus 0.222565 s; staged full
was 3.438254 s versus 2.877399 s. Lifetime RSS increased from 1,406,582,784 B to
2,603,810,816 B. These results are not logically inconsistent. A later phase
sample can be smaller despite a larger earlier lifetime peak.

Descriptive arithmetic on those medians: about 0.130 s less native execution
versus about 1.006 s more function load. Their roughly 0.876 s net disadvantage
is an explanatory estimate, NOT a measured paired component total: marginal
medians do not add to the median total. Reducing decoder precision does not
in itself remove that encoder loading step.

### Measurement qualifications

* The existing analyzer computes each run's scored per-fixture **mean**, computes
  its percentage change, then summarizes the three run-level changes. Thus
  -18.94% is not a ratio of pooled footprint medians. The report's introductory
  "medians about 18.9%" wording should be read with this correction. The user's
  three per-pair median loaded footprints imply -18.41%, -22.57%, -18.71%; those
  are different estimands, not an inconsistency in the underlying measurements.
* The `staged-asr-full-complete` code starts **after audio read**, despite one report
  sentence saying it includes audio read. It includes encoder work, decoder
  preparation, transcription and intervening synchronized diagnostic/report work.
  It is not UI Send-to-final. The older replay timer excludes real encoder work.
* Three pairs are descriptive evidence, not 63 independent device experiments or
  a confidence interval. Decoder changes from -5.17% to +4.45% do not establish a
  reliable speedup. Policy comparisons reused the recorded always runs; schedule,
  temperature and order still matter. Counterbalance new runs rather than pool
  every fixture as an independent replicate.
* The current analyzer checks complete/error-free reports but does not itself
  require `terminal=true`, exact known encoder AOT pins, or post-release samples.
  The new combined analyzer adds those requirements. This does not imply that
  the reported completed runs failed them; the report explicitly records success.
* Long diagnostic 017 remains outside scored aggregates but still occurs in the
  physical run and can affect later thermal conditions. Keep order matched and
  show first/warm/pre-017/post-017 observations when interpreting a discrepancy.
* Live first-audio events in the prior build lacked an ASR ID and were joined by
  order. Eight events matched eight turns, but this is weaker than explicit IDs.
  The patch adds a once-per-generation audio event; its analyzer refuses ordinal
  pairing. It records the app playback callback, not measured acoustic onset.

The accepted live block averaged 3.097 s to final ASR and 5.495 s to first tutor
audio. Their ~2.398 s mean gap includes tutor/coordinator/TTS/audio work, not just
ASR. No matched live control established a speed improvement. A smaller speech
model alone cannot remove all of that remaining conversation delay.

## Storage: the combined candidate is larger on the relevant deployed path

| Component sum (logical bytes) | A: FP8/PAL8 | B: FP8/PAL6 | C: PAL6/PAL6 |
|---|---:|---:|---:|
| Core AI encoder AOT | 640,483,375 | 640,483,375 | 1,273,967,904 |
| Used Core ML TextDecoder | 991,764,466 | 769,115,313 | 769,115,313 |
| Sum | 1,632,247,841 | 1,409,598,688 | 2,043,083,217 |

C is **410,835,376 B / 25.17% larger than A** on this component sum, and
633,484,529 B larger than B. Equal shared files, source assets, unused support
AudioEncoder files and retained caches are excluded from all three sums.
This is not total app-disk accounting and absolutely not RAM accounting.

The PAL6 portable source is only 483,765,816 B, but that is not the 1,273,967,904 B
AOT loaded by this trial. A six-bit source label does not establish compressed
native executable storage. AOT expansion and transient loading allocations are
plausible explanations; inspection/phase tracing is needed to establish the
compiler mechanism. Do not claim proven FP16 expansion from the byte ratio alone.
Do not delete existing source, support or caches to manufacture a storage win.

## Technical compatibility and remaining native risk

The two contradictory precision guards are experimental isolation guards, not
an established encoder/decoder incompatibility. `makeV3Selection` already chooses
encoder and support directories independently. The existing contracts are:

| Boundary | FP8 encoder | Historical PAL6 encoder |
|---|---|---|
| Mel input | FP16 [1,80,3000] | Same |
| Runtime challenge | FP16 [1,40] | FP16 [1,56] |
| Packet | FP16 [1,1920040] | FP16 [1,1920056] |
| Unpacked features | FP16 [1,1500,1280] | Same |
| Core ML decoder embeddings | FP16 [1,1280,1,1500] | Same |
| Decoder vocab | 51,865 | Same retained decoder contract |

The 56-value challenge response is checked and removed BEFORE the decoder sees
an independently owned hidden buffer. Existing code respects physical strides,
checks finite values and checks the bit-exact handoff. It does not feed a PAL6
packet directly to Core ML or invent an FP6 dtype. No frontend/tokenizer,
language detection, transcribe task, suppression, activation or decoding change
is needed. Same shape is necessary but not sufficient for speech quality: joint
weight errors can alter greedy token choices and require the combined corpus.

Admission rehashes both source and AOT bundles against their exact pinned
manifests, checks the recorded historical PAL6 sizes/fingerprints/native hashes,
checks frozen source controls, and rejects cross-encoder native identity overlap.
It verifies both support manifests and every inventoried file. Only common
speech-support files must be identical; the UNUSED Core ML AudioEncoder is
explicitly excluded, as in the existing decoder-only admission.

Apple says specializations are tied to hardware and OS, and OS updates invalidate
cached assets. The prior encoder run's OS is not established here as identical to
27.2/24B5084k. Reuse of its AOT source is justified; current runtime compatibility
is still a device gate. A missing current-OS cache is not a numerical failure or
a reason to rebuild weights. The existing serialized encoder-only probe may
specialize the unchanged artifact once, with persistent cache and identity checks.
Never delete caches or retry unchanged native failures.

Ownership remains sequential. No decoder is kept resident across a new encoder
scope, no second recognizer is added, and all in-flight native work must drain
before teardown/new preparation. The existing memory-warning latch is untouched.
The source guard changes do not establish that an old binary will run safely on
this OS. Native correctness, cancellation and current-OS resource evidence remain
required before any promotion.

## Not the last optimization avenue

The next cost to investigate after the precision decision is function loading and
when it occurs, not automatically fewer weight bits. A cached specialization is
not a loaded inference function. A separate future experiment could profile and
move safe preparation earlier in the existing user interaction, provided native
ownership and cancellation remain serialized and peak memory is qualified. Do not
retain a function across decoder work or implement that scheduling change during
this precision trial. The other measured opportunity is the post-ASR-to-audio
interval; attribute tutor, coordination and TTS work before claiming ASR can remove it.

## Implementation delivered

`DecoderTrialPolicy.swift` adds an explicit
`--coreai-w8-v3-combined=pal6-pal6` opt-in. PAL6/PAL6 without it still fails.
The generator updates the embedded app policy too; changing only the Tools copy
would have no runtime effect. Both App inputs are checked against their entire
374a7b3 Git blob hashes before a patch is generated. Existing FP8/PAL8 and FP8/PAL6
paths remain unchanged. Normal/default Talk and default prewarm=always are unchanged.

The native combined fixture-001 gate checks the existing recovery oracle; the
corpus still preserves every raw difference for review. No reference is edited.
`combined_trial.py` admits original artifacts without conversion or staging.
`analyze_combined_trial.py` supports combined, encoder-at-PAL6, decoder-at-PAL6 and
later fixed-artifact prewarm contrasts, with native two-turn and 22-file cohorts.
`analyze_combined_live.py` correlates actual ASR/audio IDs and refuses missing data.

Host tests compile and run the actual portable Swift policy and exercise
synthetic terminal/cache/ABI/cohort/phase-memory/quality/lifecycle-report rejection,
patch anchors, storage arithmetic and live correlation. Host evidence does not
claim a full Xcode build, actual artifact rehash, Core AI compilation, native
speech execution or on-phone performance. See the delivery test log for the final
count. The complete native artifact admission remains for the Mac with the assets.

The current conversation connector exposes 48 GitHub read/search actions and no
commit/push action. Plugin discovery confirmed the installed GitHub connector;
there is no GitHub CLI/authenticated checkout on this host. Remote writes were not
performed. The delivery includes a tested source patch generator and tooling patch
so the local agent can apply, test and then commit the actual results safely.
This limitation is not a need for access to the user's Mac to read the repository.

## Primary references and source anchors

- Repository source at 374a7b3: `App/LocalConversationEngine.swift`,
  `App/MuralApp.swift`, `Tools/CoreAI/W8IdentityVerifier.swift`,
  `Tools/CoreAI/DecoderTrialPolicy.swift`, `Tools/CoreAI/analyze_asr_trial.py`,
  `Tools/CoreAI/prepare_pal6_decoder_trial.py` and the committed real-results report.
- Apple AIModel: model is lightweight; functions own weights/intermediate buffers.
  https://developer.apple.com/documentation/coreai/aimodel
- Apple specialization/cache: device/OS dependency and explicit specialization.
  https://developer.apple.com/documentation/coreai/managing-model-specialization-and-caching
- Apple Core ML optimization overview: backend-dependent decompression tradeoffs.
  https://apple.github.io/coremltools/docs-guides/source/opt-overview.html
- Apple palettization performance: just-in-time decompression and LUT costs.
  https://apple.github.io/coremltools/docs-guides/source/opt-palettization-perf.html

These Apple explanations are general mechanisms, not a diagnosis of this specific
Core AI PAL6 AOT. Final disposition remains **bounded-trial GO, promotion NO-GO**.
