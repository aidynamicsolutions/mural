#!/bin/bash
# Native XCTest needs no detached mirror. All recorder children are stopped by
# the lifecycle runner before this finalizer, including on timeout/cancellation.
set -euo pipefail
: "${EVIDENCE:?}"
if [[ -e "$EVIDENCE/recorder.pid" ]]; then
  test -s "$EVIDENCE/settings.mov"
  # Decode the source directly. A null-output transcode can introduce timestamp
  # errors for simctl's variable-frame-rate video while still exiting zero.
  ffprobe -v error -err_detect explode -count_frames -select_streams v:0 \
    -show_entries format=duration:stream=nb_frames,nb_read_frames -of json \
    "$EVIDENCE/settings.mov" > "$EVIDENCE/video-probe.json" 2> "$EVIDENCE/video-decode.log"
  test ! -s "$EVIDENCE/video-decode.log"
  python3 - "$EVIDENCE/video-probe.json" <<'PY'
import json,sys
probe = json.load(open(sys.argv[1]))
assert float(probe['format']['duration']) > 0
assert len(probe['streams']) == 1
stream = probe['streams'][0]
assert int(stream['nb_read_frames']) == int(stream['nb_frames']) > 0
PY
fi
