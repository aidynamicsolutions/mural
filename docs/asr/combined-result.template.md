# Combined PAL6 qualification - REAL sanitized result

Date / exact source commit / local diff SHA / executable SHA:
Device / OS build / h18p / Xcode / Swift:
Status: [native-only / corpus / live / lifecycle / blocked]. Do not mark unrun gates passed.

## Exact artifact identity

A = FP8 encoder + PAL8 decoder.
B = FP8 encoder + PAL6 decoder.
C = PAL6 encoder + PAL6 decoder.
Record each manifest, source/AOT fingerprint, native hash, used-decoder inventory,
source/AOT/support bytes, runtime named entrypoint and current-OS cache result.
No private data uploads. No changes to defaults, VAD, warning latches or caches.

## Native fixture-001 gate

Record two turns per arm, run IDs, exact agreement, same-arm hidden repeatability,
packet ABI/challenges, cache/function identity, terminal/drained status and warnings.
A passing two-turn gate is not a performance distribution or a speech corpus pass.

## Paired corpus

Record triplet order, actual launch arguments, source/executable/diff hashes,
process sessions, fixture/mel hashes, retained-cache and thermal conditions.
21 scored and 017 diagnostic. Preserve every raw/token/language difference.
Report C vs A AND C vs B. State the metric aggregation explicitly (mean of which
samples, percent change of which means/medians). Do not pool repeated fixtures as
independent device experiments. Separate first turn, warm turns and diagnostic.

| metric / units | A | B | C | C-A | C-B |
|---|---:|---:|---:|---:|---:|
| AOT + used decoder logical bytes | | | | | |
| native encoder seconds | | | | | |
| encoder function load seconds | | | | | |
| validation/copy seconds | | | | | |
| decoder prewarm / load seconds | | | | | |
| decoder seconds | | | | | |
| full staged harness seconds (NOT UI Send) | | | | | |
| encoder-response footprint B | | | | | |
| post-release footprint B | | | | | |
| decoder-loaded footprint B | | | | | |
| decoder text-end footprint B | | | | | |
| process-lifetime RSS peak B | | | | | |
| warnings / errors | | | | | |

## Real app / human feedback / lifecycle

Keep app-monotonic Send-to-final and ID-correlated Send-to-first-tutor-audio
separate. Give count, first, warm, mean, median, range and any incomplete turns.
Record first attempts AND retries, relevant actual speech/display differences,
perceived waiting/heat, offline/fresh-conversation/cancellation outcomes.
No subtraction of interview delay. No ground-truth guarantee from control agreement.

## Failures, exclusions, uncertainty and local evidence

Attempt ledger, unmeasured items, hashes of local evidence and clean capture teardown.
State whether a precision review occurred before any prewarm policy comparison.
No native crash or memory warning is averaged away. No raw private files attached.

## Disposition

Choose one factual result and explain the incremental C-versus-B tradeoff.
Normal/default Talk is unchanged. Record final branch head and fast-forward-only
publication evidence, or honestly state that changes remain local/unpushed.
