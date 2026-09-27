#!/usr/bin/env python3
"""Run one bounded verification command and shut down its explicitly owned simulator.

Requires an initially shutdown synthetic device. No erase/delete, implicit selection,
GUI ownership, or daemon. SimSlim is required: slim by default, --stock restores
managed services. Detached helpers/settings belong in --cleanup-script.
"""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import signal
import subprocess
import sys
import time

DEFAULT_PROFILE = Path(__file__).resolve().parent.parent / ".agents/skills/verify-mural/simslim-default.json"


class Interrupted(Exception):
    def __init__(self, signum):
        self.signum = signum


def interrupted(signum, _frame):
    raise Interrupted(signum)


def snapshot():
    return json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "-j"], timeout=30))


def device_in(data, udid):
    for runtime, devices in data["devices"].items():
        for device in devices:
            if device["udid"] == udid and device.get("isAvailable") and ".iOS-" in runtime:
                return {**device, "runtime": runtime}
    raise ValueError(f"Available iOS simulator not found: {udid}")


def write_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def stop_group(process):
    """Only the new process group started by this runner, including surviving children."""
    def has_live_members():
        # Darwin can return EPERM, rather than ESRCH, during group teardown.
        # Confirm absence independently; never treat a real permissions error as success.
        rows = subprocess.check_output(["ps", "-axo", "pgid=,stat="], text=True, timeout=10)
        return any(int(parts[0]) == process.pid and not parts[1].startswith("Z")
                   for row in rows.splitlines() if len(parts := row.split()) == 2)

    process.poll()  # Reap an exited leader before checking its remaining children.
    for sig, grace in ((signal.SIGINT, 30), (signal.SIGTERM, 5), (signal.SIGKILL, 3)):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            return
        except PermissionError:
            if not has_live_members():
                return
            raise
        deadline = time.monotonic() + grace
        while time.monotonic() < deadline:
            process.poll()
            try:
                os.killpg(process.pid, 0)
            except ProcessLookupError:
                return
            except PermissionError:
                if not has_live_members():
                    return
                raise
            time.sleep(0.1)
    if not has_live_members():
        return
    raise RuntimeError(f"Command process group {process.pid} did not disappear; inspect before reusing")


def run(args):
    udid = args.udid.upper()
    if not re.fullmatch(r"[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}", udid):
        raise ValueError("Pass an exact simulator UUID with --udid / SIM_UDID")
    # Real account home, not xcbuild.sh's per-agent HOME. Same lock across projects.
    locks = Path(pwd.getpwuid(os.getuid()).pw_dir) / "Library/Caches/ios-verification"
    locks.mkdir(parents=True, exist_ok=True)
    with (locks / f"{udid}.lock").open("a+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError(f"Simulator already owned by another verification run: {udid}") from None
        before = snapshot()
        device = device_in(before, udid)
        if device["state"] != "Shutdown":
            raise ValueError(f"Refusing borrowed/prebooted device {udid}: {device['state']}. "
                             "Inspect ownership; never shut it down just to bypass this guard.")
        evidence = args.evidence.resolve()
        evidence.mkdir(parents=True, exist_ok=True)
        # Never overwrite the evidence or ownership of an earlier attempt.
        with (evidence / "session.json").open("x") as file:
            session = {"udid": udid, "device": device["name"], "runtime": device["runtime"],
                       "initial_state": device["state"], "pid": os.getpid(),
                       "started_at": datetime.now(timezone.utc).isoformat(),
                       "project": str(Path.cwd()), "command": args.command,
                       "evidence": str(evidence), "status": "running",
                       "requested_mode": "stock" if args.stock else "slim"}
            json.dump(session, file, indent=2)
        lock.seek(0)
        lock.truncate()
        json.dump(session, lock, indent=2)
        lock.flush()
        write_json(evidence / "devices-before.json", before)
        env = {**os.environ, "SIM_UDID": udid, "SIM": udid, "EVIDENCE": str(evidence)}
        exit_code = 1
        errors = []
        state = "unknown"
        process = None
        slimming = {"mode": "stock" if args.stock else "slim", "result": "setup pending"}
        started = time.monotonic()
        command_started = None
        deadline = started + args.timeout

        def execute(command):
            nonlocal process
            if process is not None:
                stop_group(process)
                process = None
            process = subprocess.Popen(command, env=env, start_new_session=True)
            # Keep the PGID in evidence even if the runner is forcibly killed.
            write_json(evidence / "command-process.json", {"pid": process.pid, "pgid": process.pid, "command": command})
            code = process.wait(timeout=max(0.1, deadline - time.monotonic()))
            # Preserve this status before final cleanup, even if cleanup subsequently fails.
            return code if code >= 0 else 128 - code

        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, interrupted)
        try:
            cli = shutil.which("simslim")
            if cli is None:
                raise ValueError("SimSlim is required, including for reliable stock restoration. "
                                 "Install with: brew tap mobai-app/tap && brew install mobai-app/tap/simslim")
            version = subprocess.check_output([cli, "--version"], text=True, timeout=10).strip()
            slimming["version"] = version
            # Exclusions can disable newly added categories after an upgrade.
            if version != "simslim 0.11.0":
                raise ValueError(f"Review profile against {version} before applying (reviewed: 0.11.0)")
            if args.stock:
                code = execute([cli, "off", udid])
                if code != 0:
                    raise RuntimeError(f"SimSlim stock restoration failed ({code}); tests not started")
            else:
                runtime = tuple(int(part) for part in device["runtime"].split(".iOS-")[1].split("-")[:2])
                if runtime < (18, 5):
                    raise ValueError("Persistent slimming requires iOS 18.5+. Use --stock "
                                     "(Make: SIMULATOR_MODE=stock) for this runtime.")
                profile = args.slim_profile.resolve()
                contents = profile.read_bytes()
                write_json(evidence / "profile.json", json.loads(contents))
                slimming.update(profile=str(profile), sha256=hashlib.sha256(contents).hexdigest())
                code = execute([cli, "on", udid, "--profile", str(profile)])
                if code != 0:
                    raise RuntimeError(f"SimSlim setup failed ({code}); tests not started")
                code = execute([cli, "verify", udid, "--profile", str(profile)])
                if code != 0:
                    raise RuntimeError(f"SimSlim profile verification failed ({code})")
            service_state = json.loads(subprocess.check_output([cli, "status", udid, "--json"], timeout=30))
            write_json(evidence / "service-state.json", service_state)
            if not service_state["booted"] or (args.stock and service_state["managedDisabled"] != 0):
                raise RuntimeError("SimSlim service state did not match requested mode; tests not started")
            slimming["result"] = "restored and verified" if args.stock else "applied and verified"
            command_started = time.monotonic()
            exit_code = execute(args.command)
        except Interrupted as error:
            exit_code = 128 + error.signum
            print(f"Verification interrupted by signal {error.signum}", file=sys.stderr)
        except subprocess.TimeoutExpired:
            exit_code = 124
            print(f"Verification exceeded {args.timeout}s", file=sys.stderr)
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            print(f"Verification failed: {error}", file=sys.stderr)
        finally:
            cleanup_started = time.monotonic()
            # A second ordinary cancellation must not interrupt shutdown/evidence finalization.
            for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
                signal.signal(sig, signal.SIG_IGN)
            if process is not None:
                try:
                    stop_group(process)
                except (OSError, RuntimeError, subprocess.SubprocessError) as error:
                    errors.append(str(error))
            if args.cleanup_script:
                try:
                    with (evidence / "cleanup-hook.log").open("w") as log:
                        hook = subprocess.Popen(["bash", str(args.cleanup_script.resolve())],
                                                env=env, stdout=log, stderr=subprocess.STDOUT,
                                                start_new_session=True)
                        try:
                            code = hook.wait(timeout=60)
                            if code:
                                errors.append(f"Cleanup hook exited {code}; see cleanup-hook.log")
                        finally:
                            stop_group(hook)
                except (OSError, RuntimeError, subprocess.SubprocessError) as error:
                    errors.append(f"Cleanup hook: {error}")
            try:
                state = device_in(snapshot(), udid)["state"]
                if state != "Shutdown":
                    result = subprocess.run(["xcrun", "simctl", "shutdown", udid],
                                            capture_output=True, text=True, timeout=60)
                    (evidence / "shutdown.log").write_text(result.stdout + result.stderr)
                    if result.returncode:
                        errors.append(f"simctl shutdown exited {result.returncode}; see shutdown.log")
                end = time.monotonic() + 30
                while True:
                    after = snapshot()
                    state = device_in(after, udid)["state"]
                    if state == "Shutdown" or time.monotonic() >= end:
                        break
                    time.sleep(0.5)
                write_json(evidence / "devices-after.json", after)
                if state != "Shutdown":
                    errors.append(f"Expected Shutdown; found {state}")
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                errors.append(f"Shutdown verification: {error}")
            report = {"udid": udid, "command_exit_code": exit_code, "final_state": state,
                      "cleanup": "FAIL" if errors else "PASS", "errors": errors,
                      "slimming": slimming, "cleanup_script": str(args.cleanup_script) if args.cleanup_script else None,
                      "timings": {"setup_seconds": (command_started or cleanup_started) - started,
                                  "command_seconds": cleanup_started - command_started if command_started else 0,
                                  "cleanup_seconds": time.monotonic() - cleanup_started}}
            write_json(evidence / "cleanup.json", report)
            session["status"] = "cleanup-failed" if errors else "finished"
            write_json(evidence / "session.json", session)
            lock.seek(0)
            lock.truncate()
            json.dump(session, lock, indent=2)
            lock.flush()
            print(f"Simulator {udid}: {state}; cleanup {report['cleanup']}; evidence {evidence}", flush=True)
            for error in errors:
                print(error, file=sys.stderr)
        return exit_code or (1 if errors else 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--udid", default=os.environ.get("SIM_UDID", ""))
    parser.add_argument("--evidence", type=Path, default=Path(os.environ.get("EVIDENCE") or
                        f".build/verification/{datetime.now():%Y%m%d-%H%M%S}-{os.getpid()}"))
    parser.add_argument("--timeout", type=int, default=1800, help="Command/setup deadline in seconds; cleanup has separate bounds")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--slim-profile", type=Path, default=DEFAULT_PROFILE,
                      help="Override the project default slimming profile")
    mode.add_argument("--stock", action="store_true", help="Restore and verify SimSlim-managed services before running")
    parser.add_argument("--cleanup-script", type=Path, help="Bounded bash finalizer for owned recordings/helpers/settings; runs before shutdown")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command[:1] == ["--"]:
        args.command = args.command[1:]
    if not args.udid or not args.command or args.timeout <= 0:
        parser.error("Require --udid (or SIM_UDID), positive --timeout, and -- COMMAND")
    try:
        return run(args)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Verification refused: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
