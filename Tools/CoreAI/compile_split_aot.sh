#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: $0 <split-export-directory> [aot-output-directory] [model-name]" >&2
  exit 64
fi

EXPORT_DIR="$(cd "$1" && pwd)"
OUT="${2:-.build/coreai/split-aot}"
NAME="${3:-phowhisper-cs-fp16-v1}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

ENCODER="$EXPORT_DIR/$NAME.encoder.aimodel"
DECODER="$EXPORT_DIR/$NAME.decoder.aimodel"

for model in "$ENCODER" "$DECODER"; do
  if [[ ! -e "$model" ]]; then
    echo "Missing split Core AI asset: $model" >&2
    exit 66
  fi
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Compiling encoder..."
"$SCRIPT_DIR/compile_aot.sh" "$ENCODER" "$OUT/encoder"

echo
echo "Compiling decoder..."
"$SCRIPT_DIR/compile_aot.sh" "$DECODER" "$OUT/decoder"

echo
echo "AOT split assets:"
find "$OUT" -type d -name "*.aimodelc" -print | sort

cat <<EOF

Stage exactly one architecture-matching encoder and decoder on the iPhone under:
  Library/Application Support/CoreAI/PhoWhisperSplit/

Rename/copy them to:
  $NAME.encoder.<AIModel.deviceArchitectureName>.aimodelc
  $NAME.decoder.<AIModel.deviceArchitectureName>.aimodelc

For the current iPhone 17 test device the prior loading probe reported architecture h18p,
but always verify AIModel.deviceArchitectureName again rather than hard-coding it.
EOF
