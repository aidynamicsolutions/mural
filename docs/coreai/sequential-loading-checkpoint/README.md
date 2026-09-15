# Core AI sequential-loading evidence

Start with [report.md](report.md).

This directory is a commit-ready, sanitized copy of the local evidence for HEAD
`865c3744a39954db0a165b2f7d85561e1a2f7800` plus the accompanying working-tree
changes. It does not establish transcript parity.

## Main finding

The encoder produces finite FP16 output. The decoder completes language detection
but aborts in the ANE runtime before completing the first transcript, even in a
fresh process that never loaded the encoder. Encoder/decoder co-residency is not
the sole cause. The full 22-file corpus was not started after that failure.

## Files

- [report.md](report.md): implementation, commands, measurements, outcome and limits.
- [Mural-sequential-crash.json](Mural-sequential-crash.json): sanitized in-process crash extract.
- [Mural-decoder-only-crash.json](Mural-decoder-only-crash.json): sanitized fresh-process crash extract.
- [runtime.txt](runtime.txt): selected sequential memory/timing/error log lines.
- [runtime-decode-only.txt](runtime-decode-only.txt): selected fresh-process log lines.
- [coreai-asr-probe.json](coreai-asr-probe.json): sequential preparation-only report.
- [encode-only.json](encode-only.json): successful checkpoint creation, not a transcript.
- [decode-only.json](decode-only.json): fresh-process preparation-only report.
- [encoder-checkpoint.json](encoder-checkpoint.json): saved tensor metadata, size and SHA256.
- [checks.txt](checks.txt): build and focused-check results.

Crash extracts retain exception/termination details, symbolic stacks for all
threads, image names, and VM summaries. Registers, identifiers, UUIDs and private
paths are omitted. Each extract records the SHA256 of its original IPS file.
Runtime logs are filtered extracts, not complete logs. Missing messages cannot
be treated as proof that no other events occurred.

Raw evidence remains in ignored `.build/verification/coreai-sequential/` on the
original Mac. Audio fixtures, encoder tensor bytes, model assets, full device
inventories and raw logs are intentionally not included here.

## Earlier attempts, summarized for the next agent

Before this experiment, the Float32-only mel-reader bug was fixed. AOT GPU
preference alone still entered the failing ANE path. Matching GPU preference at
runtime plus a frequent-reshape decoder variant then aborted in MPSGraph resource
allocation during preparation. Those unsuccessful runtime changes were removed,
and the original AOT pair restored before this sequential experiment. Detailed
raw evidence for those earlier attempts remains local under
`.build/verification/coreai-mel-fix/`; it is not included in this evidence bundle.

Do not claim a decoder numerical mismatch or a guaranteed fix from these results.
No completed transcript exists. No weight/precision/tokenizer/threshold changes,
KV cache, or normal-conversation integration have been made.
