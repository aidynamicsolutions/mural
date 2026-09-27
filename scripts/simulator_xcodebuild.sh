#!/bin/bash
# Called by mural_simulator.py while holding its DerivedData lock.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${EVIDENCE:?}" "${DERIVED_DATA:?}"
common=(-project Mural.xcodeproj -scheme Mural -configuration Debug
  -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES)

xcbuild() {
  local name="$1"; shift
  printf '\n==> %s (%s)\n' "$name" "$(date -u +%FT%TZ)"
  xcodebuild "${common[@]}" "$@" 2>&1 | tee "$EVIDENCE/$name.log" | xcbeautify --is-ci
}

if [[ "$1" == build || "$1" == build-for-testing ]]; then
  xcbuild "$1" -destination 'generic/platform=iOS Simulator' "$1"
  exit
fi
[[ "$1" == verify ]]
: "${SIM_UDID:?}"
[[ "${SIM:?}" == "$SIM_UDID" ]]
xcrun simctl bootstatus "$SIM_UDID" -b
# A cold XCTest runner needs SpringBoard to settle after profile setup.
sleep 10

run_tests() {
  local name="$1"; shift
  local status=0
  printf 'Selected tests: %s; per-test allowance: 180s; no automatic retries\n' "$#"
  xcbuild "$name" -destination "platform=iOS Simulator,id=$SIM_UDID" -destination-timeout 30 \
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
    -maximum-test-execution-time-allowance 180 -collect-test-diagnostics never \
    -resultBundlePath "$EVIDENCE/$name.xcresult" "$@" test-without-building || status=$?
  printf '%s\n' "$status" > "$EVIDENCE/$name-exit-status.txt"
  xcrun xcresulttool get test-results summary --path "$EVIDENCE/$name.xcresult" --compact \
    | tee "$EVIDENCE/$name-summary.json"
  [[ "$status" == 0 ]]
  python3 - "$EVIDENCE/$name-summary.json" "$#" "$SIM_UDID" <<'PY'
import json,sys
summary = json.load(open(sys.argv[1]))
assert summary['result'] == 'Passed' and summary['failedTests'] == 0, summary
assert summary['skippedTests'] == 0 and summary['passedTests'] == int(sys.argv[2]), summary
assert all(d['device']['deviceId'] == sys.argv[3] for d in summary['devicesAndConfigurations']), summary
PY
}

# The Make driver validates and records the exact focused/smoke/qualification selection.
: "${TESTS:?Selection must come from mural_simulator.py}"
read -r -a tests <<< "$TESTS"
selectors=()
animation=no
for test in "${tests[@]}"; do
  [[ "$test" =~ ^test[A-Za-z0-9_]+$ ]] || { echo 'TESTS must contain test method names' >&2; exit 2; }
  if [[ "$test" == testSettingsDropdownTransitions ]]; then animation=yes
  else selectors+=("-only-testing:MuralUITests/MuralUITests/$test"); fi
done
if [[ ${#selectors[@]} -gt 0 ]]; then run_tests supported-ui "${selectors[@]}"; fi
if [[ "$animation" == yes ]]; then
  # Same owned group as the test. Runner gives SIGINT 30 seconds before escalation,
  # allowing the existing bounded recorder its complete 25-second finalization.
  python3 -u .agents/skills/verify-mural/scripts/record-simulator.py \
    --device "$SIM" --output "$EVIDENCE/settings.mov" --seconds 240 \
    > "$EVIDENCE/recording.log" 2>&1 &
  recorder=$!
  printf '%s\n' "$recorder" > "$EVIDENCE/recorder.pid"
  ps -p "$recorder" -o pid=,lstart=,command= > "$EVIDENCE/recorder-owner.txt"
  finish_recording() {
    # This is our unreaped child, not a detached/reused PID.
    if kill -0 "$recorder" 2>/dev/null; then kill -TERM "$recorder"; fi
    wait "$recorder"
  }
  trap finish_recording EXIT
  ready=no
  for _ in {1..30}; do
    if grep -q 'Recording started' "$EVIDENCE/recording.log"; then ready=yes; break; fi
    kill -0 "$recorder"
    sleep 1
  done
  [[ "$ready" == yes ]] || { echo 'Recorder not ready; tests not started' >&2; exit 1; }
  run_tests settings-transition -only-testing:MuralUITests/MuralUITests/testSettingsDropdownTransitions
fi
