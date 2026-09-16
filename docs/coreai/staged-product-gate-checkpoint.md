# Staged hybrid full product-gate checkpoint

Status: **BLOCKED: unresolved parity discrepancy and failed fresh baseline comparator. Do not integrate into normal Talk.**

The earlier one/two/ten-turn fixture-001 memory milestone remains valid. This checkpoint expands the staged probe to the frozen 22-file corpus without changing weights, frontend, tokenizer, decoding policy or expected text.

## New runs

Both ran on the same installed Debug build, iPhone 17 / iPhone18,3, h18p, bundle `com.kevintruong.mural.dev`. Each started in a fresh process. The bounded collector retrieved reports and terminated its owned probe process. No cache invalidation or other cache repair occurred in this gate attempt.

### Fresh all-Core-ML comparator: failed before transcription

Run `63A3B247-0F09-491F-BDEF-27CAE83AB5D4`, mode baseline, corpus requested.

- Preparation: 171.817 seconds, including 166.338 seconds prewarm.
- Sampled footprint after loading: 3,337,767,112 bytes.
- One iOS memory warning, independently present in the scoped system log (PID 44895).
- Warning guard stopped the run before any transcript: 0/22 reference results.
- Teardown sampled footprint: 158,828,720 bytes.
- Thermal samples moved from nominal to fair.

This is a failed comparator run, not a demonstrated staged-path memory failure. It cannot supply same-phone corpus parity or a controlled performance baseline. The baseline was not retried blindly or altered to manufacture a passing comparison.

### Staged corpus: completed 22/22 without warnings

Run `0E51E1E5-CA72-4999-B714-373F2DA67269`, mode staged, corpus requested.

- All 22 frozen audio files completed with terminal status complete.
- Zero recorded memory warnings in both report and scoped system log.
- Highest event-sampled footprint: **2,095,712,336 bytes**.
- Maximum sampled thermal state: fair.
- This includes the longer fixture 017; completion is not equivalent to reference parity.

The staged run was useful independently of the comparator failure: it broadened memory evidence from repeated fixture 001 to all 22 distinct fixtures. No later lifecycle or rollout gate was credited from this result.

## Historical-reference comparison: 21/22 normalized matches

Located the saved accepted FP16 Mac reference:

`/Users/tiger/tmp/mural-asr-benchmark/phowhisper-conversion/coreml-pinned-runtime.jsonl`

All 22 source WAV hashes were checked against the corresponding staged phone audio hashes. Comparison uses the existing benchmark's normalization function: NFC, lowercase, punctuation-to-space and whitespace collapse only. Accents and lexical content are retained.

- Normalized text matches: **21/22**.
- Language matches: 22/22.
- Fixture `007.wav` differs:

```
Historical FP16: Yesterday I went to seal tea. How do I say that in English.
Staged iPhone:   Yesterday I went to seoul tea. How do I say that in English.
```

The difference remains after the accepted normalization. No punctuation, accents, prompt, suppression, threshold or expected text was adjusted to remove it. Both renderings may reflect the pre-existing recognition difficulty with this recording; that does not make them an exact parity match.

**Attribution limit:** the saved reference is from a Mac, not this fresh iPhone build. Because the current phone baseline stopped before transcription, this does not isolate Core AI as the cause of the difference. It is a concrete historical-reference discrepancy and an unmet exact-match prerequisite, not proof of a same-device hybrid regression.

The historical reference does not contain complete comparable generated-token/logit data for this gate. Do not claim those comparisons passed.

## Gate disposition

| Requirement | Disposition |
|---|---|
| Staged short fixture one/two/ten-turn memory milestone | Passed earlier, limited scope |
| Staged 22-file completion and observed memory envelope | Passed this Debug run, zero warnings |
| Same-device 22/22 baseline/staged parity | Blocked: reference run failed before transcription |
| Saved accepted-reference 22/22 normalized parity | Not met: 21/22, fixture 007 differs |
| Silence, Yes, No | Not run: progression stopped at parity/comparator prerequisites |
| Preparation/encoder/decoder cancellation with exact recovery | Not run for staged mode; still unqualified |
| Background/foreground, relaunch and persistence | Not run for staged mode |
| Offline launch/transcription | Not run with network disabled |
| Tutor/TTS coexistence and sustained thermal envelope | Not run |
| Controlled fresh/cached Release performance and subsequent-turn latency | Not run; failed comparator is not a timing distribution |
| Fresh-install-like container, rollback and supported device matrix | Not run |
| Normal Talk integration / release | Not authorized by passing evidence; unchanged |

Stopping these downstream gates is deliberate, not treating them as passes. The broad product gate remains closed.

## Harness and validation

- Staged corpus selection now accepts the existing frozen, hash-verified `001.wav` through `022.wav` set. Combining corpus mode with an explicit turn count is rejected.
- Fixture-001 self-check remains; other corpus outputs are preserved for external comparison rather than forced to fixture-001 text.
- Discovered that the old probe normalizer additionally removed symbols/tags and applied compatibility normalization. Corrected it to the established corpus rules, with an executable Unicode/lexical regression check. Independent comparison confirmed that this reporting-only correction changes none of the 22 saved staged normalized outputs and does not remove the 007 discrepancy.
- Product-config/parity/normalization tests passed. Device Debug build passed before the runs and again after the reporting-only normalization correction. The final correction was not reinstalled or used to repeat inference; its unchanged result for all saved corpus text was verified independently.
- `git diff --check` passed. No commit or publication. Existing staged/unstaged user work is preserved.

## Evidence

`.build/verification/coreai-staged-product-gate/`

- `baseline/` and `staged/`: launch commands, system logs, pointers, terminal reports, events and transcripts.
- `historical-reference-comparison.json`: per-file raw/normalized comparison, verified audio hashes and source provenance hashes.
- `historical-coreml-reference.jsonl`: preserved reference copy.
- `compare-reference.py`: rerunnable saved-evidence comparison using the existing normalizer.
- `run-corpus.py`: bounded collector, with no cache edits or automatic inference retry.
- Build/install logs, focused tests and source hash.

## Next focused investigation

Before reopening downstream gates, resolve the fixture-007 discrepancy using a safe same-device reference strategy. First inspect why the comparator's loading footprint reached 3.34 GB; do not repeat a warning-producing run unchanged. A separately staged Core ML encoder plus the same owned-embedding/WhisperKit decoder boundary could help isolate encoder differences without simultaneous model residency, but it would be a diagnostic reference, not automatically the normal-Talk baseline. Preserve the old outputs and all failures. Do not change the accepted transcript or relax parity to get a pass.
