#!/usr/bin/env python3
"""Host-only safety checks, written before the device runner. Never contacts a phone.

Failure matrix: implicit/simulator/wrong-device selection; missing opt-in; missing
or skipped tests; stale/wrong-process backend evidence; model/resource faults;
child still running after timeout/cancellation. Real UI/model checks use XCTest.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from verify_device import (validate_request, check_summary, baseline_events, acoustic_events, run_bounded,
                           compiler_proof, select_prepared, idle_process, cancellation_events, APP_EXECUTABLE,
                           phase_durations, native_phase_durations, playback_ack_token, runtime_test_plan)


def refuses(operation):
    try:
        operation()
    except (ValueError, RuntimeError, subprocess.TimeoutExpired):
        return
    raise AssertionError("Unsafe input accepted")


if __name__ == "__main__":
    # Timing failure matrix: nonmonotonic/duplicate boundaries; missing or repeated
    # native markers; failed/incomplete tests; mixing host and device clock domains.
    phases = [("preflight", 10.0), ("install", 12.0), ("cleanup", 15.0)]
    assert phase_durations(phases, 16.0) == {"preflight": 2.0, "install": 3.0, "cleanup": 1.0}
    refuses(lambda: phase_durations(phases, 14.0))
    refuses(lambda: phase_durations([("start", 2), ("end", 1)], 3))
    refuses(lambda: phase_durations([("start", 1), ("start", 2)], 3))
    assert phase_durations([], 3) == {}
    native = "noise\nMURAL_DEVICE_TIMING activated 100.0\nMURAL_DEVICE_TIMING ready 104.0\n"
    assert native_phase_durations(native) == {"activated_to_ready": 4.0}
    assert native_phase_durations("incomplete test, no markers") == {}
    assert native_phase_durations("MURAL_DEVICE_TIMING activated 100.0") == {}
    refuses(lambda: native_phase_durations(native + "MURAL_DEVICE_TIMING ready 105.0\n"))
    refuses(lambda: native_phase_durations(native + "MURAL_DEVICE_TIMING ended 99.0\n"))
    # Completion handshake failure matrix: missing/stale/wrong-turn/duplicate UI
    # request; invalid nonce; failed, overlong or unfinished playback; early Send.
    run = "11111111-2222-3333-4444-555555555555"
    nonce = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    request = f"MURAL_DEVICE_PLAYBACK_WAIT {run} 1 {nonce}\n"
    completed = dict(started_monotonic=10.0, ended_monotonic=13.0, exit_code=0,
                     send_observed_at_completion=False)
    assert playback_ack_token(request, run, 1, completed) == nonce
    for bad_log in ("", request.replace(run, nonce), request.replace(" 1 ", " 2 "),
                    request + request, request.replace(nonce, "bad-token")):
        refuses(lambda: playback_ack_token(bad_log, run, 1, completed))
    for changes in ({"exit_code": 1}, {"ended_monotonic": None},
                    {"ended_monotonic": 16.0}, {"ended_monotonic": 9.0},
                    {"send_observed_at_completion": True}):
        refuses(lambda: playback_ack_token(request, run, 1, {**completed, **changes}))
    udid = "00008150-000D25942278401C"
    validate_request(udid, "prepare", False)
    validate_request(udid, "baseline", True)
    validate_request(udid, "status", False)
    refuses(lambda: validate_request(udid, "stop-idle", False))
    processes = [{"processIdentifier": 123, "executable": "file:///apps/Mural.app/Mural"}]
    assert idle_process(processes, "file:///apps/Mural.app/", 123) == 123
    refuses(lambda: idle_process(processes, "file:///apps/Mural.app/", 999))
    refuses(lambda: idle_process(processes, "file:///apps/Other.app/", 123))
    refuses(lambda: idle_process(processes + processes, "file:///apps/Mural.app/", 123))
    for bad in ("", "booted", "C094F154-7674-4A17-9F6B-319959B1F49A", "../phone"):
        refuses(lambda: validate_request(bad, "prepare", False))
    refuses(lambda: validate_request(udid, "baseline", False))
    validate_request(udid, "acoustic", True)
    refuses(lambda: validate_request(udid, "acoustic", False))
    good = dict(passedTests=1, failedTests=0, skippedTests=0, totalTestCount=1)
    check_summary(good)
    for key in good:
        bad = {**good, key: 0 if good[key] else 1}
        refuses(lambda: check_summary(bad))
    refuses(lambda: check_summary({}))
    prefix = "Sep 27 12:00:00 Mural[123] <Notice>: "
    events = ["local_talk_asr_backend backend=Core AI GPU-preferred encoder + Core ML decoder (staged)",
              "preparation_idle_timer acquired=true", "asr_staged_prepared backend=coreai-gpu", "asr_ready",
              "preparation_idle_timer restored=", "model_complete", "local_reply_complete", "local_ended"]
    log = "\n".join(prefix + event for event in events)
    baseline_events(log)
    baseline_events(log.replace("Mural[123]", "Mural[123:456]"))
    baseline_events(log + "\n" + prefix + events[0])
    refuses(lambda: baseline_events(log + "\n" + prefix.replace("123", "456") + events[0]))
    for event in events:
        refuses(lambda: baseline_events(log.replace(prefix + event, "")))
    refuses(lambda: baseline_events(log.replace("model_complete", "model_complete", 1).replace(
        prefix + "model_complete", prefix.replace("123", "456") + "model_complete")))
    for fault in ("asr_memory_warning", "asr_turn_failed", "thermal_state=2", "asr_staged_decoder_speculative_failed"):
        refuses(lambda: baseline_events(log + "\n" + prefix + fault))
    turn = "11111111-2222-3333-4444-555555555555"
    acoustic = log + "\n" + "\n".join(prefix + event for event in [
        "capture_started", f"asr_trial_capture id={turn} uptime=1", f"asr_trial_send id={turn} uptime=14",
        "asr_input source_frames=100 converted_frames=100", f"asr_trial_final id={turn} captured_seconds=12"])
    acoustic_events(acoustic, "123")
    next_turn = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    second = acoustic[acoustic.index(prefix + "capture_started"):].replace(turn, next_turn)
    acoustic_events(acoustic + "\n" + second, "123", expected_count=2)
    refuses(lambda: acoustic_events(acoustic, "123", expected_count=2))
    refuses(lambda: acoustic_events(acoustic + "\n" + second.replace("converted_frames=100", "converted_frames=0"), "123", expected_count=2))
    refuses(lambda: acoustic_events(acoustic.replace("converted_frames=100", "converted_frames=0"), "123"))
    refuses(lambda: acoustic_events(acoustic.replace(f"asr_trial_final id={turn}", "asr_trial_final id=WRONG"), "123"))
    refuses(lambda: acoustic_events(acoustic + "\n" + prefix + f"asr_trial_capture id={turn}", "123"))
    cancelled = prefix + "capture_started\n" + prefix + f"asr_trial_capture id={turn}\n" + prefix + "local_ended\n" + second
    cancellation_events(cancelled, "123")
    refuses(lambda: cancellation_events(cancelled.replace("local_ended", f"asr_trial_final id={turn}"), "123"))
    refuses(lambda: cancellation_events(cancelled + "\n" + prefix + f"asr_trial_send id={turn}", "123"))
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        # Prepared-run failure matrix: wrong runner/app, wrong format, extra targets,
        # relocated __TESTROOT__, source mutation, lost environment and screen evidence.
        import plistlib
        plan = root / "prepared.xctestrun"
        payload = {"__xctestrun_metadata__": {"FormatVersion": 1}, "MuralUITests": {
            "TestHostBundleIdentifier": "com.kevintruong.mural.dev.physicaltests.xctrunner",
            "UITargetAppPath": "__TESTROOT__/Release-iphoneos/Mural.app",
            "TestHostPath": "__TESTROOT__/Release-iphoneos/MuralUITests-Runner.app",
            "DependentProductPaths": ["__TESTROOT__/Release-iphoneos/Mural.app"],
            "EnvironmentVariables": {"EXISTING": "kept"}}}
        plan.write_bytes(plistlib.dumps(payload))
        original = plan.read_bytes()
        resolved = runtime_test_plan(plan, {"MURAL_PHYSICAL_E2E": "multi"})
        target = resolved["MuralUITests"]
        assert target["UITargetAppPath"] == str(root / "Release-iphoneos/Mural.app")
        assert target["DependentProductPaths"] == [str(root / "Release-iphoneos/Mural.app")]
        assert target["EnvironmentVariables"] == {"EXISTING": "kept", "MURAL_PHYSICAL_E2E": "multi"}
        assert target["SystemAttachmentLifetime"] == "keepAlways"
        assert plan.read_bytes() == original
        for field in ("TestHostBundleIdentifier", "UITargetAppPath"):
            bad = {**payload, "MuralUITests": {**payload["MuralUITests"], field: "wrong"}}
            plan.write_bytes(plistlib.dumps(bad))
            refuses(lambda: runtime_test_plan(plan, {}))
        plan.write_bytes(plistlib.dumps({**payload, "UnexpectedTests": {}}))
        refuses(lambda: runtime_test_plan(plan, {}))
        plan.write_bytes(plistlib.dumps({**payload, "__xctestrun_metadata__": {"FormatVersion": 2}}))
        refuses(lambda: runtime_test_plan(plan, {}))
        # Incremental builds can reuse proven identical bytes, never a requested flag alone.
        import json
        identity = {"source_sha256": "source", "artifacts": {APP_EXECUTABLE: "binary"}}
        old = root / "old"; old.mkdir()
        receipt = old / "prepared.json"
        receipt.write_text(json.dumps({"udid": udid, "identity": identity}))
        old_log = old / "build.log"
        old_log.write_text("swiftc -module-name Mural -D MURAL_COREAI_TALK -O\n")
        new_log = root / "build.log"; new_log.write_text("Build succeeded; no compilation needed\n")
        proof = compiler_proof(new_log, identity, [receipt])
        assert proof["app_sha256"] == "binary" and proof["reused_from"] == str(old_log)
        assert select_prepared(udid, identity, [receipt]) == receipt
        refuses(lambda: select_prepared(udid, {**identity, "source_sha256": "changed"}, [receipt]))
        refuses(lambda: select_prepared("00008150-0000000000000000", identity, [receipt]))
        refuses(lambda: compiler_proof(new_log, {**identity, "artifacts": {APP_EXECUTABLE: "changed"}}, [receipt]))
        old_log.write_text("Requested OTHER_SWIFT_FLAGS=-D MURAL_COREAI_TALK\n")
        refuses(lambda: compiler_proof(new_log, identity, [receipt]))
        pidfile = root / "child.pid"
        code = "import os,time; open(%r,'w').write(str(os.getpid())); time.sleep(30)" % str(pidfile)
        refuses(lambda: run_bounded([sys.executable, "-c", code], root / "timeout.log", 1))
        pid = int(pidfile.read_text())
        assert subprocess.run(["ps", "-p", str(pid)], stdout=subprocess.DEVNULL).returncode != 0
    print("PASS: request, result, fresh-process evidence, safety faults and timeout cleanup (host-only)")
