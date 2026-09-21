#!/usr/bin/env python3
"""Bound a simctl recording and finalize it even when the driving tool times out."""
import argparse
from pathlib import Path
import signal
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Explicit simulator UDID")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--seconds", type=int, default=120)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 600:
        parser.error("--seconds must be between 1 and 600")
    if args.output.exists():
        parser.error("output already exists; use a fresh evidence filename")
    args.output.parent.mkdir(parents=True, exist_ok=True)

    def stop(_signum, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop)
    recorder = subprocess.Popen([
        "xcrun", "simctl", "io", args.device, "recordVideo", str(args.output)
    ])
    print(f"Recorder PID={recorder.pid} device={args.device} output={args.output}", flush=True)
    try:
        recorder.wait(timeout=args.seconds)
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        # Ignore repeated stop requests while simctl flushes the movie.
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        if recorder.poll() is None:
            recorder.send_signal(signal.SIGINT)
        try:
            recorder.wait(timeout=20)
        except subprocess.TimeoutExpired:
            recorder.kill()
            recorder.wait(timeout=5)
            print("Finalization timed out; capture invalid. Simulator recorder may remain busy.", file=sys.stderr)
            return 1
    if recorder.returncode != 0 or not args.output.is_file() or args.output.stat().st_size == 0:
        print("Recording failed or produced an empty file; inspect the capture log.", file=sys.stderr)
        return 1
    print(f"Finalized {args.output}; decode-check it with ffprobe before using it as evidence.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
