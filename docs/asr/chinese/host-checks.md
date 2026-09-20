# Preparation checks and limits

Initial review used `6867ff912c7eb940ec444ae836adafaa46d3d7cd`. Before publication,
`mvp` advanced to `cfa0999a0738c7a28cc5879b041c1f0e12a0218f`. The engine changes
for that commit and its new Core speech policy were inspected; the integration
anchors are unchanged and the installer pin now matches engine blob
`2162ca8d88a5dda8a51487ddd585e4129a6474b3`. Its silence-compaction changes are preserved.
The connector host is Linux, not the development Mac or a physical iPhone.

| Check | Result |
|---|---|
| `python3 -m unittest discover -s Tools/ChineseASR -p 'test_*.py' -v` | 45 passed |
| Python helper syntax compilation and CLI help | Passed |
| `swiftc -frontend -parse Tools/ChineseASR/BreezeEnglishRecognizer.swift` | Passed syntax parsing only |
| Both authored recording-template manifests | 16 entries each; schema valid; no recordings supplied |
| Existing full `swift test`, repository ASR suites, Xcode Release build | Not run here |
| Complete app-source patch application | Not run here; installer requires exact reviewed Git blob before writing |
| Breeze source inference, conversion, actual PAL8/compiled I/O inspection | Not run here |
| FireRed official/ONNX inference, native library or Swift bridge | Not run here |
| Physical phone, acoustic quality, memory/thermal, latency or lifecycle | Not run here |

The 45 tests comprise 31 evaluation/audio validation tests and 14 packaging/patch
preparation tests. Packaging fixtures contain deliberate mock bytes, not real model
weights. Integration tests use the exact retrieved replacement anchors assembled
into a synthetic source string, not the complete app or an Apple SDK. They check
missing/duplicate anchors, repeated application rejection and owner handoff edits.
They do not prove native build correctness, scheduling, model behavior or conversion.

Accuracy tests cover mixed Han/English tokenization, script preservation, translations
being penalized, explicit blank output, silence, token-weighted totals, strict corpus
IDs, incomplete/failed results, audio format/duration/truncation, unsafe paths and
preserving existing result files. No test result is evidence that either recognizer
understands Chinese correctly.

The installer is intentionally outside the app build. It preserves normal Talk and
requires a native build after application. The native candidate's current PAL8 eager
loading is a bounded experiment, not a phone-memory claim. Native agent fixes must
remain narrow and be recorded with the actual tested source identity.

Publish only a sanitized result: source/build/model/runtime identities, counts,
aggregate accuracy, explicit error categories, timing definitions, memory/thermal
observations and pass/fail/unrun cases. Keep real audio, detailed transcripts, full
logs, personal paths, device identifiers and private model artifacts local.
