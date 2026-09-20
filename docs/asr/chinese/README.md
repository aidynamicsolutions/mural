# Chinese-English ASR: two separate work items

## Native execution update

Breeze is integrated in `App/BreezeEnglishRecognizer.swift` and registered in the
Xcode project. The guarded installer was reviewed and applied on its exact pinned
engine; its duplicate Tools candidate and installer were then removed. Use the
existing Speech recognition probe, not the historical installer command below.
See [native qualification result](breeze-native-result-20260920.md) for actual
source/model identities, conversion/build evidence and unrun device/accuracy gates.
The preparation inventory below records the original handoff, not current status.

FireRedASR2-AED is now implemented as a compile-time opt-in probe, **not qualified**.
Its exact-v2 native file gate passed on iPhone 17, then live testing stopped on an
iOS memory warning while loaded/idle. Two short Yes attempts were also rejected
by the unchanged VAD gate. The ordinary Mural build was restored; no ASR default
or script/case normalization changed. See [FireRed qualification result](firered-aed-qualification.md)
for exact identities, measured timings/memory, human observations and unrun gates.
Do not retry that resource configuration merely to finish the test matrix.

Initial architecture review: `mvp` at `6867ff912c7eb940ec444ae836adafaa46d3d7cd`.
The branch advanced to `cfa0999a0738c7a28cc5879b041c1f0e12a0218f` during preparation.
Its engine diff and new speech policy were reviewed; the patch pin now targets that
engine. This delivery preserves the new silence-trimming work without modifying it.

Start with [Breeze for Taiwan Mandarin](breeze-taiwan-plan.md). Run
[the Breeze local-agent prompt](local-agent-breeze.md) on the development Mac.
Only after recording that result, start [FireRedASR2-AED](firered-aed-plan.md)
with [its separate prompt](local-agent-firered.md). Neither is a new default yet.

## What is delivered

| Item | Status |
|---|---|
| Two bounded implementation/qualification plans and agent prompts | Written |
| Local corpus validation, mixed-error scoring, source packaging, replay helpers | Implemented; standard-library tests run |
| Breeze Swift recognizer candidate | Written; Swift syntax parsed, not Apple-SDK type-checked |
| Small patch installer for the existing ASR probe | Written; anchor transformations tested; not applied to the complete app here |
| Breeze Core ML export, Xcode registration/build, device installation | Requires the Mac; not performed here |
| FireRed AED iOS bridge and app integration | Planned; not implemented or qualified |
| Physical iPhone 17 recognition, latency, memory, offline/lifecycle results | Not measured here |

The candidate lives under `Tools/ChineseASR`, outside the app target. The installer
adds it to the existing probe only after local review. This keeps the accepted
PhoWhisper FP8/PAL8 Talk path, asset pins, caches and history untouched. The
remaining work is **not testing alone**: native conversion, applying/building the
prepared Breeze integration, and FireRed's native bridge still require local work.

## Small implementation, not a provider framework

Use the current capture, sample-rate conversion, task ownership, cancellation,
VAD policy and result presentation. One model owns a whole mixed-language turn;
do not switch engines when the speaker switches languages. Use one active ASR
model at a time. No registry, automatic locale detection, new server, cloud
fallback, training pipeline, or generalized download manager is needed.

Files in `Tools/ChineseASR`:

- `BreezeEnglishRecognizer.swift`: candidate local WhisperKit actor.
- `install_breeze_probe.py`: dry-run-first patch against the exact reviewed engine.
- `prepare_breeze.py`: package an already converted PAL8 model; not a converter.
- `run_reference.py`: local Breeze/PyTorch or FireRed/AED-ONNX replay; inference untested here.
- `evaluate.py`, `test_evaluate.py`, `test_prepare.py`: local checks and tests.

## Evidence and recording rules

The two `*.template.json` files are **authored recording scripts**, not an actual
corpus or measured ground truth. Copy a template outside the repository. Record
mono 16 kHz PCM16 WAVs of at most 30 seconds, replace anonymous speaker labels, and
correct each reference to the words actually spoken without looking at ASR output.
Keep raw recordings, detailed transcripts and complete device logs local. Do not
upload them to a model hub or commit them. User recordings establish a personal
smoke result; native-speaker and unseen spontaneous speech are separate coverage.

Example commands, with private paths supplied by the local agent:

```sh
python3 -m unittest discover -s Tools/ChineseASR -p 'test_*.py' -v
python3 Tools/ChineseASR/evaluate.py check-audio "$CORPUS" "$AUDIO_ROOT" --output "$NEW_AUDIO_REPORT"
python3 Tools/ChineseASR/evaluate.py score "$CORPUS" "$PREDICTIONS" --output "$NEW_SCORE"
```

Predictions use `mural.chinese-asr.predictions.v1` with a `predictions` array of
`{"id":"tw01","text":"..."}`. Missing, duplicate, extra, failed or explicitly
incomplete results are rejected. An explicit empty transcript is scored as
missing speech, not silently discarded. Reports omit transcript text unless
`--include-text` is explicitly requested for private local review.

The declared local MER tokenization is one Han character or one word, with NFC,
case folding and punctuation separation. It does not convert Simplified to
Traditional characters, translate words or repair learner grammar. It is not a
reproduction of a publisher benchmark. Review English preservation, proper names,
script errors, silence and UX latency separately. No automatic promotion follows
from a numeric score. See [host check limits](host-checks.md).
