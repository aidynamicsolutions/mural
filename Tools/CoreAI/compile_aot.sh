#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <model.aimodel> [output-directory]" >&2
  exit 64
fi

MODEL="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUT="${2:-.build/coreai/aot}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

if [[ ! -e "$MODEL" ]]; then
  echo "Model not found: $MODEL" >&2
  exit 66
fi

if ! xcrun --find coreai-build >/dev/null 2>&1; then
  echo "coreai-build is unavailable. Install the iOS 27/Xcode Core AI toolchain and Metal Toolchain." >&2
  echo "Metal Toolchain can be installed with: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 69
fi

HELP="$(xcrun coreai-build compile --help 2>&1 || true)"
ARGS=(compile "$MODEL" --platform iOS)

# Core AI is new and CLI flag spelling can move between Xcode seeds.
# Add the deployment flag only when the installed tool advertises it.
if grep -q -- "--min-deployment-version" <<<"$HELP"; then
  ARGS+=(--min-deployment-version 27.0)
elif grep -q -- "--minimum-deployment-version" <<<"$HELP"; then
  ARGS+=(--minimum-deployment-version 27.0)
fi

echo "Core AI AOT compile"
echo "  input:  $MODEL"
echo "  output: $OUT"
echo "  command: xcrun coreai-build ${ARGS[*]}"

if grep -q -- "--output" <<<"$HELP"; then
  xcrun coreai-build "${ARGS[@]}" --output "$OUT"
else
  (
    cd "$OUT"
    xcrun coreai-build "${ARGS[@]}"
  )
fi

echo
echo "Compiled assets:"
find "$OUT" -maxdepth 2 \( -name "*.aimodelc" -o -name "*.aimodel" \) -print | sort

echo
echo "The iPhone probe expects the matching architecture asset named like:"
echo "  phowhisper-cs-fp16-v1.<AIModel.deviceArchitectureName>.aimodelc"
echo "Copy that directory to the Mural app container or pass --coreai-model-path=<absolute-device-path>."
