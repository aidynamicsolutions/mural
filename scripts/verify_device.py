#!/usr/bin/env python3
"""Bounded, opt-in physical Mural verification and saved evidence reports.

prepare builds only. Runtime stages may speak; preferences are restored through UI.
No simulator operations, mirroring, cloud fallback, room recording or automatic retries.
"""
import argparse
from contextlib import ExitStack
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import pwd
import re
import shlex
import signal
import subprocess
import sys
import time
import uuid
import wave

from verify_simulator import Interrupted, interrupted, stop_group, write_json

ROOT = Path(__file__).resolve().parent.parent
APP_ID = "com.kevintruong.mural.dev"
TEST_ID = APP_ID + ".physicaltests"
BACKEND = "Core AI GPU-preferred encoder + Core ML decoder (staged)"
APP_EXECUTABLE = "Build/Products/Release-iphoneos/Mural.app/Mural"
EVIDENCE_ROOT = ROOT / ".build/verification/physical-iphone-e2e"
FAULTS = re.compile(r"asr_memory_warning|ios_memory_warning|tts_safety_stop|thermal_state=[23]\b|"
                    r"asr_(?:preparation|turn|staged_decoder_wait|staged_decoder_speculative)_failed|"
                    r"OpenAI request attempted|local_reply_failed|model_failed")


def phase_durations(boundaries, ended):
    """Partition one monotonic clock domain; incomplete runs still retain their phases."""
    names = [name for name, _ in boundaries]
    times = [stamp for _, stamp in boundaries] + [ended]
    if len(set(names)) != len(names) or any(b < a for a, b in zip(times, times[1:])):
        raise ValueError("Duplicate or nonmonotonic timing boundary")
    return {name: times[index + 1] - times[index] for index, name in enumerate(names)}


def native_phase_durations(log):
    # Device uptime is never subtracted from host monotonic time.
    boundaries = [(name, float(stamp)) for name, stamp in re.findall(
        r"^MURAL_DEVICE_TIMING ([a-z0-9_]+) ([0-9]+\.[0-9]+)\s*$", log, re.MULTILINE)]
    if not boundaries:
        return {}
    durations = phase_durations(boundaries, boundaries[-1][1])
    return {f"{name}_to_{boundaries[index + 1][0]}": durations[name]
            for index, (name, _) in enumerate(boundaries[:-1])}


def playback_request(log, run, index):
    requests = re.findall(rf"^MURAL_DEVICE_PLAYBACK_WAIT {re.escape(run)} {index} ([A-Fa-f0-9-]{{36}})$",
                          log, re.MULTILINE)
    if len(requests) != 1:
        raise ValueError("Missing or duplicate current-run playback request")
    return str(uuid.UUID(requests[0])).upper()


def playback_ack_token(log, run, index, playback):
    token = playback_request(log, run, index)
    start, end = playback.get("started_monotonic"), playback.get("ended_monotonic")
    if (start is None or end is None or not 0 <= end - start <= 5 or
            playback.get("exit_code") != 0 or playback.get("send_observed_at_completion") is not False):
        raise ValueError("Refuse acknowledgment before successful bounded playback without early Send")
    return token


def reviewed_fixture(manifest, clip_id):
    """Validate a reviewer-frozen PCM clip without playing audio or contacting a phone."""
    manifest = manifest.resolve()
    raw = manifest.read_bytes()
    data = json.loads(raw)
    matches = [clip for clip in data["clips"] if clip.get("id") == clip_id]
    if len(matches) != 1:
        raise ValueError("Require one explicitly selected fixture")
    clip = matches[0]
    review_fields = (clip.get("reviewer"), clip.get("reference"), data.get("scoring"))
    if (clip.get("reviewed") is not True
            or any(not isinstance(value, str) or not value.strip() for value in review_fields)):
        raise ValueError("Fixture reference, reviewer and scoring must be frozen before inference")
    path = (manifest.parent / clip["file"]).resolve()
    if not path.is_relative_to(manifest.parent):
        raise ValueError("Fixture path escapes the reviewed packet")
    if hashlib.sha256(path.read_bytes()).hexdigest() != clip["sha256"]:
        raise ValueError("Reviewed fixture bytes changed")
    with wave.open(str(path), "rb") as audio:
        if audio.getnchannels() != 1 or audio.getsampwidth() != 2 or audio.getcomptype() != "NONE":
            raise ValueError("Require reviewed mono PCM16 participant audio")
        rate, frames = audio.getframerate(), audio.getnframes()
        if len(audio.readframes(frames)) != frames * 2:
            raise ValueError("Truncated PCM fixture")
    duration = frames / rate
    declared = clip.get("duration_seconds")
    if (not isinstance(declared, (int, float)) or not math.isfinite(declared)
            or duration <= 0 or abs(duration - declared) > 1 / rate):
        raise ValueError("Fixture duration differs from frozen frame boundaries")
    playback = math.ceil(duration + 3)
    acknowledgment = playback + 7  # Six-second host copy bound plus trailing margin.
    if 5 + acknowledgment + 2 > 30:  # Fresh capture/UI gate and Send headroom.
        raise ValueError("Fixture budgets exceed the existing 30-second recording cap")
    return {**clip, "file": str(path), "duration_seconds": duration,
            "manifest_sha256": hashlib.sha256(raw).hexdigest(), "scoring": data["scoring"],
            "playback_timeout_seconds": playback, "ack_timeout_seconds": acknowledgment,
            "trailing_margin_seconds": 0.75}


def consumed_ack_copy(copy_log, test_log, run, index, token):
    # devicectl stats the destination after writing; XCTest can already have
    # consumed/unlinked it. Prove exact nonce delivery, never forgive other errors.
    destination = f"tmp/mural-playback-{run}-{index}.txt"
    expected = (f"ERROR: Failed to retrieve the file node for {destination} "
                "(com.apple.dt.CoreDeviceError error 7000 (0x1B58))")
    marker = f"MURAL_DEVICE_PLAYBACK_ACK_{index} {run} {token}"
    return copy_log.strip() == expected and test_log.splitlines().count(marker) == 1


def validate_request(udid, stage, ready, pair="vi-en"):
    if not re.fullmatch(r"[0-9A-F]{8}-[0-9A-F]{16}", udid):
        raise ValueError("DEVICE_UDID must be an explicit freshly discovered physical UDID")
    if stage not in ("prepare", "status", "stop-idle", "baseline", "acoustic", "multi", "cancel", "restore-settings", "pair-check"):
        raise ValueError("Unknown physical stage")
    if pair not in ("vi-en", "zh-CN-en"):
        raise ValueError("Unknown physical test pair")
    if pair == "zh-CN-en" and stage not in ("prepare", "pair-check"):
        raise ValueError("FireRed native continuation is blocked; only build preparation and model-free pair-check are available")
    if stage not in ("prepare", "status") and not ready:
        raise ValueError("Confirm the private audible window, idle phone and closed mirroring, then set DEVICE_READY=YES")


def check_summary(summary):
    for key, expected in dict(passedTests=1, failedTests=0, skippedTests=0, totalTestCount=1).items():
        if summary.get(key) != expected:
            raise ValueError(f"Native result is not one unskipped passing test: {key}={summary.get(key)}")


def baseline_events(log):
    if FAULTS.search(log):
        raise ValueError("Resource/model/provider fault in scoped Mural capture; no retry")
    rows = [line for line in log.splitlines() if "local_talk_asr_backend backend=" + BACKEND in line]
    pids = {match.group(1) for row in rows if (match := re.search(r"\bMural\[(\d+)(?::\d+)?\]", row))}
    if len(pids) != 1:
        raise ValueError("Missing or ambiguous fresh Mural backend/process event")
    pid = pids.pop()
    current = "\n".join(line for line in log.splitlines() if re.search(rf"\bMural\[{pid}(?::\d+)?\]", line))
    offset = 0
    for event in ("local_talk_asr_backend backend=" + BACKEND, "preparation_idle_timer acquired=true",
                  "asr_staged_prepared backend=coreai-gpu", "asr_ready", "preparation_idle_timer restored=",
                  "model_complete", "local_reply_complete", "local_ended"):
        found = current.find(event, offset)
        if found < 0:
            raise ValueError(f"Missing/incorrectly ordered current-process event: {event}")
        offset = found + len(event)
    return pid


def acoustic_events(log, pid, expected_count=1):
    current = "\n".join(line for line in log.splitlines() if re.search(rf"\bMural\[{pid}(?::\d+)?\]", line))
    captures = re.findall(r"asr_trial_capture id=([A-Fa-f0-9-]{36})", current)
    segments = current.split("capture_started")[1:]
    if len(captures) != expected_count or len(set(captures)) != expected_count or len(segments) != expected_count:
        raise ValueError("Require exactly the expected distinct acoustic captures")
    for turn, segment in zip(captures, segments):
        offset = 0
        for event in (f"asr_trial_capture id={turn}", f"asr_trial_send id={turn}", "asr_input", f"asr_trial_final id={turn}"):
            found = segment.find(event, offset)
            if found < 0:
                raise ValueError(f"Missing ordered acoustic event: {event}")
            offset = found + len(event)
        if not re.search(r"converted_frames=[1-9][0-9]*\b", segment) or not re.search(r"captured_seconds=(?:[1-9][0-9]*|0\.[0-9]*[1-9])", segment):
            raise ValueError("Missing nonzero captured audio/frame evidence")
    return captures


def cancellation_events(log, pid):
    current = "\n".join(line for line in log.splitlines() if re.search(rf"\bMural\[{pid}(?::\d+)?\]", line))
    captures = re.findall(r"asr_trial_capture id=([A-Fa-f0-9-]{36})", current)
    if len(captures) != 2 or captures[0] == captures[1]:
        raise ValueError("Cancellation must be followed by one distinct fresh capture")
    cancelled = captures[0]
    if any(f"{event} id={cancelled}" in current for event in ("asr_trial_send", "asr_trial_final", "asr_trial_audio")):
        raise ValueError("Canceled recording produced a late send/result/audio event")
    segments = current.split("capture_started")
    if len(segments) != 3 or "local_ended" not in segments[1]:
        raise ValueError("Canceled session did not end before fresh capture")
    start = current.rfind("\n", 0, current.rfind("capture_started")) + 1
    completed = acoustic_events(current[start:], pid)
    return {"cancelled": cancelled, "completed": completed[0]}


def run_bounded(command, log, timeout, env=None, monitor=None, on_stop=None):
    """Own one process group until confirmed stopped, including on signal/timeout."""
    with log.open("w") as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                                   env=env, start_new_session=True)
        write_json(log.with_suffix(".process.json"), {
            "pid": process.pid, "pgid": process.pid, "command": command,
            "started_at": datetime.now(timezone.utc).isoformat(),
            "identity": subprocess.check_output(["ps", "-p", str(process.pid), "-o", "lstart=,command="], text=True).strip()})
        deadline = time.monotonic() + timeout
        try:
            while process.poll() is None:
                if monitor:
                    monitor()
                if time.monotonic() >= deadline:
                    raise subprocess.TimeoutExpired(command, timeout)
                time.sleep(0.25)
            if monitor:
                monitor()
            if process.returncode:
                raise RuntimeError(f"Command exited {process.returncode}; inspect {log}")
        finally:
            # Cancellation cannot interrupt finalization again.
            handlers = {sig: signal.signal(sig, signal.SIG_IGN) for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)}
            try:
                try:
                    if on_stop:
                        on_stop()
                finally:
                    stop_group(process)
            finally:
                for sig, handler in handlers.items():
                    signal.signal(sig, handler)


def input_identity(derived, firered=False):
    # Hash build inputs and executable artifacts, not phone data/model caches.
    paths = subprocess.check_output(["git", "ls-files", "-z", "App", "Core", "Sources", "Config", "UITests",
                                     "Mural.xcodeproj", "Package.swift", "Package.resolved"], cwd=ROOT).decode().split("\0")
    paths += ["scripts/generate_project.py", "Config/Local.xcconfig"]
    if firered:
        paths += [str(p.relative_to(ROOT)) for p in (ROOT / "Tools/ChineseASR/FireRedProbe").glob("Probe.*")]
        paths += ["Tools/ChineseASR/FireRedProbe/pin.json"]
    source = hashlib.sha256()
    for name in sorted(set(filter(None, paths))):
        path = ROOT / name
        if path.is_file():
            source.update(name.encode()); source.update(path.read_bytes())
    products = derived / "Build/Products/Release-iphoneos"
    artifacts = [products / "Mural.app/Mural", products / "Mural.app/Info.plist",
                 products / "MuralUITests-Runner.app/MuralUITests-Runner",
                 products / "MuralUITests-Runner.app/PlugIns/MuralUITests.xctest/MuralUITests"]
    artifacts += sorted((derived / "Build/Products").glob("Mural_iphoneos*.xctestrun"))
    identity = {"source_sha256": source.hexdigest(), "artifacts": {
        str(path.relative_to(derived)): hashlib.sha256(path.read_bytes()).hexdigest() for path in artifacts}}
    if firered:
        runtime = ROOT / ".build/firered"
        native = sorted((runtime / "ios-build/lib").glob("*.a"))
        framework = runtime / "ort-ios/onnxruntime.xcframework/ios-arm64/onnxruntime.framework"
        native += [framework / "onnxruntime", framework / "Info.plist"]
        native += sorted((framework / "Headers").glob("*.h"))
        native += [runtime / "sherpa-onnx/sherpa-onnx/c-api/c-api.h"]
        if len(list((runtime / "ios-build/lib").glob("*.a"))) != 9:
            raise ValueError("Expected the nine reviewed FireRed static libraries")
        identity["native_inputs"] = {}
        for path in native:
            with path.open("rb") as file:
                identity["native_inputs"][str(path.relative_to(ROOT))] = hashlib.file_digest(file, "sha256").hexdigest()
        pin = derived / "Build/Products/Release-iphoneos/Mural.app/pin.json"
        if pin.read_bytes() != (ROOT / "Tools/ChineseASR/FireRedProbe/pin.json").read_bytes():
            raise ValueError("Bundled FireRed pin differs from reviewed source")
        identity["artifacts"][str(pin.relative_to(derived))] = hashlib.sha256(pin.read_bytes()).hexdigest()
    return identity


def idle_process(processes, app_url, pid):
    matches = [p for p in processes if p.get("processIdentifier") == pid and
               p.get("executable") == app_url.rstrip("/") + "/Mural"]
    if len(matches) != 1:
        raise ValueError("Confirmed idle PID does not uniquely match the installed Mural app; nothing stopped")
    return pid


def select_prepared(udid, identity, receipts):
    for path in receipts:
        saved = json.loads(path.read_text())
        if saved.get("udid") == udid and saved.get("identity") == identity:
            return path
    raise ValueError("No matching prepared app/runner for these inputs and phone; run DEVICE_STAGE=prepare")


def runtime_test_plan(source, environment):
    """Copy the fingerprinted Xcode plan, preserving all settings and product identity."""
    plan = plistlib.loads(source.read_bytes())
    if (set(plan) != {"__xctestrun_metadata__", "MuralUITests"} or
            plan["__xctestrun_metadata__"].get("FormatVersion") != 1):
        raise ValueError("Unexpected prepared test plan format/targets")
    target = plan["MuralUITests"]
    if (target.get("TestHostBundleIdentifier") != TEST_ID + ".xctrunner" or
            target.get("UITargetAppPath") != "__TESTROOT__/Release-iphoneos/Mural.app" or
            target.get("TestHostPath") != "__TESTROOT__/Release-iphoneos/MuralUITests-Runner.app"):
        raise ValueError("Prepared test plan changed app/runner identity")
    def resolve(value):
        if isinstance(value, str):
            return value.replace("__TESTROOT__", str(source.parent))
        if isinstance(value, list):
            return [resolve(item) for item in value]
        if isinstance(value, dict):
            return {key: resolve(item) for key, item in value.items()}
        return value
    plan = resolve(plan)
    target = plan["MuralUITests"]
    target.setdefault("EnvironmentVariables", {}).update(environment)
    target["SystemAttachmentLifetime"] = "keepAlways"
    return plan


def compiler_proof(build_log, identity, receipts, firered=False):
    app_hash = identity["artifacts"][APP_EXECUTABLE]
    logs = [(build_log, False)]
    for receipt in receipts:
        saved = json.loads(receipt.read_text())
        if saved.get("identity", {}).get("artifacts", {}).get(APP_EXECUTABLE) == app_hash:
            proof = receipt.with_name("compiler-proof.json")
            if proof.exists():
                previous = json.loads(proof.read_text())
                if previous.get("app_sha256") == app_hash:
                    logs.append((Path(previous["log"]), True))
            logs.append((receipt.with_name("build.log"), True))
    for path, reused in logs:
        if not path.is_file():
            continue
        compiler = linker = None
        with path.open() as file:
            for line in file:
                if ("swiftc -module-name Mural " in line and "-D MURAL_COREAI_TALK" in line
                        and (not firered or re.search(r"-D ?MURAL_FIRERED_FILE_PROBE\b", line))):
                    compiler = line.strip()
                if ("clang++ " in line and " -lsherpa-onnx-c-api " in line
                        and " -framework onnxruntime " in line and line.rstrip().endswith("/Mural.app/Mural")):
                    linker = line.strip()
        if compiler and (not firered or linker):
            return {"app_sha256": app_hash, "log": str(path), "compiler_command": compiler,
                    "linker_command": linker, "reused_from": str(path) if reused else None}
    raise ValueError("No actual Core AI compiler invocation proves these executable bytes; requested flags alone are insufficient")


def summarize_run(evidence):
    """Local evidence only. Safe after failure or in a later session; never touches a phone."""
    bundle = evidence / "baseline.xcresult"
    summary_path = evidence / "summary.json"
    if bundle.exists() and not summary_path.exists():
        result = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle), "--compact"],
                                capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            summary_path.write_text(result.stdout)
        else:
            (evidence / "summary-error.txt").write_text(result.stderr)
    print(f"Evidence: {evidence}")
    for name in ("result.json", "failure.json", "reviewed-result.json", "human-acceptance.json", "cleanup.json", "cleanup-reviewed.json"):
        path = evidence / name
        if path.exists():
            print(f"{name}: {json.dumps(json.loads(path.read_text()), ensure_ascii=False)}")
    if summary_path.exists():
        summary = json.loads(summary_path.read_text())
        print("XCTest: " + ", ".join(f"{key}={summary.get(key)}" for key in ("passedTests", "failedTests", "skippedTests")))
        for failure in summary.get("testFailures", [])[:3]:
            print("  " + failure.get("failureText", "Unknown XCTest failure")[:1000])
    timing_path = evidence / "timings.json"
    if timing_path.exists():
        print("Timings: " + json.dumps(json.loads(timing_path.read_text())))
    test_log = evidence / "test.log"
    if test_log.exists():
        for line in test_log.read_text().splitlines():
            if ": error:" in line:
                print("  " + line[:1000])
    return 0


def device_json(arguments, path):
    subprocess.run(["xcrun", "devicectl", *arguments, "--timeout", "20", "--json-output", str(path)],
                   check=True, timeout=25, stdout=subprocess.DEVNULL)
    return json.loads(path.read_text())["result"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", choices=("prepare", "status", "stop-idle", "baseline", "acoustic", "multi", "cancel", "restore-settings", "pair-check"), default=os.environ.get("DEVICE_STAGE", "prepare"))
    parser.add_argument("--check-fixture", type=Path, help="Validate a frozen review manifest only; no phone or playback")
    parser.add_argument("--clip", help="Explicit clip ID for --check-fixture")
    parser.add_argument("--report", type=Path, nargs="?", const=Path("latest"), help="Summarize saved evidence (latest by default); no device operations")
    args = parser.parse_args()
    if args.check_fixture:
        if not args.clip or args.report:
            raise ValueError("Fixture check requires --clip and cannot be combined with --report")
        print(json.dumps(reviewed_fixture(args.check_fixture, args.clip), ensure_ascii=False, indent=2))
        return 0
    if args.clip:
        raise ValueError("--clip requires --check-fixture")
    if args.report:
        if args.report == Path("latest"):
            runs = list(EVIDENCE_ROOT.glob("*/session.json"))
            if not runs:
                raise ValueError("No saved physical runs")
            args.report = max(runs, key=lambda path: path.stat().st_mtime).parent
        return summarize_run(args.report.resolve())
    started = time.monotonic()
    phases = [("preflight", started)]
    udid = os.environ.get("DEVICE_UDID", "").upper()
    pair = os.environ.get("DEVICE_PAIR", "vi-en")
    validate_request(udid, args.stage, os.environ.get("DEVICE_READY") == "YES", pair=pair)
    if args.stage == "restore-settings" and not os.environ.get("DEVICE_RESTORE_MEANING"):
        raise ValueError("DEVICE_RESTORE_MEANING must be the recorded original preference, never a guessed default")
    os.chdir(ROOT)
    evidence = Path(os.environ.get("EVIDENCE") or
                    f".build/verification/physical-iphone-e2e/{datetime.now():%Y%m%d-%H%M%S}-{os.getpid()}").resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    print(f"Physical {args.stage}: {evidence}", flush=True)
    # Native preparation cannot overwrite the qualified ordinary app/runner.
    firered = pair == "zh-CN-en" and args.stage == "prepare"
    derived = (ROOT / (".build/firered-talk-device-derived-data" if firered else
                       ".build/local-mvp-phase-1-device-derived-data")).resolve()
    derived.mkdir(parents=True, exist_ok=True)
    locks = Path(pwd.getpwuid(os.getuid()).pw_dir) / "Library/Caches/ios-verification"
    locks.mkdir(parents=True, exist_ok=True)
    playback_run = str(uuid.uuid4()).upper()
    session = dict(pid=os.getpid(), udid=udid, stage=args.stage, app=APP_ID, runner=TEST_ID,
                   playback_run=playback_run, pair=pair,
                   configuration="Release", backend=BACKEND, settings="No changes",
                   started_at=datetime.now(timezone.utc).isoformat(), evidence=str(evidence),
                   runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    write_json(evidence / "session.json", session)
    capture = None
    playback = None
    playback_state = {}
    playbacks = []
    capture_file = None
    test_started = False
    code = 1
    cleanup_errors = []
    with ExitStack() as stack:
        lock_paths = [locks / f"{udid}.lock", derived / ".mural-build.lock"]
        if firered:
            lock_paths.append(ROOT / ".build/local-mvp-phase-1-device-derived-data/.mural-build.lock")
        for path in lock_paths:
            lock = stack.enter_context(path.open("a+"))
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            lock.seek(0); lock.truncate(); json.dump(session, lock); lock.flush()
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, interrupted)
        try:
            devices = device_json(["list", "devices"], evidence / "devices.json")["devices"]
            matches = [d for d in devices if d.get("properties", {}).get("hardware", {}).get("udid") == udid]
            if len(matches) != 1:
                raise ValueError("Exact physical device not found")
            device = matches[0]["properties"]
            if (device["hardware"].get("reality") != "physical" or device["hardware"].get("productType") != "iPhone18,3"
                    or device["connection"].get("pairingState") != "paired"):
                raise ValueError("Requires the paired iPhone 17; no backend opt-in on other devices")
            # Discovery's tunnel state may be disconnected while wired RPCs succeed.
            # Require a successful direct request, not a cached discovery state.
            lock_state = device_json(["device", "info", "lockState", "--device", udid], evidence / "lock-state.json")
            if args.stage not in ("prepare", "status") and (lock_state.get("passcodeRequired") is not False or lock_state.get("unlockedSinceBoot") is not True):
                raise ValueError("Phone requires a human unlock")
            installed = device_json(["device", "info", "apps", "--device", udid, "--bundle-id", APP_ID, "--include-container-paths"], evidence / "installed-app.json")
            if not any(app.get("bundleIdentifier") == APP_ID for app in installed.get("apps", [])):
                raise ValueError("Existing Mural bundle missing; refuse a new installation")
            (evidence / "source.txt").write_text(subprocess.check_output(
                ["git", "status", "--short", "--branch"], text=True) + subprocess.check_output(["git", "rev-parse", "HEAD"], text=True))
            (evidence / "implementation.diff").write_bytes(subprocess.check_output(["git", "diff"]))
            project = ROOT / "Mural.xcodeproj"
            if firered:
                # Isolated generation avoids exposing probe flags to concurrent ordinary builds.
                run_bounded([sys.executable, "scripts/generate_project.py", "--firered-file-probe",
                             "--output-directory", str(evidence / "native-project")],
                            evidence / "generation.log", 30)
                project = evidence / "native-project/Mural.xcodeproj"
            base = ["xcodebuild", "-project", str(project), "-scheme", "Mural", "-configuration", "Release",
                    "-destination", f"platform=iOS,id={udid}", "-destination-timeout", "30", "-derivedDataPath", str(derived),
                    f"MURAL_APP_BUNDLE_IDENTIFIER={APP_ID}", f"MURAL_TEST_BUNDLE_IDENTIFIER={TEST_ID}",
                    "OTHER_SWIFT_FLAGS=$(inherited) -D MURAL_COREAI_TALK", "-allowProvisioningUpdates", "-parallel-testing-enabled", "NO",
                    "-only-testing:MuralUITests/MuralPhysicalDeviceTests/testNativeBaseline"]
            if firered:
                base += ["-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile",
                         "-clonedSourcePackagesDirPath", str(ROOT / ".build/local-mvp-phase-1-device-derived-data/SourcePackages")]
            if args.stage == "prepare":
                command = base + ["build-for-testing"]
                pipeline = shlex.join(command) + " 2>&1 | tee " + shlex.quote(str(evidence / "build.log")) + " | xcbeautify --is-ci"
                print("Building signed app and distinct runner; no installation or launch", flush=True)
                phases.append(("signed_build", time.monotonic()))
                run_bounded(["bash", "-o", "pipefail", "-c", pipeline], evidence / "build-formatted.log", 900)
                phases.append(("artifact_validation", time.monotonic()))
                identity = input_identity(derived, firered=firered)
                receipts = sorted(EVIDENCE_ROOT.glob("*/prepared.json"), reverse=True)
                proof = compiler_proof(evidence / "build.log", identity, receipts, firered=firered)
                if firered:
                    symbols = subprocess.check_output(["nm", "-gU", str(derived / APP_EXECUTABLE)], text=True, timeout=30)
                    (evidence / "native-symbols.txt").write_text(symbols)
                    for symbol in ("_SherpaOnnxCreateOfflineRecognizer", "_SherpaOnnxDecodeOfflineStream", "_OrtGetApiBase"):
                        if not re.search(rf"\bT {re.escape(symbol)}$", symbols, re.MULTILINE):
                            raise ValueError(f"Required linked native symbol missing: {symbol}")
                write_json(evidence / "compiler-proof.json", proof)
                if proof["reused_from"]:
                    print("Incremental build: reused compiler proof for identical app executable bytes", flush=True)
                products = derived / "Build/Products/Release-iphoneos"
                for relative, expected in (("Mural.app", APP_ID), ("MuralUITests-Runner.app", TEST_ID + ".xctrunner")):
                    with (products / relative / "Info.plist").open("rb") as file:
                        if plistlib.load(file)["CFBundleIdentifier"] != expected:
                            raise ValueError(f"Incorrect signed bundle identity: {relative}")
                    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(products / relative)], check=True, timeout=30)
                write_json(evidence / "prepared.json", {"udid": udid, "identity": identity,
                    "variant": "firered-coreai" if firered else "coreai", "derived": str(derived)})
                write_json(evidence / "result.json", {"build": "PASS", "native_control": "NOT RUN", "models": "NOT RUN"})
            elif args.stage in ("status", "stop-idle"):
                rows = device_json(["device", "info", "processes", "--device", udid, "--search", "Mural"], evidence / "phone-processes.json")["runningProcesses"]
                if args.stage == "stop-idle":
                    try:
                        pid = int(os.environ.get("DEVICE_IDLE_PID", ""))
                    except ValueError:
                        raise ValueError("DEVICE_IDLE_PID must be the freshly inspected PID explicitly confirmed idle") from None
                    app = next(app for app in installed["apps"] if app["bundleIdentifier"] == APP_ID)
                    idle_process(rows, app["url"], pid)
                    device_json(["device", "process", "terminate", "--device", udid, "--pid", str(pid)], evidence / "terminate.json")
                    after = device_json(["device", "info", "processes", "--device", udid, "--search", "Mural"], evidence / "phone-after.json")["runningProcesses"]
                    if any(row.get("processIdentifier") == pid for row in after):
                        raise ValueError("Confirmed idle Mural PID still present; no automatic escalation")
                    write_json(evidence / "result.json", {"idle_process_stopped": pid, "app_data": "unchanged"})
                else:
                    # Content-free, scoped preparation metadata only, never personal history.
                    try:
                        device_json(["device", "copy", "from", "--device", udid,
                            "--domain-type", "appDataContainer", "--domain-identifier", APP_ID,
                            "--source", "Library/Application Support/Mural/CoreMLPreparation/phowhisper-cs-pal8-g16-v1-stagedDecoder.json",
                            "--destination", str(evidence / "decoder-receipt.json")], evidence / "receipt-copy.json")
                    except subprocess.SubprocessError as error:
                        write_json(evidence / "receipt-unavailable.json", {"error": str(error)})
                    write_json(evidence / "result.json", {"device": udid, "lock_state": lock_state, "processes": rows,
                        "acceptance": "NOT RUN; read-only device status"})
            else:
                fixture = ROOT / ".build/verification/physical-iphone-e2e/fixtures-v1/turn-1.aiff"
                if args.stage in ("acoustic", "multi", "cancel"):
                    if not os.environ.get("DEVICE_PLACEMENT"):
                        raise ValueError("Record confirmed phone placement with DEVICE_PLACEMENT")
                    if hashlib.sha256(fixture.read_bytes()).hexdigest() != "1670c9c29ac928b5849ce4fde4dbc31fef3d01497afba7097a506f9984522111":
                        raise ValueError("Frozen acoustic fixture missing/changed")
                    volume = subprocess.check_output(["osascript", "-e", "get volume settings"], text=True, timeout=10)
                    if "output muted:false" not in volume or "output volume:0," in volume:
                        raise ValueError("Mac speakers are muted; user chose to set volume themselves")
                    route = subprocess.check_output(["system_profiler", "SPAudioDataType", "-json"], text=True, timeout=20)
                    audio = json.loads(route)
                    outputs = [item for group in audio["SPAudioDataType"] for item in group.get("_items", [])
                               if item.get("coreaudio_default_audio_output_device") == "spaudio_yes"]
                    if len(outputs) != 1 or outputs[0].get("coreaudio_device_transport") != "coreaudio_device_type_builtin":
                        raise ValueError("Require built-in Mac speakers")
                    write_json(evidence / "acoustic-spec.json", {"text": "I bought three apples on Tuesday.", "voice": "Samantha", "rate": 150,
                        "fixture": str(fixture), "sha256": hashlib.sha256(fixture.read_bytes()).hexdigest(), "duration": 1.968345,
                        "normalization": "case/punctuation/whitespace; user-approved token 3=three; other words exact", "placement": os.environ["DEVICE_PLACEMENT"],
                        "volume": volume.strip(), "route": outputs, "playback_ack_timeout_seconds": 12,
                        "trailing_margin_seconds": 0.75, "room_capture": False})
                fixtures = [fixture]
                if args.stage in ("multi", "cancel"):
                    second = fixture.with_name("turn-2.aiff")
                    if hashlib.sha256(second.read_bytes()).hexdigest() != "7bc34a03703de4a571c7298e4d8b693e5dc7b8c537e49ea94f753a1f084a96e5":
                        raise ValueError("Second frozen fixture missing/changed")
                    fixtures.append(second)
                    write_json(evidence / "multi-spec.json", {"phrases": ["I bought three apples on Tuesday.", "My appointment is tomorrow morning."],
                        "fixtures": [str(f) for f in fixtures], "sha256": [hashlib.sha256(f.read_bytes()).hexdigest() for f in fixtures],
                        "normalization": "case/punctuation/whitespace; 3=three only", "relaunch": "exact text/count/order in newest synthetic history record"})
                explicit = os.environ.get("DEVICE_PREPARED")
                receipts = [Path(explicit)] if explicit else sorted(EVIDENCE_ROOT.glob("*/prepared.json"), reverse=True)
                prepared_path = select_prepared(udid, input_identity(derived), receipts)
                write_json(evidence / "prepared-source.json", {"receipt": str(prepared_path)})
                print(f"Using verified prepared build: {prepared_path.parent.name}", flush=True)
                # Read-only refusal: never quit someone else's mirror or capture.
                processes = subprocess.check_output(["ps", "-axo", "pid=,command="], text=True, timeout=10)
                if any(term in processes for term in ("/DeviceHub.app/", "/iPhone Mirroring.app/", "idevicesyslog -")):
                    raise ValueError("Mirroring or device capture already active; resolve ownership before running")
                before = subprocess.check_output(["xcrun", "devicectl", "device", "info", "processes", "--device", udid,
                                                  "--search", "Mural", "--timeout", "20"], text=True, timeout=25)
                (evidence / "phone-before.txt").write_text(before)
                if "Mural.app/Mural" in before:
                    raise ValueError("Existing Mural process: do not replace personal work; close the idle app first")
                phases.append(("install", time.monotonic()))
                run_bounded(["xcrun", "devicectl", "device", "install", "app", "--device", udid,
                             str(derived / "Build/Products/Release-iphoneos/Mural.app"), "--timeout", "60"], evidence / "install.log", 70)
                phases.append(("launch_and_backend_gate", time.monotonic()))
                log = evidence / "mural-device.log"
                capture_file = log.open("w")
                capture = subprocess.Popen(["xcrun", "devicectl", "device", "process", "launch", "--device", udid,
                                           "--console", "--environment-variables", '{"OS_ACTIVITY_DT_MODE":"YES"}', APP_ID],
                                           stdout=capture_file, stderr=subprocess.STDOUT, start_new_session=True)
                write_json(evidence / "capture-process.json", {"pid": capture.pid, "pgid": capture.pid,
                    "started_at": datetime.now(timezone.utc).isoformat(), "udid": udid,
                    "identity": subprocess.check_output(["ps", "-p", str(capture.pid), "-o", "lstart=,command="], text=True).strip()})
                deadline = time.monotonic() + 15
                while "local_talk_asr_backend backend=" + BACKEND not in log.read_text():
                    if capture.poll() is not None or time.monotonic() > deadline:
                        raise ValueError("Fresh app-only backend log missing; do not start models")
                    time.sleep(0.25)
                capture_received = None
                observed_phases = set()
                probe_sent = False

                def check_faults():
                    if FAULTS.search(log.read_text()):
                        raise ValueError("Resource/model/provider fault; stop without retry")

                def acknowledge(index, token):
                    # Only the XCTest runner's temporary container, never Mural data.
                    receipt = evidence / f"playback-ack-{index}.txt"
                    receipt.write_text(token)
                    copy_log = evidence / f"playback-ack-{index}.log"
                    try:
                        run_bounded(["xcrun", "devicectl", "device", "copy", "to", "--device", udid,
                                     "--source", str(receipt), "--destination", f"tmp/mural-playback-{playback_run}-{index}.txt",
                                     "--domain-type", "appDataContainer", "--domain-identifier", TEST_ID + ".xctrunner",
                                     "--timeout", "5"], copy_log, 6, monitor=check_faults)
                    except RuntimeError:
                        if not consumed_ack_copy(copy_log.read_text(), (evidence / "test.log").read_text(),
                                                 playback_run, index, token):
                            raise
                        write_json(evidence / f"playback-ack-{index}-consumed.json", {
                            "run": playback_run, "index": index, "token": token,
                            "delivery": "native exact-token receipt precedes devicectl post-copy stat"})

                def monitor():
                    nonlocal playback, playback_state, capture_received, probe_sent
                    content = log.read_text()
                    test_log = evidence / "test.log"
                    test_content = test_log.read_text() if test_log.exists() else ""
                    if FAULTS.search(content):
                        raise ValueError("Resource/model/provider fault; stop without retry")
                    for event in ("asr_ready", "model_complete", "local_ended"):
                        if event in content and event not in observed_phases:
                            observed_phases.add(event)
                            print(f"Device phase: {event}", flush=True)
                    if args.stage in ("restore-settings", "pair-check") and not probe_sent and f"MURAL_DEVICE_PLAYBACK_WAIT {playback_run} 0 " in test_content:
                        acknowledge(0, playback_request(test_content, playback_run, 0))
                        probe_sent = True
                        write_json(evidence / "sync-probe.json", {"run": playback_run, "ack_sent": True, "playback": "NOT REQUESTED"})
                    if args.stage in ("acoustic", "multi", "cancel"):
                        now = time.monotonic()
                        captures = re.findall(r"asr_trial_capture id=([A-Fa-f0-9-]{36})", content)
                        if len(captures) > len(fixtures) or len(captures) != len(set(captures)):
                            raise ValueError("Unexpected/duplicate capture; refuse additional playback")
                        if captures:
                            current = content[content.rfind("capture_started"):]
                            if len(captures) > len(playbacks):
                                if len(captures) != len(playbacks) + 1:
                                    raise ValueError("Missed a capture event")
                                if capture_received is None:
                                    capture_received = now
                                if now - capture_received > 5:
                                    raise ValueError("Capture/UI log gate delayed; refuse late playback")
                                test_log = evidence / "test.log"
                                marker = f"MURAL_DEVICE_RECORD_UI_READY_{len(captures)}"
                                if test_log.exists() and marker in test_log.read_text():
                                    if "asr_trial_send" in current or "capture_started" not in current:
                                        raise ValueError("Capture no longer ready for playback")
                                    if playback is not None:
                                        if "ended_monotonic" not in playback_state:
                                            raise ValueError("Previous playback not finished")
                                        stop_group(playback)
                                    playback = subprocess.Popen(["afplay", str(fixtures[len(playbacks)])], start_new_session=True)
                                    playback_state = dict(pid=playback.pid, turn=captures[-1], started_monotonic=now,
                                                          capture_received_monotonic=capture_received)
                                    playbacks.append(playback_state)
                                    print(f"Playing frozen turn {len(playbacks)}/{len(fixtures)} after native capture/UI gates", flush=True)
                                    capture_received = None
                                    write_json(evidence / "playback.json", playbacks)
                            if playback is not None and "ended_monotonic" not in playback_state:
                                if playback.poll() is not None:
                                    if playback.returncode != 0:
                                        raise ValueError("Acoustic playback failed")
                                    playback_state.update(ended_monotonic=now, exit_code=playback.returncode,
                                                          send_observed_at_completion="asr_trial_send" in current)
                                    write_json(evidence / "playback.json", playbacks)
                                    token = playback_ack_token(test_content, playback_run, len(playbacks), playback_state)
                                    acknowledge(len(playbacks), token)
                                    playback_state["ack_transferred_monotonic"] = time.monotonic()
                                    write_json(evidence / "playback.json", playbacks)
                                elif now - playback_state["started_monotonic"] > 5 or "asr_trial_send" in current:
                                    raise ValueError("Playback overrun or early Send")
                    if capture.poll() is not None:
                        test_log = evidence / "test.log"
                        if not test_log.exists() or not any(marker in test_log.read_text() for marker in ("MURAL_DEVICE_CLEANUP_PASS", "MURAL_DEVICE_MODEL_PHASE_COMPLETE")):
                            # App termination and stdout marker delivery can race at teardown.
                            time.sleep(1)
                            if not test_log.exists() or not any(marker in test_log.read_text() for marker in ("MURAL_DEVICE_CLEANUP_PASS", "MURAL_DEVICE_MODEL_PHASE_COMPLETE")):
                                raise ValueError("Scoped app console stopped before confirmed teardown")
                    if FAULTS.search(log.read_text()):
                        raise ValueError("Resource/model/provider fault; stop without retry")
                bundle = evidence / "baseline.xcresult"
                plans = list((derived / "Build/Products").glob("Mural_iphoneos*.xctestrun"))
                if len(plans) != 1:
                    raise ValueError("Require one fingerprinted prepared xctestrun")
                test_plan = evidence / "runtime.xctestrun"
                test_plan.write_bytes(plistlib.dumps(runtime_test_plan(plans[0], {
                    "MURAL_PHYSICAL_E2E": args.stage,
                    "MURAL_PHYSICAL_PAIR": pair,
                    "MURAL_RESTORE_MEANING": os.environ.get("DEVICE_RESTORE_MEANING", ""),
                    "MURAL_PLAYBACK_RUN": playback_run})))
                command = ["xcodebuild", "-xctestrun", str(test_plan), "-destination", f"platform=iOS,id={udid}",
                           "-destination-timeout", "30", "-parallel-testing-enabled", "NO",
                           "-only-testing:MuralUITests/MuralPhysicalDeviceTests/testNativeBaseline",
                           "-resultBundlePath", str(bundle), "-test-timeouts-enabled", "YES",
                                  "-default-test-execution-time-allowance", "300", "-maximum-test-execution-time-allowance", "300",
                                  "-collect-test-diagnostics", "never", "test-without-building"]
                pipeline = shlex.join(command) + " 2>&1 | tee " + shlex.quote(str(evidence / "test.log")) + " | xcbeautify --is-ci"
                test_started = True
                def halt_playback():
                    if playback is not None:
                        stop_group(playback)
                phases.append(("native_test_command", time.monotonic()))
                run_bounded(["bash", "-o", "pipefail", "-c", pipeline], evidence / "test-formatted.log", 420,
                            env=os.environ.copy(),
                            monitor=monitor, on_stop=halt_playback)
                phases.append(("result_validation", time.monotonic()))
                summary = subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle), "--compact"], timeout=30)
                (evidence / "summary.json").write_bytes(summary)
                check_summary(json.loads(summary))
                if args.stage in ("restore-settings", "pair-check"):
                    text = (evidence / "test.log").read_text()
                    outcome = f"MURAL_DEVICE_PAIR_CHECK_PASS {pair}" if args.stage == "pair-check" else "MURAL_DEVICE_RESTORE_ONLY"
                    if not all(marker in text for marker in (outcome, "MURAL_DEVICE_SETTINGS_RESTORED", "MURAL_DEVICE_CLEANUP_PASS", "MURAL_DEVICE_PLAYBACK_ACK_0")):
                        raise ValueError("Model-free selection/restoration not confirmed")
                    if re.search(r"firered_native_begin|asr_trial_capture|model_request|asr_ready", log.read_text()):
                        raise ValueError("Unexpected model/capture work during model-free verification")
                    write_json(evidence / "result.json", {"settings_restoration": "PASS", "pair": pair, "models": "NOT REQUESTED"})
                else:
                    pid = baseline_events(log.read_text())
                    if "MURAL_DEVICE_BASELINE_UI_PASS" not in (evidence / "test.log").read_text():
                        raise ValueError("Native outcome marker missing")
                    turn = None
                    if args.stage in ("acoustic", "multi", "cancel"):
                        if len(playbacks) != len(fixtures) or any("ack_transferred_monotonic" not in item for item in playbacks):
                            raise ValueError("Acoustic playback not completed")
                        turn = (cancellation_events(log.read_text(), pid) if args.stage == "cancel"
                                else acoustic_events(log.read_text(), pid, expected_count=len(fixtures)))
                    if args.stage == "cancel" and "MURAL_DEVICE_CANCELLATION_PASS" not in (evidence / "test.log").read_text():
                        raise ValueError("Cancellation recovery UI outcome missing")
                    if args.stage == "multi" and "MURAL_DEVICE_PERSISTENCE_PASS" not in (evidence / "test.log").read_text():
                        raise ValueError("Relaunch persistence marker missing")
                    write_json(evidence / "result.json", {"native_control": "PASS", "real_model": "PASS", "app_pid": pid,
                        "acoustic": "PASS" if turn else "NOT RUN", "turn": turn,
                        "lifecycle": "End during recording, drain, distinct new conversation: PASS" if args.stage == "cancel" else "NOT RUN",
                        "audible_output": "NOT VERIFIED", "persistence_relaunch": "PASS" if args.stage == "multi" else "NOT RUN"})
            code = 0
        except (Exception, KeyboardInterrupt) as error:
            write_json(evidence / "failure.json", {"error": str(error), "type": type(error).__name__})
            print(f"{'FAIL' if test_started or args.stage == 'prepare' else 'BLOCKED'}: {error}", file=sys.stderr)
        finally:
            phases.append(("cleanup", time.monotonic()))
            for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
                signal.signal(sig, signal.SIG_IGN)
            if playback is not None:
                try:
                    stop_group(playback)
                except Exception as error:
                    cleanup_errors.append(str(error))
            if capture is not None:
                try:
                    stop_group(capture)
                except Exception as error:
                    cleanup_errors.append(str(error))
            if capture_file:
                capture_file.close()
                try:
                    after = subprocess.check_output(["xcrun", "devicectl", "device", "info", "processes", "--device", udid,
                                                     "--search", "Mural", "--timeout", "20"], text=True, timeout=25)
                    (evidence / "phone-after.txt").write_text(after)
                    if "Mural.app/Mural" in after or "MuralUITests-Runner.app" in after:
                        cleanup_errors.append("Owned phone process remains; inspect before another run")
                except Exception as error:
                    cleanup_errors.append(str(error))
            phone = "not launched"
            if test_started:
                text = (evidence / "test.log").read_text() if (evidence / "test.log").exists() else ""
                phone = "ended, drained, terminated" if "MURAL_DEVICE_CLEANUP_PASS" in text else "UNCONFIRMED"
                if phone == "UNCONFIRMED":
                    cleanup_errors.append("Phone teardown unconfirmed: inspect owned XCTest/Mural work before another run")
            write_json(evidence / "cleanup.json", {"cleanup": "FAIL" if cleanup_errors else "PASS", "errors": cleanup_errors,
                       "phone": phone, "settings": "restored by XCTest if changed; unconfirmed when teardown missing" if test_started else "unchanged",
                       "playback": "owned afplay stopped" if playback is not None else "Mac playback not started", "room_capture": "not started"})
    ended = time.monotonic()
    timings = {"total_seconds": ended - started, "stage": args.stage,
               "host_phases_seconds": phase_durations(phases, ended),
               "scope": "Host command through cleanup, excluding report rendering; prepare/build is a separate command",
               "native_scope": "Device uptime intervals inside native_test_command, overlapping host phases; do not add to host total"}
    try:
        test_log = evidence / "test.log"
        timings["native_intervals_seconds"] = native_phase_durations(test_log.read_text()) if test_log.exists() else {}
    except ValueError as error:
        timings["native_timing_error"] = str(error)
        code = 1
    write_json(evidence / "timings.json", timings)
    summarize_run(evidence)
    return code or bool(cleanup_errors)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"Physical verification refused: {error}", file=sys.stderr)
        sys.exit(1)
