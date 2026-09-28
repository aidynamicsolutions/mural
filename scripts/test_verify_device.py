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
                           phase_durations, native_phase_durations, playback_ack_token, runtime_test_plan, consumed_ack_copy, reviewed_fixture, resource_events, capture_readiness, provisioning_events, provisioning_recovery_events)


def refuses(operation):
    try:
        operation()
    except (ValueError, RuntimeError, subprocess.TimeoutExpired):
        return
    raise AssertionError("Unsafe input accepted")


if __name__ == "__main__":
    # Runtime integration failure matrix: probe UI leaks into Talk candidate,
    # runtime/compiler flag missing, weights bundled, or ordinary project mutated.
    root = Path(__file__).resolve().parents[1]
    ordinary = (root / "Mural.xcodeproj/project.pbxproj").read_bytes()
    with tempfile.TemporaryDirectory() as output:
        subprocess.run([sys.executable, str(root / "scripts/generate_project.py"),
                        "--firered-runtime", "--output-directory", output], check=True, timeout=30)
        generated = (Path(output) / "Mural.xcodeproj/project.pbxproj").read_text()
        assert "App/Native/FireRedRuntime.mm" in generated
        assert "MURAL_FIRERED_RUNTIME" in generated
        assert "Probe.mm" not in generated and "MURAL_FIRERED_FILE_PROBE" not in generated
        assert "encoder.int8.onnx" not in generated and "decoder.int8.onnx" not in generated
    assert (root / "Mural.xcodeproj/project.pbxproj").read_bytes() == ordinary
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
    # Resource playback uses the reviewed duration, not the routine five-second cap.
    long_playback = {**completed, "ended_monotonic": 20.0}
    assert playback_ack_token(request, run, 1, long_playback, timeout=11) == nonce
    refuses(lambda: playback_ack_token(request, run, 1, long_playback))
    refuses(lambda: playback_ack_token(request, run, 1, long_playback, timeout=100))
    # Reproduced transport race: native consumed/deleted the exact receipt before
    # devicectl's post-copy stat. Only exact current nonce consumption plus that
    # specific missing-node error can recover; other transfer failures still fail.
    destination = f"tmp/mural-playback-{run}-0.txt"
    copy_error = f"ERROR: Failed to retrieve the file node for {destination} (com.apple.dt.CoreDeviceError error 7000 (0x1B58))\n"
    consumed = f"MURAL_DEVICE_PLAYBACK_ACK_0 {run} {nonce}\n"
    assert consumed_ack_copy(copy_error, consumed, run, 0, nonce)
    for bad in ("", consumed.replace(nonce, run), consumed.replace("ACK_0", "ACK_1"), consumed + consumed):
        assert not consumed_ack_copy(copy_error, bad, run, 0, nonce)
    for bad in ("device disconnected", copy_error.replace(run, nonce), copy_error + "other failure"):
        assert not consumed_ack_copy(bad, consumed, run, 0, nonce)
    udid = "00008150-000D25942278401C"
    # Pair-extension failure matrix: unknown pair, missing readiness, accidental
    # native FireRed admission before resource approval, and unchanged VI defaults.
    validate_request(udid, "pair-check", True, pair="zh-CN-en")
    validate_request(udid, "pair-check", True, pair="vi-en")
    refuses(lambda: validate_request(udid, "pair-check", False, pair="zh-CN-en"))
    refuses(lambda: validate_request(udid, "pair-check", True, pair="zh-TW-en"))
    # Native build preparation is model-free; no native runtime admission.
    validate_request(udid, "prepare", False, pair="zh-CN-en")
    # Acquisition-only failure matrix: wrong pair/readiness; no actual network,
    # wrong/missing total, no resumed range, unexpected native initialization.
    validate_request(udid, "provision", True, pair="zh-CN-en")
    refuses(lambda: validate_request(udid, "provision", False, pair="zh-CN-en"))
    refuses(lambda: validate_request(udid, "provision", True, pair="vi-en"))
    provision = "Mural[123]: firered_provision_only_enabled\n"
    for name, size in (("decoder.int8.onnx", 417291928), ("encoder.int8.onnx", 817286833), ("tokens.txt", 79172)):
        for offset in range(0, size, 4194304):
            provision += f"Mural[123]: speech_package_range file={name} offset={offset} bytes={min(4194304, size-offset)} total={size}\n"
    provision += "Mural[123]: firered_provision_verified bytes=1234657933 manifest=a302683c199acb2b37e664fd8ba52d7a5d47503d49dfdff06ba861a264329e3d\n"
    resumed = provision[provision.index("Mural[123]: speech_package_range file=decoder.int8.onnx offset=4194304"):]
    assert provisioning_events(provision, resumed_offset=4194304, resumed_log=resumed)["native_models"] == "NOT REQUESTED"
    for bad in ("", provision.replace("1234657933", "1"), provision.replace("offset=4194304", "offset=0"),
                provision + "Mural[123]: firered_native_begin phase=prepare", provision.replace("Mural[123]", "Other[123]")):
        refuses(lambda: provisioning_events(bad, resumed_offset=4194304, resumed_log=resumed))
    refuses(lambda: provisioning_events(provision, resumed_offset=4194304, resumed_log=provision))
    refuses(lambda: provisioning_events(provision + "\nMural[123]: firered_provision_fault reason=setup-failed", resumed_offset=4194304, resumed_log=resumed))
    # Recovery must retain graphs, resume exactly the owned job, transfer only the
    # missing token object and reach real verified activation with no setup/native fault.
    job = "8991E43E-E606-4F00-93BF-EE5273A189FD"
    recovery = f"Mural[456]: firered_provision_only_enabled\nMural[456]: speech_setup event=job_started job={job} stage=checking\n"
    recovery += "Mural[456]: speech_package_range file=tokens.txt offset=0 bytes=79172 total=79172\n"
    recovery += "Mural[456]: firered_provision_verified bytes=1234657933 manifest=a302683c199acb2b37e664fd8ba52d7a5d47503d49dfdff06ba861a264329e3d\n"
    assert provisioning_recovery_events(recovery, job)["network_bytes_written"] == 79172
    for bad in ("", recovery.replace(job, run), recovery.replace("bytes=79172", "bytes=1"),
                recovery + "Mural[456]: firered_provision_fault reason=setup-failed", recovery + "Mural[456]: firered_native_begin phase=prepare",
                recovery + "Mural[456]: speech_package_range file=encoder.int8.onnx offset=0 bytes=4194304 total=817286833"):
        refuses(lambda: provisioning_recovery_events(bad, job))

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
    # Resource evidence failure matrix: wrong/current PID, wrong pair, duplicate
    # native work, duration >60, missing release, short idle/post-drain, warning,
    # backgrounding, incomplete TTS, and missing actual phase memory samples.
    resource_rows = [events[0], "firered_resource phase=baseline uptime=1.0",
        "local_talk_model_selected pair=zh-CN-en model=FireRedASR2-AED",
        "firered_native_begin phase=prepare uptime=10.0 cpu_threads=1",
        "firered_native_return phase=prepare uptime=20.0 seconds=10.0 cancelled=false",
        "asr_ready", "tts_finished", "firered_resource phase=ready uptime=30.0",
        "firered_native_begin phase=decode uptime=40.0 samples=16000",
        "firered_native_return phase=decode uptime=42.0 seconds=2.0 cancelled=false",
        "model_complete", "local_reply_complete", "tts_finished",
        "firered_resource phase=turn-complete uptime=50.0",
        "firered_resource phase=end-requested uptime=410.0",
        "asr_memory model=firered-v2-aed-int8 stage=released footprint_bytes=100",
        "firered_resource phase=owner-drained uptime=411.0",
        "firered_resource phase=post-drain-2 uptime=413.0",
        "firered_resource phase=post-drain-10 uptime=421.0",
        "firered_resource phase=post-drain-30 uptime=441.0"]
    resource_rows = [x + ' footprint_bytes=100 headroom_bytes=200 thermal_state=0' if 'firered_resource phase=' in x else x for x in resource_rows]
    resource_log = '\n'.join(prefix + x for x in resource_rows)
    assert resource_events(resource_log)['idle_seconds'] == 360
    for bad in (resource_log.replace('footprint_bytes=100 headroom_bytes', 'footprint_bytes=0 headroom_bytes'),
                resource_log.replace('phase=owner-drained', 'phase=not-drained'),
                resource_log.replace('Mural[123]', 'Mural[999]', 1),
                resource_log.replace('pair=zh-CN-en', 'pair=vi-en'),
                resource_log.replace('seconds=10.0', 'seconds=61.0'),
                resource_log.replace('phase=end-requested uptime=410.0', 'phase=end-requested uptime=409.0'),
                resource_log.replace('post-drain-30 uptime=441.0', 'post-drain-30 uptime=440.0'),
                resource_log.replace('stage=released', 'stage=not-released'),
                resource_log.replace('tts_finished', 'no-speech'),
                resource_log + '\n' + prefix + 'firered_resource_fault reason=background',
                resource_log + '\n' + prefix + 'asr_memory_warning',
                resource_log + '\n' + prefix + resource_rows[3]):
        refuses(lambda: resource_events(bad))
    # Capture readiness: exact attached PID/date interval, actual exported stacks
    # and VM rows. TOC/Recording started alone or another process is insufficient.
    toc = '<trace-toc><run number="1"><info><target><process pid="123"/></target><summary><start-date>2026-09-28T00:00:00Z</start-date><end-date>2026-09-28T00:00:05Z</end-date></summary></info></run></trace-toc>'
    baseline_xml = '<trace-query-result><node xpath="Allocations"><row><backtrace><frame name="malloc"/></backtrace></row></node><node xpath="VM"><row address-range="0x1000 - 0x2000" dirty-size="4096"/></node></trace-query-result>'
    assert capture_readiness(toc, baseline_xml, '123')['vm_rows'] == 1
    for bad_toc, bad_xml in ((toc.replace('123','999'),baseline_xml),(toc,baseline_xml.replace('malloc','&lt;Call stack limit reached&gt;')),(toc,'<trace-query-result/>'),(toc.replace('05Z','00Z'),baseline_xml)):
        refuses(lambda: capture_readiness(bad_toc,bad_xml,'123'))
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
        # Fixture admission failure matrix: unreviewed/empty reference or scoring,
        # hash drift, duplicate ID, escaping paths, stereo audio, wrong duration,
        # or a playback/ACK budget that consumes the 30-second recording cap.
        import hashlib
        import json
        import wave
        wav = root / "clip.wav"
        with wave.open(str(wav), "wb") as audio:
            audio.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
            audio.writeframes(b'\0\0' * (8 * 16000))
        clip = dict(id="test", file="clip.wav", sha256=hashlib.sha256(wav.read_bytes()).hexdigest(),
                    reviewed=True, reviewer="host-test-only", reference="test reference",
                    duration_seconds=8.0)
        manifest = root / "fixtures.json"
        data = dict(scoring="NFC; no script conversion", clips=[clip])
        manifest.write_text(json.dumps(data))
        admitted = reviewed_fixture(manifest, "test")
        assert admitted["playback_timeout_seconds"] == 11
        assert admitted["ack_timeout_seconds"] == 18
        assert admitted["reference"] == "test reference"
        for change in ({"reviewed": False}, {"reviewed": "true"}, {"reviewer": ""},
                       {"reference": ""}, {"sha256": "0" * 64}, {"file": "../clip.wav"},
                       {"duration_seconds": 7.0}, {"duration_seconds": float("nan")}):
            manifest.write_text(json.dumps({**data, "clips": [{**clip, **change}]}))
            refuses(lambda: reviewed_fixture(manifest, "test"))
        manifest.write_text(json.dumps({**data, "scoring": ""}))
        refuses(lambda: reviewed_fixture(manifest, "test"))
        manifest.write_text(json.dumps({**data, "clips": [clip, clip]}))
        refuses(lambda: reviewed_fixture(manifest, "test"))
        for channels, seconds in ((2, 8), (1, 22)):
            with wave.open(str(wav), "wb") as audio:
                audio.setparams((channels, 2, 16000, 0, "NONE", "not compressed"))
                audio.writeframes(b'\0\0' * channels * seconds * 16000)
            manifest.write_text(json.dumps({**data, "clips": [{**clip, "duration_seconds": seconds,
                "sha256": hashlib.sha256(wav.read_bytes()).hexdigest()}]}))
            refuses(lambda: reviewed_fixture(manifest, "test"))
        # Isolated generation must preserve the ordinary project/signing settings,
        # anchor source/package paths to the checkout and preserve locked versions.
        checkout = Path(__file__).resolve().parent.parent
        protected = [checkout / "Mural.xcodeproj/project.pbxproj", checkout / "Config/Local.xcconfig"]
        before = [p.read_bytes() if p.exists() else None for p in protected]
        subprocess.run([sys.executable, str(checkout / "scripts/generate_project.py"),
                        "--firered-file-probe", "--output-directory", str(root)], check=True)
        generated = (root / "Mural.xcodeproj/project.pbxproj").read_text()
        assert 'MURAL_FIRERED_FILE_PROBE' in generated and 'Probe.mm' in generated
        assert f'projectDirPath = "{checkout}"' in generated
        assert f'relativePath = "{checkout}"' in generated
        assert [p.read_bytes() if p.exists() else None for p in protected] == before
        resolved_path = "Mural.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        assert (root / resolved_path).read_bytes() == (checkout / resolved_path).read_bytes()
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
        # Native proof may never reuse ordinary compiler flags, even at the same
        # claimed hash; both actual flags must occur in the app invocation.
        refuses(lambda: compiler_proof(new_log, identity, [receipt], firered=True))
        old_log.write_text("swiftc -module-name Mural -DMURAL_FIRERED_RUNTIME -D MURAL_COREAI_TALK -O\n")
        refuses(lambda: compiler_proof(new_log, identity, [receipt], firered=True))
        linker = "clang++ -lsherpa-onnx-c-api -framework onnxruntime -o /build/Release-iphoneos/Mural.app/Mural\n"
        old_log.write_text(old_log.read_text() + linker)
        assert compiler_proof(new_log, identity, [receipt], firered=True)["linker_command"] == linker.strip()
        old_log.write_text("Requested OTHER_SWIFT_FLAGS=-D MURAL_COREAI_TALK\n")
        refuses(lambda: compiler_proof(new_log, identity, [receipt]))
        pidfile = root / "child.pid"
        code = "import os,time; open(%r,'w').write(str(os.getpid())); time.sleep(30)" % str(pidfile)
        refuses(lambda: run_bounded([sys.executable, "-c", code], root / "timeout.log", 1))
        pid = int(pidfile.read_text())
        assert subprocess.run(["ps", "-p", str(pid)], stdout=subprocess.DEVNULL).returncode != 0
    print("PASS: request, result, fresh-process evidence, safety faults and timeout cleanup (host-only)")
