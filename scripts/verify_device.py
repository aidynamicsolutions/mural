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
import xml.etree.ElementTree as ET

from verify_simulator import Interrupted, interrupted, stop_group, write_json

ROOT = Path(__file__).resolve().parent.parent
APP_ID = "com.kevintruong.mural.dev"
BREEZE_STAGES = ("breeze-check", "breeze-acoustic", "breeze-multi", "breeze-traditional", "breeze-history", "breeze-support", "breeze-finish", "breeze-profile-check", "breeze-profile")
TEST_ID = APP_ID + ".physicaltests"
BACKEND = "Core AI GPU-preferred encoder + Core ML decoder (staged)"
APP_EXECUTABLE = "Build/Products/Release-iphoneos/Mural.app/Mural"
EVIDENCE_ROOT = ROOT / ".build/verification/physical-iphone-e2e"
# Only the explicit non-stopping notification is advisory. Old stops, probe warnings
# and every genuine model/resource/thermal fault still fail, even on that same log row.
FAULTS = re.compile(r"asr_memory_warning(?! stopped=false continuing=true\b)|ios_memory_warning|tts_safety_stop|thermal_state=[23]\b|"
                    r"asr_(?:preparation|turn|staged_decoder_wait|staged_decoder_speculative)_failed|"
                    r"OpenAI request attempted|local_reply_failed|model_failed|firered_resource_fault|firered_provision_fault|firered_vad_unavailable")


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


def playback_ack_token(log, run, index, playback, timeout=5):
    token = playback_request(log, run, index)
    start, end = playback.get("started_monotonic"), playback.get("ended_monotonic")
    if (not 0 < timeout <= 21 or start is None or end is None or not 0 <= end - start <= timeout or
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


def breeze_fixture_ids(stage, requested=None):
    if requested:
        if stage != "breeze-acoustic" or requested not in ("M00A-switch", "F00A-switch", "M00A-english"):
            raise ValueError("One-clip override requires the acoustic stage and an existing reviewed clip")
        return [requested]
    return {"breeze-acoustic": ["M00A-switch"], "breeze-multi": ["F00A-switch", "M00A-english"],
            "breeze-traditional": ["M00A-english"], "breeze-support": ["M00A-english"]}[stage]


def expected_console_stop(test_log):
    # Intent permits closure only. Final XCTest/settings/cleanup checks still prove
    # successful termination, so this cannot convert a crash or failed test to PASS.
    return any(marker in test_log for marker in (
        'MURAL_DEVICE_TERMINATE_REQUESTED', 'MURAL_DEVICE_CLEANUP_PASS', 'MURAL_DEVICE_MODEL_PHASE_COMPLETE'))


def check_profiler_exit(exit_code, test_log):
    if exit_code is not None and not expected_console_stop(test_log):
        raise ValueError('Profiler stopped before native cleanup')


def breeze_history_fixture(source, udid):
    prior = json.loads((source / 'session.json').read_text())
    result = json.loads((source / 'result.json').read_text())
    check_summary(json.loads((source / 'summary.json').read_text()))
    if ((source / 'failure.json').exists() or prior.get('udid') != udid
            or prior.get('stage') not in ('breeze-acoustic', 'breeze-multi')
            or prior.get('pair') != 'breeze-zh-CN-en'
            or json.loads((source / 'cleanup.json').read_text()).get('cleanup') != 'PASS'
            or result.get('backend', {}).get('pair') != 'zh-CN-en'
            or result.get('backend', {}).get('model') != 'breeze-asr25-pal8-v1'):
        raise ValueError("History requires this phone's successful, cleaned-up native Simplified conversation")
    session = str(uuid.UUID(result.get('session', ''))).upper()
    turns = result.get('turns', [])
    if not 1 <= len(turns) <= 2 or any(set(turn) != {'raw', 'display', 'reply'} or
            any(not isinstance(value, str) or not value or len(value.encode('utf-8')) > 500_000
                for value in turn.values()) for turn in turns):
        raise ValueError('Missing bounded exact native conversation expectations')
    return {'session': session, 'turns': turns}


def validate_breeze_memory_poc(stage, pair, enabled):
    if enabled and not ((stage == "prepare" and pair == "vi-en") or
                        (stage in ("breeze-check", "breeze-acoustic", "breeze-multi", "breeze-support") and pair == "breeze-zh-CN-en")):
        raise ValueError("Memory-warning PoC requires explicit isolated preparation or a Simplified Breeze stage")


def validate_request(udid, stage, ready, pair="vi-en"):
    if not re.fullmatch(r"[0-9A-F]{8}-[0-9A-F]{16}", udid):
        raise ValueError("DEVICE_UDID must be an explicit freshly discovered physical UDID")
    if stage not in ("prepare", "status", "stop-idle", "baseline", "acoustic", "multi", "cancel", "restore-settings", "pair-check", "resource-check", "resource", "provision") + BREEZE_STAGES:
        raise ValueError("Unknown physical stage")
    if pair not in ("vi-en", "zh-CN-en", "breeze-zh-CN-en"):
        raise ValueError("Unknown physical test pair")
    if (stage in BREEZE_STAGES) != (pair == "breeze-zh-CN-en"):
        raise ValueError("Breeze requires its explicit ordinary-build stage and pair")
    if pair == "zh-CN-en" and stage not in ("prepare", "pair-check", "resource-check", "resource", "provision"):
        raise ValueError("FireRed requires an explicit model-free, provisioning or resource stage")
    if stage in ("resource-check", "resource", "provision") and pair != "zh-CN-en":
        raise ValueError("Provisioning/resource stages require the explicit Simplified Chinese candidate")
    if stage not in ("prepare", "status") and not ready:
        window = "protected download-only window on Wi-Fi" if stage == "provision" else "private audible/model-free window"
        raise ValueError(f"Confirm the {window}, idle unlocked phone and closed mirroring, then set DEVICE_READY=YES")


def provisioning_process(log):
    pids = set(re.findall(r'Mural\[(\d+)(?::\d+)?\].*firered_provision_only_enabled', log))
    if len(pids) != 1:
        raise ValueError('Missing unique provisioning app PID')
    pid = pids.pop()
    current = '\n'.join(line for line in log.splitlines() if re.search(rf'Mural\[{pid}(?::\d+)?\]', line))
    if FAULTS.search(current) or re.search(r'firered_native_begin|asr_trial_capture|model_request|asr_ready|local_talk_model_selected|tts_synthesis', current):
        raise ValueError('Native work occurred during acquisition-only qualification')
    return pid, current


def provisioning_events(log, *, resumed_offset, resumed_log):
    """Exact written network coverage and an independently inventoried resumed offset."""
    pid, current = provisioning_process(log)
    expected = {'decoder.int8.onnx': 417291928, 'encoder.int8.onnx': 817286833, 'tokens.txt': 79172}
    pattern = r'speech_package_range file=(\S+) offset=(\d+) bytes=(\d+) total=(\d+)'
    covered = {name: 0 for name in expected}
    for name, offset, count, total in re.findall(pattern, current):
        offset, count, total = int(offset), int(count), int(total)
        if (name not in expected or total != expected[name] or offset != covered[name]
                or not 0 < count <= min(4194304, total - offset)):
            raise ValueError('Network coverage is duplicated, missing or outside the pinned file')
        covered[name] += count
    marker = 'firered_provision_verified bytes=1234657933 manifest=a302683c199acb2b37e664fd8ba52d7a5d47503d49dfdff06ba861a264329e3d'
    if covered != expected or current.count(marker) != 1:
        raise ValueError('Missing full phone-network coverage or verified activation')
    resumed = re.findall(pattern, resumed_log)
    if not 0 < resumed_offset < expected['decoder.int8.onnx'] or not resumed or resumed[0][:2] != ('decoder.int8.onnx', str(resumed_offset)):
        raise ValueError('Download did not resume at the independently observed drained partial length')
    return {'provisioning': 'PASS', 'network_bytes_written': sum(covered.values()), 'resumed_offset': resumed_offset,
            'native_models': 'NOT REQUESTED', 'scope': 'first-download provisioning in an existing installation', 'pid': pid}


def provisioning_recovery_events(log, job):
    pid, current = provisioning_process(log)
    expected = [('tokens.txt', '0', '79172', '79172')]
    if re.findall(r'speech_package_range file=(\S+) offset=(\d+) bytes=(\d+) total=(\d+)', current) != expected:
        raise ValueError('Recovery must transfer only the missing pinned tokens, not redownload the retained graphs')
    marker = 'firered_provision_verified bytes=1234657933 manifest=a302683c199acb2b37e664fd8ba52d7a5d47503d49dfdff06ba861a264329e3d'
    if current.count(marker) != 1 or f'speech_setup event=job_started job={job} ' not in current:
        raise ValueError('Recovery did not resume the known setup and verify/activate its exact package')
    return {'provisioning_recovery': 'PASS', 'network_bytes_written': 79172,
            'verified_package_bytes': 1234657933, 'native_models': 'NOT REQUESTED', 'pid': pid,
            'scope': 'recovery of retained first-download files, not a new empty-location run'}


def retained_provisioning_job(source, udid, evidence):
    """Explicit recovery of this failed test's setup, never arbitrary personal work."""
    prior = json.loads((source / 'session.json').read_text())
    if (prior.get('stage') != 'provision' or prior.get('udid') != udid or prior.get('pair') != 'zh-CN-en'
            or not (source / 'failure.json').is_file()
            or json.loads((source / 'recovery-cleanup.json').read_text()).get('cleanup') != 'PASS'
            or json.loads((source / 'managed-preflight.json').read_text()).get('empty') is not True):
        raise ValueError('Recovery requires the failed, cleaned-up, originally empty provisioning run')
    _, old = provisioning_process((source / 'mural-device.log').read_text())
    totals = {'decoder.int8.onnx': 417291928, 'encoder.int8.onnx': 817286833}
    covered = {name: 0 for name in totals}
    for name, start, size, total in re.findall(r'speech_package_range file=(\S+) offset=(\d+) bytes=(\d+) total=(\d+)', old):
        start, size, total = int(start), int(size), int(total)
        if name not in totals or total != totals[name] or start != covered[name] or not 0 < size <= min(4194304, total-start):
            raise ValueError('Prior graph transfer evidence changed or is incomplete')
        covered[name] += size
    if covered != totals or 'firered_provision_verified ' in old:
        raise ValueError('Recovery is only for completed graphs with missing tokens and no activation')
    jobs = re.findall(r'speech_setup event=job_interrupted job=([A-F0-9-]{36}) ', old)
    if not jobs: raise ValueError('Missing interrupted test-owned setup identity')
    job = jobs[-1]
    domain = ['--device', udid, '--domain-type', 'appDataContainer', '--domain-identifier', APP_ID]
    device_json(['device', 'copy', 'from', *domain, '--source', 'Library/Application Support/Mural/SpeechSetup/job.json',
                 '--destination', str(evidence / 'retained-setup.json')], evidence / 'retained-setup-copy.json')
    retained = json.loads((evidence / 'retained-setup.json').read_text())
    if retained.get('id') != job or retained.get('identity', {}).get('pair') != 'zh-CN-en' or retained.get('downloadsApproved') is not True:
        raise ValueError('Current setup is not the previously approved test-owned job')
    root = 'Library/Application Support/Mural/SpeechModels'
    active = device_json(['device', 'info', 'files', *domain, '--subdirectory', root, '--no-recurse', '--search', 'active-zh-CN-en.json'], evidence / 'retained-active.json')['files']
    if active: raise ValueError('Package already activated; stop instead of pretending to resume a partial')
    path = root + '/.downloads/firered-asr2-int8-374cff18-v1-a302683c199acb2b37e664fd8ba52d7a5d47503d49dfdff06ba861a264329e3d/support'
    files = device_json(['device', 'info', 'files', *domain, '--subdirectory', path, '--no-recurse'], evidence / 'retained-files.json')['files']
    expected = {**totals, 'tokens.txt': 0}
    if len(files) != 3 or {f.get('name'): f['metadata']['size'] for f in files} != expected or any(f['resources'].get('isSymbolicLink') or f['resources'].get('isDirectory') for f in files):
        raise ValueError('Retained inventory differs from completed graphs and empty tokens; preserve and review')
    write_json(evidence / 'retained-source.json', {'source': str(source), 'job': job,
        'old_log_sha256': hashlib.sha256((source / 'mural-device.log').read_bytes()).hexdigest(),
        'action': 'retain graphs, fetch tokens, full rehash, atomic activation; no native load'})
    return job


def managed_fire_red_inventory(udid, evidence):
    """Read only names/metadata in the exact managed tree; never inspect model contents."""
    def rows(path, name, label):
        args = ['device', 'info', 'files', '--device', udid, '--domain-type', 'appDataContainer',
                '--domain-identifier', APP_ID, '--subdirectory', path, '--no-recurse']
        if name: args += ['--search', name]
        return device_json(args, evidence / f'managed-{label}.json')['files']
    path = ''
    for index, name in enumerate(('Library', 'Application Support', 'Mural', 'SpeechModels')):
        found = [row for row in rows(path, name, str(index)) if row.get('name') == name]
        if not found: return {'empty': True, 'missing_component': name}
        if len(found) != 1 or found[0]['resources'].get('isSymbolicLink') or not found[0]['resources'].get('isDirectory'):
            raise ValueError('Unsafe managed package ancestor')
        path = f'{path}/{name}'.lstrip('/')
    root_rows = rows(path, None, 'root')
    if any(row.get('name') == 'active-zh-CN-en.json' for row in root_rows):
        raise ValueError('Managed FireRed active pointer already exists; agree a preservation-safe arrangement')
    for group in ('.downloads', 'packages'):
        directory = next((row for row in root_rows if row.get('name') == group), None)
        if directory:
            if directory['resources'].get('isSymbolicLink') or not directory['resources'].get('isDirectory'):
                raise ValueError('Unsafe managed package directory')
            if rows(f'{path}/{group}', 'firered', group.strip('.')):
                raise ValueError('Managed FireRed files already exist; never delete/reuse them for first-download acceptance')
    return {'empty': True, 'root': path}


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


def resource_events(log):
    if FAULTS.search(log):
        raise ValueError("Resource/model/lifecycle fault; no retry")
    pids = set(re.findall(r'Mural\[(\d+)(?::\d+)?\].*local_talk_asr_backend backend=' + re.escape(BACKEND), log))
    if len(pids) != 1:
        raise ValueError("Require one fresh candidate process")
    pid = pids.pop()
    current = '\n'.join(line for line in log.splitlines() if re.search(rf'Mural\[{pid}(?::\d+)?\]', line))
    if 'local_talk_model_selected pair=zh-CN-en' not in current:
        raise ValueError("Missing actual Simplified pair selection")
    for phase in ('prepare', 'decode'):
        starts = re.findall(rf'firered_native_begin phase={phase} uptime=([0-9.]+)', current)
        returns = re.findall(rf'firered_native_return phase={phase} uptime=([0-9.]+) seconds=([0-9.]+) cancelled=false', current)
        if (len(starts) != 1 or len(returns) != 1 or not 0 < float(returns[0][1]) <= 60
                or not 0 < float(returns[0][0]) - float(starts[0]) <= 60):
            raise ValueError("Require exactly one bounded successful native operation per phase")
    phases = {}
    for phase, stamp, footprint in re.findall(r'firered_resource phase=([a-z0-9-]+) uptime=([0-9.]+) footprint_bytes=(\d+)', current):
        if phase == 'sample':
            continue
        if phase in phases or int(footprint) <= 0:
            raise ValueError("Duplicate phase or missing Mach footprint")
        phases[phase] = float(stamp)
    names = ['baseline', 'ready', 'turn-complete', 'end-requested', 'owner-drained',
             'post-drain-2', 'post-drain-10', 'post-drain-30']
    if any(name not in phases for name in names) or any(phases[b] < phases[a] for a, b in zip(names, names[1:])):
        raise ValueError("Missing/nonmonotonic resource boundary")
    idle = phases['end-requested'] - phases['turn-complete']
    if idle < 360 or any(phases[f'post-drain-{n}'] - phases['owner-drained'] < n for n in (2, 10, 30)):
        raise ValueError("Incomplete loaded-idle or post-drain interval")
    release = current.find('asr_memory model=firered-v2-aed-int8 stage=released')
    drain = current.find('firered_resource phase=owner-drained')
    final = current.find('firered_resource phase=turn-complete')
    if (not 0 <= release < drain or current[:final].count('tts_finished') < 2
            or current[:final].count('model_complete') < 1 or 'local_reply_complete' not in current[:final]):
        raise ValueError("Missing combined tutor/speech completion or actual recognizer release")
    return dict(pid=pid, idle_seconds=idle, phases=phases)


def capture_readiness(toc, exported, pid):
    info = ET.fromstring(toc).find('./run/info')
    if info is None or info.find('./target/process').get('pid') != pid:
        raise ValueError("Profiler target is not the fresh owned app PID")
    start = info.findtext('./summary/start-date')
    end = info.findtext('./summary/end-date')
    if not start or not end or datetime.fromisoformat(end) <= datetime.fromisoformat(start):
        raise ValueError("Missing timed baseline capture interval")
    data = ET.fromstring(exported)
    stacks = [f for f in data.iter('frame') if f.get('name') and not f.get('name').startswith('<')]
    vm = [r for r in data.iter('row') if 'address-range' in r.attrib and 'dirty-size' in r.attrib]
    if not stacks or not vm:
        raise ValueError("Baseline capture has no useful allocation stacks/VM rows; refuse Prepare")
    return dict(pid=pid, start=start, end=end, symbolized_frames=len(stacks), vm_rows=len(vm),
                vm_time_scope='Snapshot(s) within this baseline interval; no exact per-row timestamp exported')


def require_instruments_device(inventory, udid):
    section = None
    for line in inventory.splitlines():
        if line.startswith("== "):
            section = line.strip()
        elif section == "== Devices ==" and line.strip().endswith(f"({udid})"):
            return
    raise ValueError("Exact phone is offline or missing in Instruments; no install or model work permitted")


def resource_capture_probe(udid, pid, evidence, deadline, monitor):
    """Prove the capture path on this process before admitting any model work."""
    options = {"Allocations": {"discardEventsForFreedMemory": False,
        "discardUnrecordedDataUponStop": True, "identifyVirtualCppObjects": True,
        "enableNSZombieDetection": False, "onlyTrackVMAllocations": False, "recordReferenceCounts": False,
        "recordedTypes": [{"action": "record", "enabled": True, "match": "contains", "type": "*"},
                          *[{"action": "ignore", "enabled": False, "match": "hasPrefix", "type": name}
                            for name in ("NS", "CF", "Malloc")]]},
        "Points of Interest": {"excludeOSLogs": True},
        "VM Tracker": {"automaticSnapshotEnabled": True, "snapshotIntervalInSeconds": 3}}
    write_json(evidence / 'allocation-options.json', options)
    command = ['xcrun', 'xctrace', 'record', '--template', 'Allocations', '--instrument', 'VM Tracker',
               '--device', udid, '--attach', pid, '--recording-options', str(evidence / 'allocation-options.json')]
    def budget(maximum):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError('Capture-readiness phase exhausted; no model work permitted')
        return min(maximum, remaining)
    trace = evidence / 'baseline.trace'
    run_bounded(command + ['--time-limit', '15s', '--output', str(trace)],
                evidence / 'baseline-capture.log', budget(30), monitor=monitor)
    toc = evidence / 'baseline-toc.xml'
    run_bounded(['xcrun', 'xctrace', 'export', str(trace), '--toc'], toc, budget(10), monitor=monitor)
    exported = evidence / 'baseline-memory.xml'
    def bounded_export():
        monitor()
        if exported.exists() and exported.stat().st_size > 32 * 1024**2:
            raise ValueError('Baseline export exceeds bounded inspection size')
    # The default end selection can export zero VM rows despite recorded snapshots.
    # Select inside the 15-second baseline, retaining the original trace and interval.
    run_bounded(['xcrun', 'xctrace', 'export', str(trace), '--time-end', '14s', '--xpath',
        '/trace-toc/run[@number="1"]/tracks/track/details/detail[@name="Allocations List" or @name="Regions Map"]'],
        exported, budget(25), monitor=bounded_export)
    write_json(evidence / 'capture-readiness.json', capture_readiness(toc.read_text(), exported.read_text(), pid))
    return command


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


def breeze_fault_log(log, memory_poc=False):
    """Keep full evidence; only an idle non-Breeze owner's warning is nonfatal in PoC."""
    marker = "breeze_memory_poc enabled=true thermal_stop_retained=true"
    pids = set(re.findall(r'Mural\[(\d+)(?::\d+)?\].*' + marker, log))
    if pids and not memory_poc:
        raise ValueError("Diagnostic build cannot qualify the normal warning policy")
    lines = []
    for line in log.splitlines():
        if memory_poc and "asr_memory_warning stopped=true model=PhoWhisper CS " in line and "previous_state=Prepare speech models" in line:
            if len(pids) != 1 or not re.search(rf'Mural\[{next(iter(pids))}(?::\d+)?\]', line):
                raise ValueError("Idle warning exception requires the fresh diagnostic process")
            # Do not remove the row or hide other faults, particularly thermal state.
            line = line.replace("asr_memory_warning", "idle_memory_warning_diagnostic")
        lines.append(line)
    return "\n".join(lines)


def breeze_events(log, expected_count, pair="zh-CN-en", memory_poc=False):
    """Fresh real-model evidence, distinct from word accuracy and human listening."""
    if memory_poc and not re.search(r'Mural\[\d+(?::\d+)?\].*breeze_memory_poc enabled=true thermal_stop_retained=true', log):
        raise ValueError("Missing actual diagnostic runtime policy")
    if FAULTS.search(breeze_fault_log(log, memory_poc)) or re.search(r"breeze_vad_unavailable|tts_fallback|breeze_asset_verification_end success=false|firered_native_begin|sensevoice|paraformer", log, re.I):
        raise ValueError("Breeze model/resource fault or alternate backend; no retry")
    pids = set(re.findall(r'Mural\[(\d+)(?::\d+)?\].*local_talk_asr_backend backend=' + re.escape(BACKEND), log))
    if len(pids) != 1:
        raise ValueError("Require one fresh console-owned Mural PID")
    pid = pids.pop()
    if memory_poc and set(re.findall(r'Mural\[(\d+)(?::\d+)?\].*breeze_memory_poc enabled=true thermal_stop_retained=true', log)) != {pid}:
        raise ValueError("Diagnostic marker does not match the current Breeze PID")
    current = '\n'.join(line for line in log.splitlines() if re.search(rf'\bMural\[{pid}(?::\d+)?\]', line))
    selected = re.findall(r'local_talk_model_selected pair=(\S+) model=([^\n]+)', current)
    if len(selected) != 1 or selected[0][0] != pair or not selected[0][1].startswith('Breeze '):
        raise ValueError("Missing single selected Breeze model and frozen pair")
    if (current.count('asr_memory model=breeze-asr25-pal8-v1 stage=loaded') != 1
            or current.count('breeze_inference_begin ') != expected_count
            or current.count('breeze_decode scope=whisperkit-transcribe-not-ui-send') != expected_count):
        raise ValueError("Missing real Breeze load/inference or duplicate recognizer")
    marker = 'breeze_script_display policy=tw2s-han-1d8105a0-v1 raw_preserved=true pair=zh-CN-en'
    if current.count(marker) != (expected_count if pair == 'zh-CN-en' else 0):
        raise ValueError("Missing completed-turn raw-preserving display marker")
    offset = 0
    events = ('local_talk_model_selected', 'asr_ready', 'tts_finished', 'local_ended') if expected_count == 0 else (
        'local_talk_model_selected', 'asr_ready', 'breeze_inference_begin', 'local_reply_complete', 'tts_finished', 'local_ended')
    for event in events:
        found = current.find(event, offset)
        if found < 0:
            raise ValueError('Missing ordered Breeze event: ' + event)
        offset = found + len(event)
    return {'pid': pid, 'pair': pair, 'model': 'breeze-asr25-pal8-v1', 'inferences': expected_count}


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
    paths = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "App", "Core", "Sources", "Config", "UITests",
                                     "Mural.xcodeproj", "Package.swift", "Package.resolved"], cwd=ROOT).decode().split("\0")
    paths += ["scripts/generate_project.py", "Config/Local.xcconfig"]
    if firered:
        paths += [str(p.relative_to(ROOT)) for p in (ROOT / "Tools/ChineseASR/FireRedProbe").glob("Probe.*")]
        paths += ["Tools/ChineseASR/FireRedProbe/pin.json", "App/Native/FireRedRuntime.h", "App/Native/FireRedRuntime.mm", "scripts/build_firered_runtime.sh"]
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
        runtime = ROOT / ".build/firered-runtime"
        native = sorted((runtime / "ios-build/lib").glob("*.a"))
        framework = runtime / "ort-ios/onnxruntime.xcframework/ios-arm64/onnxruntime.framework"
        native += [framework / "onnxruntime", framework / "Info.plist"]
        native += sorted((framework / "Headers").glob("*.h"))
        native += [runtime / "sherpa-onnx/sherpa-onnx/c-api/c-api.h", runtime / "FireRedNotices.txt"]
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
        notices = products / "Mural.app/FireRedNotices.txt"
        if notices.read_bytes() != (runtime / "FireRedNotices.txt").read_bytes():
            raise ValueError("Bundled native notices differ from reviewed runtime build")
        identity["artifacts"][str(notices.relative_to(derived))] = hashlib.sha256(notices.read_bytes()).hexdigest()
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


def compiler_proof(build_log, identity, receipts, firered=False, memory_poc=False):
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
                        and bool(re.search(r"-D ?MURAL_BREEZE_MEMORY_POC\b", line)) == memory_poc
                        and (not firered or re.search(r"-D ?MURAL_FIRERED_RUNTIME\b", line))):
                    compiler = line.strip()
                if ("clang++ " in line and " -lsherpa-onnx-c-api " in line
                        and " -framework onnxruntime " in line and line.rstrip().endswith("/Mural.app/Mural")):
                    linker = line.strip()
        if compiler and (not firered or linker):
            return {"app_sha256": app_hash, "log": str(path), "compiler_command": compiler,
                    "linker_command": linker, "reused_from": str(path) if reused else None}
    raise ValueError("No actual Core AI compiler invocation proves these executable bytes; requested flags alone are insufficient")



def breeze_load_profile(log):
    """Report existing content-free native fences; incomplete/failed loads never look complete."""
    profiles, active, receipt, skipped = [], {}, {}, {}
    pattern = re.compile(r'Mural\[(\d+)(?::\d+)?\].*(coreml_preparation|speech_preparation_step) (.+)')
    for line in log.splitlines():
        match = pattern.search(line)
        if not match:
            continue
        pid, kind, message = match.groups()
        fields = dict(re.findall(r'(\w+)=([^\s]+)', message))
        if fields.get('model') != 'breeze-asr25-pal8-v1':
            continue
        phase = fields.get('phase')
        if kind == 'coreml_preparation':
            if phase == 'receipt':
                receipt[pid] = fields.get('status')
                skipped[pid] = False
            elif phase == 'prewarm_skipped':
                skipped[pid] = True
            elif phase == 'load_begin':
                if pid in active:
                    raise ValueError('Overlapping Breeze load fences')
                profile = dict(pid=pid, receipt_status=receipt.get(pid),
                               prewarm_skipped=skipped.get(pid, False), steps={},
                               components_seconds={}, complete=False, outcome='incomplete')
                profiles.append(profile)
                active[pid] = profile
            elif phase in ('load_end', 'load_failed'):
                if pid not in active:
                    raise ValueError('Breeze load ended without its begin fence')
                profile = active.pop(pid)
                seconds = float(fields['seconds'])
                if not math.isfinite(seconds) or seconds < 0:
                    raise ValueError('Invalid native load duration')
                profile['total_seconds'] = seconds
                completed = sum(profile['components_seconds'].values())
                if completed > seconds + .001:
                    raise ValueError('Component durations exceed their native load fence')
                profile['unattributed_seconds'] = max(0, seconds - completed)
                profile['outcome'] = 'completed' if phase == 'load_end' else fields.get('status', 'failed')
                profile['complete'] = (phase == 'load_end'
                    and set(profile['components_seconds']) == {'MelSpectrogram', 'TextDecoder', 'AudioEncoder'}
                    and len(profile['steps']) == 3
                    and all(step['outcome'] == 'completed' for step in profile['steps'].values()))
        elif phase == 'load':
            if pid not in active:
                raise ValueError('Component event outside its Breeze load fence')
            profile = active[pid]
            identifier, component, outcome = fields['id'], fields['component'], fields['outcome']
            seconds = float(fields['seconds'])
            if not math.isfinite(seconds) or seconds < 0:
                raise ValueError('Invalid component duration')
            if outcome == 'begin':
                if identifier in profile['steps']:
                    raise ValueError('Duplicate component begin')
                profile['steps'][identifier] = dict(component=component, outcome='begin', seconds=seconds)
            else:
                step = profile['steps'].get(identifier)
                if not step or step['component'] != component or step['outcome'] != 'begin':
                    raise ValueError('Missing, mismatched or duplicate component boundary')
                step.update(outcome=outcome, seconds=seconds)
                if outcome == 'completed':
                    if component in profile['components_seconds']:
                        raise ValueError('Duplicate component load')
                    profile['components_seconds'][component] = seconds
    return profiles


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
    device_log = evidence / "mural-device.log"
    if device_log.exists():
        try:
            profile = breeze_load_profile(device_log.read_text())
            if profile:
                write_json(evidence / "model-load-profile.json", profile)
                print("Breeze model loads: " + json.dumps(profile))
        except (ValueError, KeyError) as error:
            print("Breeze load profile unavailable: " + str(error))
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
    import base64
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", choices=("prepare", "status", "stop-idle", "baseline", "acoustic", "multi", "cancel", "restore-settings", "pair-check", "resource-check", "resource", "provision") + BREEZE_STAGES, default=os.environ.get("DEVICE_STAGE", "prepare"))
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
    memory_poc = os.environ.get("DEVICE_BREEZE_MEMORY_POC") == "YES"
    validate_breeze_memory_poc(args.stage, pair, memory_poc)
    if args.stage == "restore-settings" and not os.environ.get("DEVICE_RESTORE_MEANING"):
        raise ValueError("DEVICE_RESTORE_MEANING must be the recorded original preference, never a guessed default")
    os.chdir(ROOT)
    evidence = Path(os.environ.get("EVIDENCE") or
                    f".build/verification/physical-iphone-e2e/{datetime.now():%Y%m%d-%H%M%S}-{os.getpid()}").resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    print(f"Physical {args.stage}: {evidence}", flush=True)
    # Native preparation cannot overwrite the qualified ordinary app/runner.
    breeze_stage = args.stage in BREEZE_STAGES
    breeze_profile = args.stage in ("breeze-profile-check", "breeze-profile")
    trace_name = "model-load.trace" if breeze_profile else "resource.trace"
    breeze_audio = breeze_stage and args.stage not in ("breeze-check", "breeze-history", "breeze-finish", "breeze-profile-check", "breeze-profile")
    history_source = os.environ.get('DEVICE_BREEZE_HISTORY_SOURCE')
    if (args.stage == 'breeze-history') != bool(history_source):
        raise ValueError('Only breeze-history requires DEVICE_BREEZE_HISTORY_SOURCE, the exact passed native run')
    history_fixture = breeze_history_fixture(Path(history_source).resolve(), udid) if history_source else None
    resource_stage = args.stage in ("resource", "resource-check")
    resource_run = args.stage == "resource"
    provision_run = args.stage == "provision"
    recovery_source = os.environ.get('DEVICE_PROVISION_SOURCE')
    if recovery_source and not provision_run:
        raise ValueError('DEVICE_PROVISION_SOURCE is only valid for explicit provisioning recovery')
    recovery_job = None
    firered = pair == "zh-CN-en" and (args.stage == "prepare" or resource_stage or provision_run)
    derived = (ROOT / (".build/firered-talk-device-derived-data" if firered else
                       ".build/breeze-memory-poc-device-derived-data" if memory_poc else
                       ".build/local-mvp-phase-1-device-derived-data")).resolve()
    derived.mkdir(parents=True, exist_ok=True)
    locks = Path(pwd.getpwuid(os.getuid()).pw_dir) / "Library/Caches/ios-verification"
    locks.mkdir(parents=True, exist_ok=True)
    playback_run = str(uuid.uuid4()).upper()
    session = dict(pid=os.getpid(), udid=udid, stage=args.stage, app=APP_ID, runner=TEST_ID,
                   playback_run=playback_run, pair=pair, breeze_memory_poc=memory_poc,
                   configuration="Release", backend=BACKEND, settings="No changes",
                   started_at=datetime.now(timezone.utc).isoformat(), evidence=str(evidence),
                   runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    write_json(evidence / "session.json", session)
    capture = None
    profiler = None
    profiler_file = None
    playback = None
    playback_state = {}
    playbacks = []
    capture_file = None
    test_started = False
    code = 1
    cleanup_errors = []
    with ExitStack() as stack:
        lock_paths = [locks / f"{udid}.lock", derived / ".mural-build.lock"]
        if firered or memory_poc:
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
            if firered and args.stage == "prepare":
                runtime = ROOT / '.build/firered-runtime'
                if runtime.is_symlink() or not runtime.is_dir() or not (runtime / 'runtime-sha256.txt').is_file():
                    raise ValueError('Build the checkout-owned pinned runtime with scripts/build_firered_runtime.sh first')
                # Isolated generation avoids exposing candidate flags to concurrent ordinary builds.
                run_bounded([sys.executable, "scripts/generate_project.py", "--firered-runtime",
                             "--output-directory", str(evidence / "native-project")],
                            evidence / "generation.log", 30)
                project = evidence / "native-project/Mural.xcodeproj"
            base = ["xcodebuild", "-project", str(project), "-scheme", "Mural", "-configuration", "Release",
                    "-destination", f"platform=iOS,id={udid}", "-destination-timeout", "30", "-derivedDataPath", str(derived),
                    f"MURAL_APP_BUNDLE_IDENTIFIER={APP_ID}", f"MURAL_TEST_BUNDLE_IDENTIFIER={TEST_ID}",
                    "OTHER_SWIFT_FLAGS=$(inherited) -D MURAL_COREAI_TALK", "-allowProvisioningUpdates", "-parallel-testing-enabled", "NO",
                    "-only-testing:MuralUITests/MuralPhysicalDeviceTests/testNativeBaseline"]
            if memory_poc:
                base[base.index("OTHER_SWIFT_FLAGS=$(inherited) -D MURAL_COREAI_TALK")] += " -D MURAL_BREEZE_MEMORY_POC"
            if firered or memory_poc:
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
                # Custom evidence roots need the same explicit receipt selection as runtime.
                # Compiler proof still requires identical app executable bytes, not a source claim.
                explicit = os.environ.get("DEVICE_PREPARED")
                receipts = [Path(explicit)] if explicit else sorted(EVIDENCE_ROOT.glob("*/prepared.json"), reverse=True)
                proof = compiler_proof(evidence / "build.log", identity, receipts, firered=firered, memory_poc=memory_poc)
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
                    "variant": "firered-coreai" if firered else "breeze-memory-poc-coreai" if memory_poc else "coreai", "derived": str(derived)})
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
                fixture_spec = None
                playback_timeout = 5
                if resource_stage:
                    manifest = ROOT / '.build/verification/simplified-talk-meli-20260928/frozen-manifest-v1.json'
                    # One predeclared mixed clip, not an output-dependent selection.
                    if hashlib.sha256(manifest.read_bytes()).hexdigest() != '11704fc265b19de99b899e668d1b3b3de3d87d1b873c31d3e0406c9811f25cbc':
                        raise ValueError('Frozen reviewed manifest changed; review before qualification')
                    fixture_spec = reviewed_fixture(manifest, 'M00A-switch')
                    fixture = Path(fixture_spec['file'])
                    playback_timeout = fixture_spec['playback_timeout_seconds']
                    write_json(evidence / 'reviewed-fixture.json', fixture_spec)
                    if resource_run:
                        check = Path(os.environ.get('DEVICE_RESOURCE_CHECK', ''))
                        if not check.is_dir() or not (check / 'result.json').is_file():
                            raise ValueError('Require a saved matching model-free resource-check first')
                        prior = json.loads((check / 'session.json').read_text())
                        if (prior.get('stage') != 'resource-check' or prior.get('udid') != udid
                                or prior.get('runner_sha256') != session['runner_sha256']
                                or json.loads((check / 'cleanup.json').read_text()).get('cleanup') != 'PASS'
                                or json.loads((check / 'result.json').read_text()).get('models') != 'NOT REQUESTED'
                                or json.loads((check / 'reviewed-fixture.json').read_text()) != fixture_spec):
                            raise ValueError('Resource-check identity/cleanup/fixture mismatch')
                breeze_specs = []
                if breeze_audio:
                    manifest = ROOT / '.build/verification/simplified-talk-meli-20260928/frozen-manifest-v1.json'
                    if hashlib.sha256(manifest.read_bytes()).hexdigest() != '11704fc265b19de99b899e668d1b3b3de3d87d1b873c31d3e0406c9811f25cbc':
                        raise ValueError('Reviewed MELI references changed')
                    clips = breeze_fixture_ids(args.stage, os.environ.get('DEVICE_BREEZE_CLIP'))
                    breeze_specs = [reviewed_fixture(manifest, clip) for clip in clips]
                    fixture_spec = breeze_specs[0]; fixture = Path(fixture_spec['file'])
                    playback_timeout = max(spec['playback_timeout_seconds'] for spec in breeze_specs)
                    write_json(evidence / 'breeze-fixtures.json', breeze_specs)
                if args.stage in ("acoustic", "multi", "cancel") or resource_run or breeze_audio:
                    if not os.environ.get("DEVICE_PLACEMENT"):
                        raise ValueError("Record confirmed phone placement with DEVICE_PLACEMENT")
                    if not (resource_run or breeze_audio) and hashlib.sha256(fixture.read_bytes()).hexdigest() != "1670c9c29ac928b5849ce4fde4dbc31fef3d01497afba7097a506f9984522111":
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
                    write_json(evidence / "acoustic-spec.json", {"text": fixture_spec['reference'] if (resource_run or breeze_audio) else "I bought three apples on Tuesday.", "source": "MELI" if (resource_run or breeze_audio) else "Samantha synthetic speech",
                        "fixture": str(fixture), "sha256": hashlib.sha256(fixture.read_bytes()).hexdigest(), "duration": fixture_spec['duration_seconds'] if (resource_run or breeze_audio) else 1.968345,
                        "normalization": fixture_spec['scoring'] if (resource_run or breeze_audio) else "case/punctuation/whitespace; user-approved token 3=three; other words exact", "placement": os.environ["DEVICE_PLACEMENT"],
                        "volume": volume.strip(), "route": outputs, "playback_ack_timeout_seconds": fixture_spec['ack_timeout_seconds'] if (resource_run or breeze_audio) else 12,
                        "trailing_margin_seconds": 0.75, "room_capture": False})
                fixtures = [Path(spec['file']) for spec in breeze_specs] if breeze_audio else [fixture]
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
                prepared_path = select_prepared(udid, input_identity(derived, firered=firered), receipts)
                if memory_poc:
                    compiler_proof(prepared_path.with_name("build.log"), input_identity(derived), [prepared_path], memory_poc=True)
                if resource_run:
                    previous = json.loads((check / 'prepared-source.json').read_text())['receipt']
                    if json.loads(Path(previous).read_text())['identity'] != json.loads(prepared_path.read_text())['identity']:
                        raise ValueError('Resource-check used a different prepared executable/runner')
                if args.stage == "breeze-profile":
                    check = Path(os.environ.get("DEVICE_BREEZE_PROFILE_CHECK", ""))
                    prior = json.loads((check / "session.json").read_text())
                    prior_prepared = json.loads((check / "prepared-source.json").read_text())["receipt"]
                    if (prior.get("stage") != "breeze-profile-check" or prior.get("udid") != udid
                            or prior.get("runner_sha256") != session["runner_sha256"]
                            or json.loads((check / "cleanup.json").read_text()).get("cleanup") != "PASS"
                            or json.loads((check / "result.json").read_text()).get("models") != "NOT REQUESTED"
                            or not (check / "trace-finalized.json").exists()
                            or json.loads(Path(prior_prepared).read_text())["identity"] != json.loads(prepared_path.read_text())["identity"]):
                        raise ValueError("Require matching cleaned-up model-free Breeze profiler check")
                write_json(evidence / "prepared-source.json", {"receipt": str(prepared_path)})
                print(f"Using verified prepared build: {prepared_path.parent.name}", flush=True)
                # Read-only refusal: never quit someone else's mirror or capture.
                processes = subprocess.check_output(["ps", "-axo", "pid=,command="], text=True, timeout=10)
                if any(term in processes for term in ("/DeviceHub.app/", "/iPhone Mirroring.app/", "idevicesyslog -", "xctrace record")):
                    raise ValueError("Mirroring or device capture already active; resolve ownership before running")
                if breeze_profile:
                    inventory = subprocess.check_output(["xcrun", "xctrace", "list", "devices"], text=True, timeout=30)
                    (evidence / "instruments-devices.txt").write_text(inventory)
                    require_instruments_device(inventory, udid)
                before = subprocess.check_output(["xcrun", "devicectl", "device", "info", "processes", "--device", udid,
                                                  "--search", "Mural", "--timeout", "20"], text=True, timeout=25)
                (evidence / "phone-before.txt").write_text(before)
                if "Mural.app/Mural" in before:
                    raise ValueError("Existing Mural process: do not replace personal work; close the idle app first")
                if provision_run:
                    if recovery_source:
                        recovery_job = retained_provisioning_job(Path(recovery_source).resolve(), udid, evidence)
                    else:
                        write_json(evidence / 'managed-preflight.json', managed_fire_red_inventory(udid, evidence))
                phases.append(("install", time.monotonic()))
                run_bounded(["xcrun", "devicectl", "device", "install", "app", "--device", udid,
                             str(derived / "Build/Products/Release-iphoneos/Mural.app"), "--timeout", "60"], evidence / "install.log", 70)
                if resource_stage and time.monotonic() - started > 60:
                    raise ValueError('Preflight/install exceeded the approved 60-second phase')
                phases.append(("launch_and_backend_gate", time.monotonic()))
                log = evidence / "mural-device.log"
                capture_file = log.open("w")
                capture = subprocess.Popen(["xcrun", "devicectl", "device", "process", "launch", "--device", udid,
                                           "--console", "--environment-variables", '{"OS_ACTIVITY_DT_MODE":"YES"}', APP_ID,
                                           *(["--firered-talk-resource"] if resource_stage else []),
                                           *(["--firered-provision-only"] if provision_run else [])],
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
                control_sent = set()
                probe_wait_started = None
                abort_reason = None
                abort_started = None
                native_begins = {}
                provision_resume_offset = None
                provision_resume_log_offset = None

                def check_faults():
                    if FAULTS.search(log.read_text()) or (breeze_stage and re.search(r'breeze_vad_unavailable|tts_fallback|breeze_asset_verification_end success=false', log.read_text())):
                        raise ValueError("Resource/model/provider fault; stop without retry")

                if resource_stage or breeze_profile:
                    pids = set(re.findall(r'Mural\[(\d+)(?::\d+)?\].*local_talk_asr_backend', log.read_text()))
                    if len(pids) != 1:
                        raise ValueError('Require exactly one fresh app PID for profiler attachment')
                    pid = pids.pop()
                    phases.append(('capture_readiness', time.monotonic()))
                    capture_deadline = time.monotonic() + 60
                    # The backend log is emitted during init, before launch finishes.
                    # Resolve that exact PID in a fresh device inventory before Instruments
                    # attaches; never attach by name or broaden to all phone processes.
                    running = device_json(['device', 'info', 'processes', '--device', udid, '--search', 'Mural'],
                                          evidence / 'profile-target.json')['runningProcesses']
                    if not any(row.get('processIdentifier') == int(pid) and
                               row.get('executable', '').endswith('/Mural.app/Mural') for row in running):
                        raise ValueError('Fresh console PID is not yet an inspectable Mural process; refuse capture')
                    profile_command = (['xcrun', 'xctrace', 'record', '--template', 'Time Profiler',
                        '--instrument', 'Core ML', '--device', udid, '--attach', pid] if breeze_profile else
                        resource_capture_probe(udid, pid, evidence, capture_deadline, check_faults))
                    profiler_file = (evidence / 'resource-capture.log').open('w')
                    profile_command += ['--time-limit', '400s' if breeze_profile else '900s', '--output', str(evidence / trace_name)]
                    profiler = subprocess.Popen(profile_command, stdout=profiler_file, stderr=subprocess.STDOUT, start_new_session=True)
                    write_json(evidence / 'profiler-process.json', {'pid': profiler.pid, 'pgid': profiler.pid,
                        'command': profile_command, 'started_at': datetime.now(timezone.utc).isoformat(),
                        'identity': subprocess.check_output(['ps', '-p', str(profiler.pid), '-o', 'lstart=,command='], text=True).strip()})
                    while True:
                        check_faults()
                        profile_log = (evidence / 'resource-capture.log').read_text()
                        if f'Attaching to: Mural ({pid})' in profile_log and 'Ctrl-C to stop the recording' in profile_log:
                            break
                        if profiler.poll() is not None or time.monotonic() >= capture_deadline:
                            raise ValueError('Main trace did not attach within capture readiness budget')
                        time.sleep(.25)
                    # Profiler setup can outlast Auto-Lock. Recheck the protected
                    # human gate before XCTest startup instead of waiting through
                    # an automation-mode timeout on a phone that already relocked.
                    capture_lock = device_json(['device', 'info', 'lockState', '--device', udid],
                                               evidence / 'capture-lock-state.json')
                    if capture_lock.get('passcodeRequired') is not False or time.monotonic() >= capture_deadline:
                        raise ValueError('Phone relocked or capture readiness budget expired before XCTest; no models started')

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

                def request_resource_abort(reason):
                    nonlocal abort_reason, abort_started
                    if abort_reason is not None:
                        return
                    abort_reason = reason; abort_started = time.monotonic()
                    if playback is not None:
                        stop_group(playback)
                    abort = evidence / 'resource-abort.txt'; abort.write_text(reason)
                    write_json(evidence / 'resource-fault.json', {'reason': reason, 'action': 'native teardown, no retry'})
                    run_bounded(['xcrun', 'devicectl', 'device', 'copy', 'to', '--device', udid,
                        '--source', str(abort), '--destination', f'tmp/mural-resource-abort-{playback_run}.txt',
                        '--domain-type', 'appDataContainer', '--domain-identifier', TEST_ID + '.xctrunner',
                        '--timeout', '5'], evidence / 'abort-copy.log', 6)

                def monitor():
                    nonlocal playback, playback_state, capture_received, probe_sent, probe_wait_started
                    nonlocal provision_resume_offset, provision_resume_log_offset
                    content = log.read_text()
                    test_log = evidence / "test.log"
                    test_content = test_log.read_text() if test_log.exists() else ""
                    if breeze_stage and abort_reason:
                        if time.monotonic() - abort_started > 90:
                            raise ValueError('Breeze native drain exceeded cleanup budget')
                        return
                    # All profiler stages need this check, not just the resource
                    # branch. Once abort is requested, leave the native drain intact.
                    if (resource_stage or breeze_profile) and not abort_reason:
                        check_profiler_exit(profiler.poll(), test_content)
                    if resource_stage or provision_run:
                        fault = FAULTS.search(content)
                        reason = fault.group(0) if fault else None
                        for phase in ('prepare', 'decode'):
                            if f'firered_native_begin phase={phase}' in content and f'firered_native_return phase={phase}' not in content:
                                native_begins.setdefault(phase, time.monotonic())
                                if time.monotonic() - native_begins[phase] > 60:
                                    reason = reason or f'Native {phase} exceeded 60 seconds'
                        if provision_run and re.search(r'firered_native_begin|asr_trial_capture|model_request|asr_ready|local_talk_model_selected', content):
                            reason = reason or 'Native work is forbidden during provisioning'
                        if reason:
                            request_resource_abort(reason)
                        if abort_reason:
                            if time.monotonic() - abort_started > 90:
                                raise ValueError('Native abort cleanup exceeded 90 seconds; inspect preserved failure')
                            return
                    elif FAULTS.search(breeze_fault_log(content, memory_poc) if breeze_stage else content) or (breeze_stage and re.search(r'breeze_vad_unavailable|tts_fallback|breeze_asset_verification_end success=false', content)):
                        raise ValueError("Resource/model/provider fault; stop without retry")
                    for event in ("asr_ready", "model_complete", "local_ended"):
                        if event in content and event not in observed_phases:
                            observed_phases.add(event)
                            print(f"Device phase: {event}", flush=True)
                    if args.stage in ("restore-settings", "pair-check", "resource-check", "breeze-check", "breeze-history", "breeze-finish", "breeze-profile-check", "breeze-profile") and not probe_sent and f"MURAL_DEVICE_PLAYBACK_WAIT {playback_run} 0 " in test_content:
                        probe_wait_started = probe_wait_started or time.monotonic()
                        # Model-free qualification must cross the old 12-second wait.
                        if not resource_stage or time.monotonic() - probe_wait_started >= 13:
                            if breeze_profile:
                                # XCTest has activated the app. Prove it still owns the
                                # exact profiled PID before acknowledging any model work.
                                rows = device_json(['device', 'info', 'processes', '--device', udid, '--search', 'Mural'],
                                                   evidence / 'profile-native-target.json')['runningProcesses']
                                main_pids = [str(row.get('processIdentifier')) for row in rows
                                             if row.get('executable', '').endswith('/Mural.app/Mural')]
                                if main_pids != [pid]:
                                    raise ValueError('Native UI no longer owns the exact profiled Mural PID; no models permitted')
                            acknowledge(0, playback_request(test_content, playback_run, 0))
                            probe_sent = True
                            write_json(evidence / "sync-probe.json", {"run": playback_run, "ack_sent": True, "playback": "NOT REQUESTED"})
                    if provision_run:
                        if 1 not in control_sent and 'speech_package_range file=decoder.int8.onnx offset=0 ' in content and f'MURAL_DEVICE_PLAYBACK_WAIT {playback_run} 1 ' in test_content:
                            acknowledge(1, playback_request(test_content, playback_run, 1)); control_sent.add(1)
                        if 2 not in control_sent and 'MURAL_DEVICE_PROVISION_CANCELLED' in test_content and f'MURAL_DEVICE_PLAYBACK_WAIT {playback_run} 2 ' in test_content:
                            partial = device_json(['device', 'info', 'files', '--device', udid, '--domain-type', 'appDataContainer',
                                '--domain-identifier', APP_ID, '--subdirectory',
                                'Library/Application Support/Mural/SpeechModels/.downloads/firered-asr2-int8-374cff18-v1-a302683c199acb2b37e664fd8ba52d7a5d47503d49dfdff06ba861a264329e3d/support',
                                '--no-recurse', '--search', 'decoder.int8.onnx'], evidence / 'cancelled-partial.json')['files']
                            if len(partial) != 1 or partial[0].get('name') != 'decoder.int8.onnx' or partial[0]['resources'].get('isSymbolicLink'):
                                raise ValueError('Missing safe drained partial file')
                            provision_resume_offset = partial[0]['metadata']['size']
                            if not 0 < provision_resume_offset < 417291928:
                                raise ValueError('Cancellation missed the nonempty partial boundary; preserve files and stop')
                            provision_resume_log_offset = len(log.read_text())
                            acknowledge(2, playback_request(test_content, playback_run, 2)); control_sent.add(2)
                        if 3 not in control_sent and 'firered_provision_verified ' in content and f'MURAL_DEVICE_PLAYBACK_WAIT {playback_run} 3 ' in test_content:
                            if recovery_job:
                                provisioning_recovery_events(content, recovery_job)
                            else:
                                if provision_resume_offset is None: raise ValueError('Missing interrupted attempt evidence')
                                provisioning_events(content, resumed_offset=provision_resume_offset, resumed_log=content[provision_resume_log_offset:])
                            acknowledge(3, playback_request(test_content, playback_run, 3)); control_sent.add(3)
                    if resource_run:
                        for index, boundary in ((2, 'turn-complete'), (3, 'owner-drained'), (4, 'post-drain-30')):
                            if (index not in control_sent and f'firered_resource phase={boundary} ' in content
                                    and f'MURAL_DEVICE_PLAYBACK_WAIT {playback_run} {index} ' in test_content):
                                acknowledge(index, playback_request(test_content, playback_run, index)); control_sent.add(index)
                    if args.stage in ("acoustic", "multi", "cancel") or resource_run or breeze_audio:
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
                                    if resource_run and hashlib.sha256(fixture.read_bytes()).hexdigest() != fixture_spec['sha256']:
                                        raise ValueError('Frozen fixture changed after preparation')
                                    if breeze_audio and hashlib.sha256(fixtures[len(playbacks)].read_bytes()).hexdigest() != breeze_specs[len(playbacks)]['sha256']:
                                        raise ValueError('Reviewed Breeze fixture changed before playback')
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
                                    token = playback_ack_token(test_content, playback_run, len(playbacks), playback_state, timeout=playback_timeout)
                                    acknowledge(len(playbacks), token)
                                    playback_state["ack_transferred_monotonic"] = time.monotonic()
                                    write_json(evidence / "playback.json", playbacks)
                                elif now - playback_state["started_monotonic"] > playback_timeout or "asr_trial_send" in current:
                                    raise ValueError("Playback overrun or early Send")
                    if capture.poll() is not None:
                        test_log = evidence / "test.log"
                        if not test_log.exists() or not expected_console_stop(test_log.read_text()):
                            # A native intent is emitted before deliberate termination;
                            # final cleanup and test results remain independent gates.
                            time.sleep(1)
                            if not test_log.exists() or not expected_console_stop(test_log.read_text()):
                                raise ValueError("Scoped app console stopped before confirmed teardown")
                    if FAULTS.search(breeze_fault_log(log.read_text(), memory_poc) if breeze_stage else log.read_text()):
                        raise ValueError("Resource/model/provider fault; stop without retry")
                def safe_monitor():
                    try:
                        monitor()
                    except Exception as error:
                        if not (resource_stage or provision_run or breeze_stage) or abort_reason is not None:
                            raise
                        request_resource_abort(str(error))

                bundle = evidence / "baseline.xcresult"
                plans = list((derived / "Build/Products").glob("Mural_iphoneos*.xctestrun"))
                if len(plans) != 1:
                    raise ValueError("Require one fingerprinted prepared xctestrun")
                test_plan = evidence / "runtime.xctestrun"
                test_plan.write_bytes(plistlib.dumps(runtime_test_plan(plans[0], {
                    "MURAL_PHYSICAL_E2E": args.stage,
                    "MURAL_PHYSICAL_PAIR": pair,
                    "MURAL_PROVISION_RESUME_JOB": recovery_job or "",
                    "MURAL_RESTORE_MEANING": os.environ.get("DEVICE_RESTORE_MEANING", ""),
                    "MURAL_PLAYBACK_RUN": playback_run,
                    "MURAL_RESOURCE_CAPTURE_READY": "YES" if resource_stage else "",
                    "MURAL_RESOURCE_ACK_SECONDS": str(fixture_spec['ack_timeout_seconds']) if resource_stage else "",
                    "MURAL_BREEZE_ACK_SECONDS": str(max(spec['ack_timeout_seconds'] for spec in breeze_specs)) if breeze_audio else "12",
                    "MURAL_BREEZE_HISTORY_BASE64": base64.b64encode(json.dumps(history_fixture, ensure_ascii=False).encode()).decode() if history_fixture else ""})))
                command = ["xcodebuild", "-xctestrun", str(test_plan), "-destination", f"platform=iOS,id={udid}",
                           "-destination-timeout", "30", "-parallel-testing-enabled", "NO",
                           "-only-testing:MuralUITests/MuralPhysicalDeviceTests/" + ("testNativeBreezeDisplay" if breeze_stage else "testNativeBaseline"),
                           "-resultBundlePath", str(bundle), "-test-timeouts-enabled", "YES",
                                  "-default-test-execution-time-allowance", "360" if recovery_job else "1500" if provision_run else "720" if resource_run else "300", "-maximum-test-execution-time-allowance", "360" if recovery_job else "1500" if provision_run else "720" if resource_run else "300",
                                  "-collect-test-diagnostics", "never", "test-without-building"]
                pipeline = shlex.join(command) + " 2>&1 | tee " + shlex.quote(str(evidence / "test.log")) + " | xcbeautify --is-ci"
                test_started = True
                def halt_playback():
                    if playback is not None:
                        stop_group(playback)
                    if (resource_stage or provision_run or breeze_stage) and 'MURAL_DEVICE_CLEANUP_PASS' not in (evidence / 'test.log').read_text():
                        # Timeout/cancellation also gets native End/drain opportunity
                        # before the host terminates its owned test process group.
                        request_resource_abort(abort_reason or 'Host test ended before confirmed native cleanup')
                        drain_deadline = time.monotonic() + 60
                        while time.monotonic() < drain_deadline:
                            if 'MURAL_DEVICE_CLEANUP_PASS' in (evidence / 'test.log').read_text():
                                break
                            time.sleep(.25)
                phases.append(("native_test_command", time.monotonic()))
                native_budget = (min(420, started + 480 - time.monotonic()) if recovery_job else
                                 min(1560, started + 1620 - time.monotonic()) if provision_run else
                                 min(780, started + 900 - time.monotonic()) if resource_run else 420)
                if native_budget <= 0:
                    raise ValueError('Runtime budget exhausted before native test; preserve cleanup reserve')
                run_bounded(["bash", "-o", "pipefail", "-c", pipeline], evidence / "test-formatted.log", native_budget,
                            env=os.environ.copy(),
                            monitor=safe_monitor, on_stop=halt_playback)
                phases.append(("result_validation", time.monotonic()))
                summary = subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle), "--compact"], timeout=30)
                (evidence / "summary.json").write_bytes(summary)
                check_summary(json.loads(summary))
                if abort_reason:
                    raise ValueError(f'Resource run stopped: {abort_reason}')
                if breeze_stage:
                    import base64
                    text = (evidence / 'test.log').read_text()
                    required = ('MURAL_DEVICE_BREEZE_UI_PASS', 'MURAL_DEVICE_SETTINGS_RESTORED', 'MURAL_DEVICE_CLEANUP_PASS')
                    if not all(marker in text for marker in required):
                        raise ValueError('Breeze UI/restoration/cleanup evidence missing')
                    result = {'stage': args.stage, 'settings_restoration': 'PASS', 'audible_output': 'PENDING HUMAN', 'word_accuracy': 'PENDING REVIEW',
                        'qualification': 'DIAGNOSTIC ONLY - memory-warning pause bypassed; thermal/model/time stops retained' if memory_poc else 'normal warning policy',
                        'memory_warning_rows': [line for line in log.read_text().splitlines() if 'memory_poc_warning' in line or 'asr_memory_warning' in line]}
                    if breeze_audio:
                        if len(playbacks) != len(fixtures) or any('ack_transferred_monotonic' not in item for item in playbacks):
                            raise ValueError('Breeze playback not completed')
                        actual_pair = 'zh-TW-en' if args.stage == 'breeze-traditional' else 'zh-CN-en'
                        result['backend'] = breeze_events(log.read_text(), len(fixtures), pair=actual_pair, memory_poc=memory_poc)
                        result['captures'] = acoustic_events(breeze_fault_log(log.read_text(), memory_poc), result['backend']['pid'], len(fixtures))
                        turns = re.findall(r'^MURAL_DEVICE_BREEZE_TURN (\S+)$', text, re.MULTILINE)
                        if len(turns) != len(fixtures):
                            raise ValueError('Missing scoped raw/display/reply evidence')
                        result['turns'] = [json.loads(base64.b64decode(turn, validate=True)) for turn in turns]
                        sessions = re.findall(r'^MURAL_DEVICE_BREEZE_SESSION ([A-Fa-f0-9-]{36})$', text, re.MULTILINE)
                        if len(sessions) != 1:
                            raise ValueError('Missing unique new test conversation identity')
                        result['session'] = sessions[0]
                        if log.read_text().count('tts_finished') != len(fixtures) + 1:
                            raise ValueError('Missing reply speech completion or unexpected extra playback')
                        result['script_rendering'] = 'PASS: byte-equal real converter expectation in native XCTest'
                        if args.stage == 'breeze-support':
                            support = re.findall(r'^MURAL_DEVICE_BREEZE_SUPPORT_BASE64 (\S+)$', text, re.MULTILINE)
                            if len(support) != 1:
                                raise ValueError('Missing actual meaning/lookup/Help UI outcome')
                            result['support'] = json.loads(base64.b64decode(support[0], validate=True))
                            if set(result['support']) != {'meaning', 'word', 'lookup', 'help'} or any(
                                    not isinstance(value, str) or not value for value in result['support'].values()):
                                raise ValueError('Incomplete native support evidence')
                            result['support_rendering'] = 'PASS: native meaning/lookup/Help already Simplified'
                            result['help_speech'] = 'NOT PLAYED: only greeting and English reply completed'
                        if args.stage == 'breeze-multi' and 'MURAL_DEVICE_BREEZE_EDIT_PERSISTENCE_PASS' not in text:
                            raise ValueError('Missing edit/relaunch/raw retention outcome')
                    elif args.stage == 'breeze-profile':
                        if not probe_sent or 'MURAL_DEVICE_BREEZE_PROFILE_PASS' not in text:
                            raise ValueError('Native preparation-only profile lacked PID admission or did not finish')
                        result['backend'] = breeze_events(log.read_text(), 0)
                        profiles = breeze_load_profile(log.read_text())
                        if len(profiles) != 1 or not profiles[0]['complete'] or profiles[0]['pid'] != result['backend']['pid']:
                            raise ValueError('Missing complete same-PID Breeze component profile')
                        if re.search(r'asr_trial_capture|asr_trial_send|asr_input|breeze_inference_begin', log.read_text()):
                            raise ValueError('Preparation-only profile unexpectedly captured or decoded speech')
                        result.update(models='PREPARED: one normal Talk preparation', load_profile=profiles[0],
                                      microphone='NOT USED', word_accuracy='NOT RUN', audible_output='Greeting completed, listening unconfirmed')
                        write_json(evidence / 'model-load-profile.json', profiles)
                    else:
                        if not probe_sent or re.search(r'asr_ready|asr_trial_capture|model_request|firered_native_begin', log.read_text()):
                            raise ValueError('Model-free gate lacked nonce or unexpectedly started native work')
                        result['models'] = 'NOT REQUESTED'
                        if args.stage == 'breeze-finish':
                            if not all(marker in text for marker in ('MURAL_DEVICE_FINAL_MEANING=Simplified Chinese',
                                                                     'MURAL_DEVICE_BREEZE_NATIVE_DICTIONARY_PASS')):
                                raise ValueError('Final preference or native dictionary regression lacked independent proof')
                            result.update(settings_restoration='User-selected final preference, not original test preference',
                                          final_mode='On-device', final_learning='English', final_meaning='Simplified Chinese',
                                          native_dictionary_regression='PASS: real pinned converter, no ASR models')
                        result['audible_output'] = result['word_accuracy'] = 'NOT RUN in model-free stage'
                        if history_fixture:
                            if 'MURAL_DEVICE_BREEZE_EDIT_PERSISTENCE_PASS' not in text:
                                raise ValueError('Missing scoped edit/relaunch/raw retention outcome')
                            result.update(session=history_fixture['session'], source_run=str(Path(history_source).resolve()),
                                          persistence_relaunch='PASS', explicit_edit='PASS', raw_retention='PASS')
                    write_json(evidence / 'result.json', result)
                elif args.stage in ("restore-settings", "pair-check", "resource-check"):
                    text = (evidence / "test.log").read_text()
                    outcome = f"MURAL_DEVICE_PAIR_CHECK_PASS {pair}" if args.stage in ("pair-check", "resource-check") else "MURAL_DEVICE_RESTORE_ONLY"
                    if not all(marker in text for marker in (outcome, "MURAL_DEVICE_SETTINGS_RESTORED", "MURAL_DEVICE_CLEANUP_PASS", "MURAL_DEVICE_PLAYBACK_ACK_0")):
                        raise ValueError("Model-free selection/restoration not confirmed")
                    if re.search(r"firered_native_begin|asr_trial_capture|model_request|asr_ready", log.read_text()):
                        raise ValueError("Unexpected model/capture work during model-free verification")
                    write_json(evidence / "result.json", {"settings_restoration": "PASS", "pair": pair, "models": "NOT REQUESTED"})
                elif provision_run:
                    text = (evidence / 'test.log').read_text()
                    if not all(marker in text for marker in ('MURAL_DEVICE_SETTINGS_RESTORED', 'MURAL_DEVICE_CLEANUP_PASS')):
                        raise ValueError('Missing independent settings restoration/cleanup')
                    content = log.read_text()
                    if recovery_job:
                        if control_sent != {3} or 'MURAL_DEVICE_PROVISION_RECOVERY_UI_PASS' not in text:
                            raise ValueError('Missing recovery UI evidence')
                        result = provisioning_recovery_events(content, recovery_job)
                        result['prior_failed_run'] = recovery_source
                    else:
                        if control_sent != {1, 2, 3} or not all(marker in text for marker in ('MURAL_DEVICE_PROVISION_UI_PASS', 'MURAL_DEVICE_PROVISION_CANCELLED')):
                            raise ValueError('Missing provisioning/cancellation UI evidence')
                        result = provisioning_events(content, resumed_offset=provision_resume_offset,
                                                     resumed_log=content[provision_resume_log_offset:])
                    write_json(evidence / 'result.json', result)
                elif resource_run:
                    result = resource_events(log.read_text())
                    result['turn'] = acoustic_events(log.read_text(), result['pid'])
                    text = (evidence / 'test.log').read_text()
                    if ('MURAL_DEVICE_RESOURCE_UI_PASS' not in text or len(playbacks) != 1
                            or 'ack_transferred_monotonic' not in playbacks[0] or control_sent != {2, 3, 4}):
                        raise ValueError('Missing resource UI/playback/drain evidence')
                    import base64
                    raw = re.findall(r'^MURAL_DEVICE_RESOURCE_RAW_BASE64 (\S+)$', text, re.MULTILINE)
                    if len(raw) != 1:
                        raise ValueError('Missing unmodified raw recognition')
                    result.update(resource='PASS', acoustic_capture='PASS', audible_output='NOT VERIFIED',
                                  reference_scoring='PENDING separate raw-text review; not a resource assertion',
                                  raw_recognition=base64.b64decode(raw[0], validate=True).decode('utf-8'))
                    write_json(evidence / 'result.json', result)
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
            if profiler is not None:
                try:
                    if profiler.poll() is None:
                        profiler.send_signal(signal.SIGINT)
                    profiler.wait(timeout=60)
                    if profiler.returncode != 0 or not (evidence / trace_name).exists():
                        raise ValueError('Owned trace did not finalize successfully')
                    if breeze_profile:
                        toc = subprocess.check_output(['xcrun', 'xctrace', 'export', '--input', str(evidence / trace_name), '--toc'], timeout=30)
                        (evidence / 'model-load-toc.xml').write_bytes(toc)
                        trace_root = ET.fromstring(toc)
                        target = trace_root.find('./run/info/target/process')
                        if target is None or target.get('pid') != pid:
                            raise ValueError('Core ML trace is not scoped to the fresh owned Mural PID')
                        if trace_root.find('./run/data/table[@schema="coreml-os-signpost"]') is None:
                            raise ValueError('Trace lacks the actual Core ML model-activity instrument')
                    write_json(evidence / 'trace-finalized.json', {'exit_code': profiler.returncode, 'trace': trace_name})
                except Exception as error:
                    cleanup_errors.append(str(error))
                finally:
                    try:
                        stop_group(profiler)
                    except Exception as error:
                        cleanup_errors.append(str(error))
            if profiler_file:
                profiler_file.close()
            if capture is not None:
                try:
                    if (resource_stage or breeze_stage) and not test_started:
                        # This fresh owned launch never reached Prepare. Stop only
                        # its proven PID, never a pre-existing/personal process.
                        owned = set(re.findall(r'Mural\[(\d+)(?::\d+)?\].*local_talk_asr_backend', log.read_text()))
                        if len(owned) != 1:
                            raise ValueError('Pre-test app ownership unconfirmed')
                        device_json(['device', 'process', 'terminate', '--device', udid, '--pid', owned.pop()], evidence / 'pretest-terminate.json')
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
            phone = ("owned launch stopped before native tests" if capture is not None and not cleanup_errors
                     else "pre-test cleanup unconfirmed" if capture is not None else "not launched")
            if test_started:
                text = (evidence / "test.log").read_text() if (evidence / "test.log").exists() else ""
                phone = "ended, drained, terminated" if "MURAL_DEVICE_CLEANUP_PASS" in text else "UNCONFIRMED"
                if phone == "UNCONFIRMED":
                    cleanup_errors.append("Phone teardown unconfirmed: inspect owned XCTest/Mural work before another run")
            write_json(evidence / "cleanup.json", {"cleanup": "FAIL" if cleanup_errors else "PASS", "errors": cleanup_errors,
                       "phone": phone, "settings": "restored by XCTest if changed; unconfirmed when teardown missing" if test_started else "unchanged",
                       "playback": "owned afplay stopped" if playback is not None else "Mac playback not started", "room_capture": "not started"})
    ended = time.monotonic()
    ceiling = 600 if recovery_job else 1740 if provision_run else 1020
    if (resource_run or provision_run) and ended - started > ceiling:
        write_json(evidence / 'budget-failure.json', {'seconds': ended - started, 'ceiling': ceiling,
            'cleanup': 'completed rather than cut off to hide the overrun'})
        code = 1
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
