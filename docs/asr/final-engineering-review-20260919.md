# ASR engineering review - 2026-09-19

## Disposition and delivery

Retain **packed-v3 FP8 Core AI encoder + PAL8 Core ML decoder**, `prewarm=always`.
No finding invalidates that precision decision. No model conversion, PAL4/PAL6
campaign, default promotion, lifecycle redesign or silence/VAD work was performed.

Reviewed remote: `65c96f6df18b99eee3739081d064c74b2b3ba326`, branch `mvp`.
The connector host was Linux, not the developer's Mac. Its GitHub connection
exposed reads but no file/tree/commit/ref write actions, despite repository push
permission. CLI/network access did not provide an alternative. **The fixes were
prepared and host-tested, not committed or pushed by this review.** Apply them
on the current remote parent, run the Mac gates, and publish fast-forward only.
The final phone result must identify the actual tested source and ending SHA.

## Review coverage

The comparison covered all 17 commits from `6e1e9f0` through the reviewed head,
including all eight implementation commits and both temporary blocker commits.
The entire `LocalConversationEngine.swift` was retrieved and Git-blob verified;
selection, probe/verifier, exporter contracts, project settings, coordinator End,
product ownership/drain/timing paths and the relevant qualification reports were
inspected. This was not an exhaustive execution of every utility in the tree,
a full Apple build, a remeasurement of private evidence, or a line-by-line audit
of unrelated product features. `mvp_plan.md` retains unrelated historical work.

| Commits | Evolution / retained rationale |
|---|---|
| `6e1e9f0`, `2957fb9`, `f51fb58`, `ed673ec` | Research order moved to the retained bilingual model, PAL8, then a supported FP8/INT8 encoder experiment; old work orders are superseded. |
| `4e80f46`, `ab93c12`, `f5dbbf9` | Cache-alias blocker, independent identities and bounded probe safety. Do not revert the safeguards because commit names say temporary. |
| `0206224`, `afa5eee` | Runtime FP16 challenge/response and packed-v3 product selection replaced constant-marker qualification. |
| `b806b6c`, `eb26759` | Audited PAL6 encoder tooling/qualification and separate native versus staged timers. |
| `374a7b3`, `0218a01` | Isolated PAL6 decoder, guarded combined trial, opt-in prewarm policy and ID-correlated first audio. |
| `fa30fc2`, `2420c47`, `9f37655`, `65c96f6` | PAL4 resource result followed by repeated live PAL4/PAL8 assessment and the FP8/PAL8 preference. |

## Findings and narrow fixes

1. **Release isolation.** `makeV3Selection` referenced `W8TinyProbe`, whose type
   is absent outside Debug/W8 builds. A portable compile of the real selector
   reproduced the missing-symbol error for ordinary and Talk-only Release.
   Guard the helper with `MURAL_COREAI_W8`, matching its existing guarded caller.
   Do not compile the probe into normal Release to hide the problem.
2. **Legacy admission regression.** The v3 refactor reduced `verifiedSelection`
   to resolution alone, losing the legacy h18p and pinned encoder fingerprint
   checks. Restore them only when `selection.v3 == nil`. The accepted FP8/PAL8
   manifest path already had its own checks; the finding does not discredit its
   recorded results. Wrong architecture and changed fingerprint now reject.
3. **V3 fingerprint consistency.** The exporter and tiny probe hash all bundle
   entries; the Talk helper skipped hidden entries. Size checks are not the same
   contract: an empty hidden entry can evade a size-only check. Add an explicit
   complete-inventory option for v3, recursively propagated. Preserve the old
   visible-only legacy digest convention and every accepted pin. This closes a
   source-level verification gap; no actual misidentified phone artifact was found.
4. **Misleading diagnostics.** Verification events named FP16 even when PAL8 was
   selected, preparation text ignored greeting prewarm, and two staged timing
   names implied broader scopes. Use the verified support name, describe prewarm,
   and append scope labels without changing timer boundaries or legacy numeric
   keys. The live decode wall interval includes replay/transcription; the staged
   interval ends after unload but does not start at UI Send.
5. **Current documentation.** Remove the fictional PAL16 comparison label and
   the FP16-reference row's incorrect PAL8 decoder identification. Remove the
   unsupported FP16 quality-ceiling claim. Keep the historical 4.36-second replay
   median outside the live Send-to-final-mean table. Preserve all measured values.
   The ASR index and plan entry point now identify the settled choice and supersede
   old experiment instructions; historical qualification evidence remains intact.

Regression coverage lives in `Tools/CoreAI/test_asr_final_review.py`. The existing
product-residency test needs only the matching optional fingerprint parameter in
its test double. No provider framework, extra owner, new model, dependency,
source/AOT pin, decoder default or warning-recovery policy was introduced.

## Selection, identity and ownership

Normal Release Talk remains eager WhisperKit/Core ML. FP8/PAL8 needs both
`MURAL_COREAI_TALK` and `MURAL_COREAI_W8` plus explicit encoder and decoder flags;
omitting the decoder flag selects FP16. Effective private Mac build overrides
and the installed process were unavailable here. See [the current index](README.md).

The FP8 manifest pin is
`73b160308d7a0d591ce7645eb19c6710f3a9dd301548d0cbb13129c3ab929e13`;
PAL8 support is
`430c6b5454ac44e35e69f007683477b2064cf4f92af1011d65485017c0607336`.
The recorded FP8 AOT fingerprint is
`c5c7d3264c7256fc50c37e4e4a3471ec69c278397f1887cca65b96a6ee796c65`.
The [native result](combined-pal6-result-20260918.md) records the source/AOT native
hashes and byte inventories; they must be reverified locally, not assumed installed.

The named FP8 function uses FP16 input `[1,80,3000]`, challenge `[1,40]`, packed
output `[1,1920040]`, and 1,920,000 finite FP16 hidden values. The bridge preserves
`[1,1500,1280]` to `[1,1280,1,1500]`. The model must expose the exact named function;
v3 does not fall back to `main`. Challenge/response protects the known runtime
alias/ABI failure modes, not cryptographic attestation of every cached weight.

The inspected live path retains its one recognizer/task owner, generation checks,
awaited speculative prewarm, awaited encoder scope, and decoder unload on success
and error. End cancels presentation/application of stale work while native work
must return before teardown/recovery. The warning latch remains sticky. No new
race was established in these paths; host checks do not prove physical GPU
retirement or all scheduling interleavings. Historical explicit PAL4/PAL6 policies
and immutable builders remain forensic/regression tools, not production defaults.

## Tests and limits

| Check | Connector-host result |
|---|---|
| Existing `test_w8_runtime_identity` | 8 passed; real CPU Torch capture plus portable Swift identity checks. |
| New `test_asr_final_review` | 8 passed; real selector build matrix, legacy rejection, actual 20-pair decoder/combined policy, static transport/measurement/hash-contract checks. |
| Existing Talk opt-in script | Six cases passed through a host-only `xcrun` dispatch adapter. Linux lacks Core AI; the new build matrix separately reproduces the missing-type boundary. |
| Existing product config/parity script | 19 accepted configurations and 24 rejection cases passed using retrieved production excerpts and a host-only Linux URL adapter. This is not native residency proof. |
| Cached-load, Core ML hybrid/layout, bounded hash-memory tests | Inspected; Apple-specific versions not run on Linux. |
| Complete legacy/packed-v3 product, PAL6, decoder/combined report-analysis suites and full core `swift test` | Not run as complete suites on this partial snapshot; required Mac preflight. Actual runtime identity and decoder policy subsets above did run. |
| Xcode Release, Core AI AOT/native execution, iPhone lifecycle/audio/heat | Not run here. |

The new Release and legacy-admission tests reproduced failures before the fixes.
The hidden-inventory regression checks the Swift source contract, not a live
CryptoKit filesystem traversal. Test counts must not be converted into Apple
execution claims. The deliverable contains the exact patch and sanitized host logs;
no private `.build/verification` material was read, modified or published.

## Remaining closure gates

Land the reviewed changes on the current parent; complete Mac host/Release gates;
then run [one final phone validation](final-fp8-pal8-validation.md). The selected
precision is suitable for that bounded validation, not certified by this Linux
review alone. Known `siêu thị` errors and the small single-speaker live sample
remain accuracy limits. No universal accuracy, cold-cache, energy, long-soak or
production-default claim is made. Silence/VAD remains out of scope.
