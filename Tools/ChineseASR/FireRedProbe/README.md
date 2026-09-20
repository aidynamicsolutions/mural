# FireRedASR2-AED native file probe

Development-only native iPhone file replay, either standalone or hosted by an
explicit Mural build variant. No capture, tutor, network client, ASR-default
change, or custom decoder. **Do not add live capture
until the physical file probe passes.** See the [qualification result](../../../docs/asr/chinese/firered-aed-qualification.md).

`pin.json` identifies the inspected official checkpoint, conversion recipe,
released INT8 bytes, and maintained runtime. These are separate identities:
the release does not contain a reproducible producer-build attestation. Both
INT8 graphs are self-contained; inspection found no external tensor files.

## Prepared local layout

Run from the merged `mvp` checkout. The completed Breeze work is preserved:

```sh
export MURAL_ROOT="$PWD"
export F="$PWD/.build/firered"
export E="$PWD/.build/verification/firered-aed"
mkdir -p "$F" "$E"
```

The preparation run already populated:

- `$F/sherpa-onnx`: source `a5b4a944c5186a68bcdc0ac3011e4c541781ac84`.
- `$F/ort-ios/onnxruntime.xcframework`: maintained static iOS ORT 1.28.2.
- `$F/ios-build/lib`: Release device-arm64 sherpa static libraries.
- `$F/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26`: pinned AED models and upstream examples.
- `$F/official`, `$F/official-model`, `$F/conversion`: separately pinned source/checkpoint/recipe.
- `$F/venv`: source-built sherpa Python runtime, ONNX inspection, official PyTorch replay.
- `$F/notices`: upstream license/notice texts for the local runtime build.
- `$E`: private raw metadata, build logs, hashes, and replay reports. Do not commit.

To recover missing dependencies, use only these pinned sources:

```sh
curl -fL --max-time 120 https://api.github.com/repos/k2-fsa/sherpa-onnx/tarball/a5b4a944c5186a68bcdc0ac3011e4c541781ac84 -o "$F/sherpa-source.tar.gz"
mkdir -p "$F/sherpa-onnx"
tar -xzf "$F/sherpa-source.tar.gz" -C "$F/sherpa-onnx" --strip-components=1
curl -fL --max-time 120 https://github.com/csukuangfj/onnxruntime-libs/releases/download/v1.28.2/onnxruntime-ios-static-xcframework-1.28.2.xcframework.zip -o "$F/ort-ios.zip"
echo "2c2299acbb461d26d4bac4bc85985d40e7c7177ed6072703ae0846d88b0b4599  $F/ort-ios.zip" | shasum -a 256 -c -
mkdir -p "$F/ort-ios"
unzip -n "$F/ort-ios.zip" -d "$F/ort-ios"
curl -fL --max-time 300 https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26.tar.bz2 -o "$F/model.tar.bz2"
echo "43015b3f1643a5688b4821e8ed323473d38b798c4ec291471fe00df1bcfc4f1c  $F/model.tar.bz2" | shasum -a 256 -c -
tar -xjf "$F/model.tar.bz2" -C "$F"
```

Never extract over a source tree another build is using. Keep failed outputs.

## Maintained iOS build

This is the OS64 CMake path from the pinned upstream `build-ios-no-tts.sh`,
without its unused simulator slices or XCFramework packaging. No upstream
implementation or decoder modification. CPU, one thread, greedy search, batch 1.
The runtime handles waveform scaling, fbank, CMVN and dynamic decoder caches.

```sh
export SHERPA_ONNXRUNTIME_LIB_DIR="$F/ort-ios/onnxruntime.xcframework/ios-arm64"
export SHERPA_ONNXRUNTIME_INCLUDE_DIR="$SHERPA_ONNXRUNTIME_LIB_DIR/onnxruntime.framework/Headers"
cmake -S "$F/sherpa-onnx" -B "$F/ios-build" \
  -DCMAKE_TOOLCHAIN_FILE="$F/sherpa-onnx/toolchains/ios.toolchain.cmake" \
  -DPLATFORM=OS64 -DENABLE_BITCODE=0 -DENABLE_ARC=1 -DENABLE_VISIBILITY=0 \
  -DDEPLOYMENT_TARGET=17.0 -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DSHERPA_ONNX_ENABLE_TTS=OFF -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
  -DSHERPA_ONNX_ENABLE_BINARY=OFF -DSHERPA_ONNX_ENABLE_TESTS=OFF \
  -DSHERPA_ONNX_ENABLE_CHECK=OFF -DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF \
  -DSHERPA_ONNX_ENABLE_JNI=OFF -DSHERPA_ONNX_ENABLE_C_API=ON \
  -DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF -DSHERPA_ONNX_BUILD_C_API_EXAMPLES=OFF
cmake --build "$F/ios-build" --target sherpa-onnx-c-api -j 4
```

XcodeGen generates **only this probe** under ignored `.build/`; never regenerate
Mural's project. Supply the existing private signing config without copying its
contents into source. `--project-root` is needed for correct generated references.

```sh
mkdir -p "$F/app-project"
xcodegen generate --spec Tools/ChineseASR/FireRedProbe/project.yml \
  --project "$F/app-project" --project-root "$F/app-project"
: "${SIGNING_CONFIG:?Path to the existing private Config/Local.xcconfig}"
xcodebuild -project "$F/app-project/FireRedProbe.xcodeproj" -scheme FireRedProbe \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$F/probe-derived" -xcconfig "$SIGNING_CONFIG" \
  MURAL_ROOT="$MURAL_ROOT" build
```

Initial signing needed `-allowProvisioningUpdates` to create the separate
probe's development profile. It did not alter Mural's profile or bundle ID.
No binary/model distribution is part of this source change. See [notices](NOTICES.md)
before distributing any built artifact.

## Host replay limits

The maintained Python package at this revision imports TTS types unconditionally.
Building it with `SHERPA_ONNX_ENABLE_TTS=OFF` produces a `GenerationConfig` import
failure. The retained failure log documents this; rebuilding Python with its
supported TTS-enabled configuration resolved it. The iOS **C API** stays no-TTS.
No TTS model is loaded by either AED replay.

`run_reference.py firered-onnx` was run using that source-built Python runtime.
The four upstream fixtures have **no independently reviewed ground truth** here.
The private manifest explicitly says not to score them as human accuracy.
Official AED PyTorch was run separately with CPU/FP32, one thread, beam 1,
softmax smoothing 1, length penalty 0, EOS penalty 1. This controls some search
choices, but is not proof of graph-level or dataset-wide quantization parity.
`evaluate.py` measured model-to-model agreement only. No script conversion,
translation, or transcript correction was applied.

## Existing Mural slot (free-signing device)

The first standalone installation hit the free-profile three-app limit. The user
requested using the existing Mural app instead. Do not uninstall any app. Generate
the explicit variant, build and copy its signed app, then regenerate the ordinary
project. Commit only the ordinary generated project. This adds no runtime link or
native source to an ordinary build and changes no ASR default.

```sh
python3 scripts/generate_project.py --firered-file-probe
xcodebuild -project Mural.xcodeproj -scheme Mural -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .build/local-mvp-phase-1-device-derived-data \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  PRODUCT_BUNDLE_IDENTIFIER=com.kevintruong.mural.dev build
# Preserve this signed app outside derived data before rebuilding the default.
python3 scripts/generate_project.py
```

Use `BUNDLE=com.kevintruong.mural.dev` and that preserved `Mural.app` for the
commands below. `--run-firered` routes directly to the same file-probe controller,
**before LearningStore or the normal audio/model owner is created**. No launch
argument means normal Mural. Files live only in `Documents/FireRedProbe`; backup
exclusion applies only to that directory, not Mural's Documents or learning data.
The initial six-replay gate passed in this mode; see the qualification result.

## Physical gate: exclusive phone handoff

Do not run these commands until the user confirms Breeze is not using the phone.
Rediscover the connected physical iPhone 17 and set `DEVICE_UDID` locally. Never
uninstall Mural or reset its data. Use its bundle only with the explicit variant
above, not by renaming the standalone replacement app.

```sh
xcrun devicectl list devices
: "${DEVICE_UDID:?Set the freshly discovered physical iPhone 17 identifier}"
export BUNDLE=com.kevintruong.mural.fireredprobe
export APP="$F/probe-derived/Build/Products/Release-iphoneos/FireRedProbe.app"
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"
export MODEL="$F/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26"
mkdir -p "$F/staging/FireRedProbe/model"
cp -n "$MODEL/encoder.int8.onnx" "$MODEL/decoder.int8.onnx" "$MODEL/tokens.txt" "$F/staging/FireRedProbe/model/"
xcrun devicectl device copy to --device "$DEVICE_UDID" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --source "$F/staging/FireRedProbe" --destination Documents/FireRedProbe
# Upstream 5.1-second mixed-language fixture, NOT human-reference accuracy.
xcrun devicectl device copy to --device "$DEVICE_UDID" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --source "$MODEL/test_wavs/1.wav" --destination Documents/FireRedProbe/probe.wav
xcrun devicectl device process launch --device "$DEVICE_UDID" \
  --terminate-existing "$BUNDLE" --run-firered
```

A launch without `--run-firered` is idle; tap **Run file probe** explicitly.
Only one run is allowed per process. Pin verification reads fixed-size chunks,
then the app validates a complete 3-10-second PCM16 WAV before creating sherpa.
One serial native owner creates the recognizer and performs three replays,
destroys it, then reloads and repeats three times. Each result/stream is released
after synchronous native work. Stop, inactive-app notification, memory warning,
and serious thermal state prevent further work. Cancellation cannot interrupt
an in-flight C call or free its handles early. A completed load/decode over 60 s
is a resource blocker, not a recommended product latency target.

Reports are private, atomic `Documents/FireRedProbe/firered-<UUID>.json` checkpoints with
raw output, input SHA-256, model pins, OS/hardware, preparation/decode times,
thermal state, warning count and Mach footprint. Only the probe directory is excluded from
backup. A memory warning also writes a marker immediately. Last checkpoint
without `complete: true` is **not a pass**, including termination during load.
Never retry a crash or memory warning just to obtain a completion.

Retrieve the **specific report file** using `devicectl device info files` and
`device copy from`. Do not copy the whole Documents directory/models to get logs.
Set `REPORT` to the retrieved file and run this minimal acceptance check:

```sh
python3 - "$REPORT" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
assert r['complete'] is True and 'failure' not in r
assert r['provider'] == 'cpu' and r['threads'] == r['batch_size'] == 1
assert len(r['predictions']) == 6
assert len({p['text'] for p in r['predictions']}) == 1
assert sum(e['stage'] == 'Recognizer released' for e in r['events']) == 2
assert all(e['memory_warnings'] == 0 and e['thermal_state'] < 2
           and e['memory_available'] for e in r['events'])
assert all(0 < p['decode_seconds'] <= 60 for p in r['predictions'])
assert all(0 < r[f'prepare_{i}_seconds'] <= 60 for i in (1, 2))
print('Repeated replay/cleanup report checks passed; human output and resource review still required.')
PY
```

Measure current footprint before/after each owner lifetime. Kernel footprint/RSS
peaks are **process-lifetime** values, not isolated model allocations. Decode
latency spans stream creation, waveform frontend, native decode and result copy;
it is **not live Send-to-final**. Six replays of one clip do not establish p50/p90
across speech, leak freedom, interruption safety, offline restart, or a 20-turn
soak. Test those only after reviewing the initial physical result. Keep full
reports and recordings out of commits.
