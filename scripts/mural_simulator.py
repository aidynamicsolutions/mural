#!/usr/bin/env python3
"""Make's simulator-only build/verification commands; lock reusable DerivedData."""
import argparse
from datetime import datetime
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

from verify_simulator import Interrupted, device_in, interrupted, snapshot, stop_group, write_json

ROOT = Path(__file__).resolve().parent.parent
SMOKE_TESTS = (
    "testOnboardingChoosesLearningAndSubtitleLanguagesWithoutAnAccount",
    "testMeaningLabelWorksAfterEndingAndManualResetKeepsHistory",
    "testOnDeviceVoiceSelectionPersists",
)
QUALIFICATION_TESTS = (
    "testOnboardingChoosesLearningAndSubtitleLanguagesWithoutAnAccount",
    "testExistingUserCanDeclineThenAcceptAIConsentWithoutRepeatingOnboarding",
    "testMeaningLanguageSelectsOnDeviceRecognizerAndUnsupportedCombinationsFailClosed",
    "testSpeechSetupCancelKeepsAdmissionClosedUntilDrain",
    "testOnDeviceVoiceSelectionPersists",
    "testMuralVoiceSelectionPersists",
    "testThemeSurvivesNavigationToWords",
    "testThemeSearchFiltersLocally",
    "testSettingsOfferSecureKeyEntryAndBackups",
    "testMeaningLabelWorksAfterEndingAndManualResetKeepsHistory",
    "testOpenTranscriptRemainsReadableUntilManualNewConversation",
    "testSettingsLanguageRowAtAccessibilityTextSize",
    "testSettingsDropdownTransitions",
)


def select_tests(suite, requested):
    if suite not in ("smoke", "qualification"):
        raise ValueError("VERIFY_SUITE must be smoke or qualification")
    tests = requested.split() if requested is not None else list(SMOKE_TESTS if suite == "smoke" else QUALIFICATION_TESTS)
    if not tests or any(not re.fullmatch(r"test[A-Za-z0-9_]+", test) for test in tests):
        raise ValueError("TESTS must contain test method names")
    if len(set(tests)) != len(tests):
        raise ValueError("TESTS must not contain duplicate methods")
    return tests


def wait(command, env, timeout, lifecycle=False):
    process = subprocess.Popen(command, env=env, start_new_session=True)
    try:
        return process.wait(timeout=timeout)
    except (Interrupted, subprocess.TimeoutExpired) as error:
        # The lifecycle owner must finish its own separately bounded cleanup before
        # releasing the build lock. Never kill it on an ordinary cancellation.
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, signal.SIG_IGN)
        if lifecycle:
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=300)
        return 128 + error.signum if isinstance(error, Interrupted) else 124
    finally:
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, signal.SIG_IGN)
        if not lifecycle:
            stop_group(process)
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, interrupted)


def main():
    started = time.monotonic()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("build", "verify"))
    args = parser.parse_args()
    os.chdir(ROOT)
    suite = os.environ.get("VERIFY_SUITE") or "smoke"
    try:
        tests = select_tests(suite, os.environ.get("TESTS")) if args.action == "verify" else []
    except ValueError as error:
        parser.error(str(error))
    mode = os.environ.get("SIMULATOR_MODE") or "slim"
    if mode not in ("slim", "stock"):
        parser.error("SIMULATOR_MODE must be slim or stock")
    profile = os.environ.get("SIMSLIM_PROFILE")
    if mode == "stock" and profile:
        parser.error("SIMSLIM_PROFILE conflicts with SIMULATOR_MODE=stock")
    udid = os.environ.get("SIM_UDID", "").upper()
    if args.action == "verify":
        if not udid:
            parser.error("SIM_UDID must be an explicit owned Shutdown simulator UUID")
        if device_in(snapshot(), udid)["state"] != "Shutdown":
            parser.error("SIM_UDID must be Shutdown; do not borrow a booted simulator")
    evidence = Path(os.environ.get("EVIDENCE") or
                    f".build/verification/{datetime.now():%Y%m%d-%H%M%S}-{os.getpid()}").resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    # Exclusive marker refuses accidental reuse, including a build-only attempt.
    with (evidence / "make-action.json").open("x") as file:
        json.dump({"action": args.action, "pid": os.getpid(), "suite": suite, "tests": tests,
                   "selection": "focused" if os.environ.get("TESTS") else suite}, file, indent=2)
    derived = Path(os.environ.get("DERIVED_DATA") or ".build/mural-lifecycle-derived-data").resolve()
    derived.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "EVIDENCE": str(evidence), "DERIVED_DATA": str(derived),
           "SIM_UDID": udid, "SIM": udid, "TESTS": " ".join(tests)}
    budget = 900 if args.action == "build" else (2400 if suite == "qualification" else 600)
    reserve = 0 if args.action == "build" else 180
    deadline = started + budget - reserve  # Never cut off shutdown to meet a target.
    timings = {"budget_seconds": budget, "cleanup_reserve_seconds": reserve,
               "preparation_seconds": time.monotonic() - started}
    code = 1
    try:
        with (derived / ".mural-build.lock").open("a+") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                parser.error(f"DerivedData is owned by another Mural job: {derived}")
            for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
                signal.signal(sig, interrupted)
            action = "build" if args.action == "build" else "build-for-testing"
            build_started = time.monotonic()
            remaining = 900 if args.action == "build" else max(0, deadline - build_started)
            code = wait(["bash", str(ROOT / "scripts/simulator_xcodebuild.sh"), action], env, min(900, remaining))
            timings["build_seconds"] = time.monotonic() - build_started
            if code == 0 and args.action == "verify":
                remaining = int(deadline - time.monotonic())
                if remaining <= 0:
                    print("Verification work budget exhausted by build; simulator not started", file=sys.stderr)
                    code = 124
                else:
                    command = [sys.executable, str(ROOT / "scripts/verify_simulator.py"), "--udid", udid,
                               "--evidence", str(evidence), "--timeout", str(remaining),
                               "--cleanup-script", str(ROOT / "scripts/simulator_finalize.sh")]
                    if mode == "stock":
                        command += ["--stock"]
                    elif profile:
                        command += ["--slim-profile", profile]
                    runtime_started = time.monotonic()
                    code = wait(command + ["--", "bash", str(ROOT / "scripts/simulator_xcodebuild.sh"), "verify"],
                                env, remaining + 300, lifecycle=True)
                    timings["lifecycle_seconds"] = time.monotonic() - runtime_started
    finally:
        timings["total_seconds"] = time.monotonic() - started
        timings["budget_met"] = timings["total_seconds"] <= budget
        if args.action == "verify" and not timings["budget_met"]:
            print(f"Verification exceeded the {budget}s total budget; cleanup was allowed to finish", file=sys.stderr)
            code = code or 124
        timings["exit_code"] = code
        write_json(evidence / "timings.json", timings)
        print(f"Mural {args.action}: {timings['total_seconds']:.1f}s through finalization; evidence {evidence}", flush=True)
    return code


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Mural simulator command failed: {error}", file=sys.stderr)
        sys.exit(1)
