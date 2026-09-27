#!/usr/bin/env python3
"""Real simctl acceptance check. Pass a SHUTDOWN synthetic device; never erases data.

Failure cases were specified before the runner: wrong device, concurrent ownership,
prebooted borrowing, nonzero command, timeout/signals, cleanup-hook failure, lost
artifacts, child leaks, and changes to another project's booted device.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
RUNNER = ROOT / "scripts/verify_simulator.py"


def devices():
    data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"], timeout=30))
    return {d["udid"]: d for group in data["devices"].values() for d in group}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--udid", required=True)
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--control-udid", required=True, help="Separately owned booted synthetic control; this check never changes it")
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    before = devices()
    assert before[args.udid]["state"] == "Shutdown", "Use a shutdown synthetic device"
    assert args.control_udid != args.udid
    assert before[args.control_udid]["name"].startswith("Mural Lifecycle")
    assert before[args.control_udid]["state"] == "Booted", "Boot the controlled isolation sentinel first"
    assert before[args.udid]["name"].startswith("Mural Lifecycle"), "Dedicated check device only"
    results = []
    boot = 'xcrun simctl bootstatus "$SIM_UDID" -b'  # Default slimming already boots the device.

    def command(name, script, extra=()):
        return [sys.executable, str(RUNNER), "--udid", args.udid,
                "--evidence", str(evidence / name), *extra, "--", "bash", "-c", script]

    def check(name, script, expected, extra=(), cleanup="PASS"):
        with (evidence / (name + ".log")).open("w") as log:
            result = subprocess.run(command(name, script, extra), stdout=log, stderr=subprocess.STDOUT, timeout=240)
        assert result.returncode == expected, (name, result.returncode, expected)
        report = json.loads((evidence / name / "cleanup.json").read_text())
        assert report["cleanup"] == cleanup, report
        assert report["final_state"] == "Shutdown", report
        assert devices()[args.udid]["state"] == "Shutdown"
        results.append(name)

    # Exact UDID only; no name or booted-device fallback.
    for selector in ("", "booted", "Mural Lifecycle Verification",
                     "00000000-0000-0000-0000-000000000000"):
        result = subprocess.run([sys.executable, str(RUNNER), "--udid", selector,
                                 "--", "true"], capture_output=True, timeout=30)
        assert result.returncode != 0, selector
    results.append("invalid-selection")

    check("success", boot + '; printf retained > "$EVIDENCE/artifact.txt"', 0)
    assert (evidence / "success/artifact.txt").read_text() == "retained"
    check("failure", boot + "; exit 23", 23)
    check("timeout", boot + "; sleep 300", 124, ("--timeout", "45"))

    # Interrupt while a real simulator and owned command child are both running.
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        name = sig.name.lower()
        script = boot + '; sleep 300 & echo $! > "$EVIDENCE/child.pid"; touch "$EVIDENCE/ready"; wait'
        with (evidence / (name + ".log")).open("w") as log:
            process = subprocess.Popen(command(name, script), stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 120
                while not (evidence / name / "ready").exists():
                    assert process.poll() is None, name
                    assert time.monotonic() < deadline, "boot readiness timeout"
                    time.sleep(0.5)
                rejected = subprocess.run(command(name + "-concurrent", "exit 0"), capture_output=True, timeout=20)
                assert rejected.returncode != 0
                assert devices()[args.udid]["state"] == "Booted", "Rejected run touched active owner"
                process.send_signal(sig)
                assert process.wait(timeout=90) == 128 + sig
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=90)
        report = json.loads((evidence / name / "cleanup.json").read_text())
        assert report["cleanup"] == "PASS", report
        assert devices()[args.udid]["state"] == "Shutdown"
        pid = (evidence / name / "child.pid").read_text().strip()
        stat = subprocess.run(["ps", "-p", pid, "-o", "stat="], capture_output=True, text=True).stdout.strip()
        assert not stat or stat.startswith("Z"), ("Child still executing", pid, stat)
        results.append(name + "-and-concurrent-rejection")

    # Refuse an already booted device even when no runner holds its lock.
    subprocess.run(["xcrun", "simctl", "boot", args.udid], check=True, timeout=30)
    try:
        rejected = subprocess.run(command("prebooted", "exit 0"), capture_output=True, timeout=30)
        assert rejected.returncode != 0
        assert devices()[args.udid]["state"] != "Shutdown", "Borrowed device was shut down"
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", args.udid], check=True, timeout=60)
    results.append("prebooted-rejection")

    hook = evidence / "failing-cleanup.sh"
    hook.write_text('#!/bin/bash\necho "intentional cleanup-hook failure" >&2\nexit 19\n')
    check("cleanup-failure", boot, 1, ("--cleanup-script", str(hook)), cleanup="FAIL")
    check("failure-and-cleanup-failure", boot + "; exit 23", 23,
          ("--cleanup-script", str(hook)), cleanup="FAIL")

    # Missing SimSlim now fails closed, rather than silently running full-weight.
    with (evidence / "without-simslim.log").open("w") as log:
        result = subprocess.run(command("without-simslim", boot,
                                ("--slim-profile", str(ROOT / ".agents/skills/verify-mural/simslim-default.json"))),
                                env={**os.environ, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"},
                                stdout=log, stderr=subprocess.STDOUT, timeout=180)
    assert result.returncode == 1
    assert devices()[args.udid]["state"] == "Shutdown"
    missing_report = json.loads((evidence / "without-simslim/cleanup.json").read_text())
    assert missing_report["slimming"]["result"] == "setup pending"
    assert missing_report["cleanup"] == "PASS"
    assert not (evidence / "without-simslim/command-process.json").exists()
    results.append("without-simslim")

    # The supplied finalizer must run before shutdown, after the recorder has finalized.
    video_hook = evidence / "video-cleanup.sh"
    video_hook.write_text('''#!/bin/bash
set -euo pipefail
xcrun simctl ui "$SIM_UDID" appearance "$(cat "$EVIDENCE/original-appearance")"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$EVIDENCE/recording.mp4" > "$EVIDENCE/video-duration"
''')
    video = boot + f'''
xcrun simctl ui "$SIM_UDID" appearance > "$EVIDENCE/original-appearance"
xcrun simctl ui "$SIM_UDID" appearance dark
python3 "{ROOT}/.agents/skills/verify-mural/scripts/record-simulator.py" --device "$SIM_UDID" --output "$EVIDENCE/recording.mp4" --seconds 120 &
sleep 5
'''
    check("recording-finalizer", video, 0, ("--cleanup-script", str(video_hook)))
    assert float((evidence / "recording-finalizer/video-duration").read_text()) > 0
    assert (evidence / "recording-finalizer/recording.mp4").stat().st_size > 0

    # Refuse to overwrite an existing session/artifact directory.
    repeated = subprocess.run(command("success", "exit 0"), capture_output=True, timeout=30)
    assert repeated.returncode != 0
    assert (evidence / "success/artifact.txt").read_text() == "retained"
    results.append("evidence-reuse-refused")

    after = devices()
    other_booted = [u for u, d in before.items() if d["state"] == "Booted"]
    assert after[args.control_udid]["state"] == "Booted", "Controlled unrelated device changed"
    external_changes = [u for u in other_booted if after[u]["state"] != "Booted"]
    assert (evidence / "success/artifact.txt").read_text() == "retained"
    report = {"result": "PASS", "checks": results, "control_device_preserved": args.control_udid,
              "externally_changed_devices": external_changes,
              "owned_device": args.udid, "final_state": after[args.udid]["state"]}
    (evidence / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
