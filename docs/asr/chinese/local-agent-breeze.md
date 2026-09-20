# Local-agent prompt — Breeze only

Native execution has begun: see [the result](breeze-native-result-20260920.md).
The integration below was applied with its blob guard intact. The App actor is now
the single source; the Tools candidate/installer were removed after native build.
Do not rerun the historical installer step against an already integrated checkout.

Copy the text below to the AI agent on the development Mac. The user will operate
and review speech on the physical iPhone 17 devices. This is an execution prompt,
not a request to write another plan.

---

Work in `aidynamicsolutions/mural`, branch `mvp`. Read
`docs/asr/chinese/README.md`, `breeze-taiwan-plan.md`, `host-checks.md`, and the current
`docs/asr/README.md`. Preserve user changes, signing, bundle ID, stores, existing
models, cache safety checks and PhoWhisper FP8/PAL8 Talk. No force push, cache deletion,
cloud fallback, paid job, FireRed implementation or production model promotion.

This commit contains tested Python helpers, a Swift recognizer candidate and a
prepared patch installer. It is NOT a native-built or phone-qualified integration.
Your remaining implementation is model conversion, applying/rebasing that small
patch, project registration and any narrow SDK fixes, followed by physical tests.

1. Record branch/head, clean/dirty state, Mac/Xcode/SDK, resolved package revisions,
   and connected physical device models/OS versions. Do not reset a dirty checkout.
   Run `python3 -m unittest discover -s Tools/ChineseASR -p 'test_*.py' -v` and the
   repository's existing host/Core/ASR gates. Distinguish those from native builds.
2. Resolve and download an immutable full revision of the official
   `MediaTek-Research/Breeze-ASR-25` into a private local work directory, with matching
   source weights, processor, tokenizer, generation config and notices. Use no
   community compiled weights as a substitute. Record provenance. Keep all artifacts
   and recordings out of Git and do not upload anything to a model hub.
3. Copy `taiwan-smoke.template.json` outside Git. Help the user record the prompts,
   plus spontaneous mixed speech, or reuse permitted existing Taiwan recordings.
   Obtain actual human-checked references before viewing predictions. The app does
   not normally save raw audio; use the existing local fixture workflow or an explicit
   temporary recording tool, not a silent change to production audio retention.
   Validate mono 16 kHz PCM16 WAVs with `evaluate.py check-audio`.
4. Run `run_reference.py breeze` with explicit local paths and the full revision.
   Start with a few clips before the full set. Verify automatic language/transcribe
   behavior; don't inherit the model config's old English-only forced prefix. Freeze
   the reference decoding settings and report failures rather than replacing speech
   with translations or correcting the user's grammar.
5. Inspect the installed WhisperKitTools help and existing conversion utilities.
   Export the exact source into matching 80-mel Core ML assets, establish host
   correctness, then create ONE PAL8 encoder/decoder phone candidate. Inspect actual
   compression and model I/O, not just filenames. Keep app dependency pins. Do not
   repeat the previously warning-prone eager FP16 phone path or PAL4/PAL6 experiments.
   Package using `prepare_breeze.py --source ... --compiled ... --revision ...
   --output ...`, preserving its independently recorded manifest SHA-256.
6. Run `python3 Tools/ChineseASR/install_breeze_probe.py` and review the diff before
   `--apply`. If its source-blob check fails, rebase only its documented integration
   changes onto the actual current engine; do not disable the guard or reset source.
   Inspect and use `scripts/generate_project.py` to register the new App file. Review
   generated changes. Check the new enum case in every exhaustive switch and the
   existing ASR probe picker. Build Release with Xcode and retain default Talk behavior.
   Confirm single-owner cancellation and the memory-warning latch cover Breeze.
7. Stage the verified bundle at Application Support/BreezeASR25/breeze-asr25-pal8-v1
   on one phone. Supply exactly one `--breeze-manifest-sha256=...` launch argument.
   Use actual local device-tool help/identifiers; do not guess a UDID or use a simulator
   result as physical evidence. Start with 3–10-second turns in the Breeze probe.
   For matched audio, use the existing local file-replay harness where possible;
   otherwise add only a small development-only caller of this actor for local fixtures.
   Keep full replay output private, and do not introduce a production recording store.
8. Test both switching directions, all-English, Taiwan names/vocabulary, Traditional
   characters, subsecond replies, silence, a near-30-second turn, offline restart,
   End during preparation/decoding, attempted restart, interruptions/backgrounding,
   and at least 20 warm turns. Stop on a native crash, memory warning or stale result;
   do not retry the same failing graph. Measure UI Send-to-final separately from decode
   wall time, and peak footprint separately from phase samples. Repeat on other
   physical iPhone 17s only after the first bounded run is safe.
9. Use `evaluate.py score` for complete matched predictions. Review English preservation
   and script errors with the user independently of MER. Do not edit references after
   seeing a prediction. Label single-speaker smoke limitations and untested cases.
10. Commit only reviewed source changes and a concise sanitized result, fast-forward
    on the current branch. Record actual tested source SHA, model/source/export/runtime
    pins, Xcode/phone/OS, test counts, preparation/first/warm latency, memory/thermal
    evidence, accuracy differences, lifecycle results and remaining blockers. Remove
    the duplicated Tools candidate/installer only when the App implementation becomes
    the single maintained source; do not maintain two diverging recognizers. Leave
    `prepareConversation()` on PhoWhisper until a separate acceptance decision.

Perform these actions rather than stopping at another planning document. Report
conversion/build/device blockers precisely. Never label an unrun step as passed.
