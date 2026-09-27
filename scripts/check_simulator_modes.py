#!/usr/bin/env python3
"""Real CLI checks for default slimming, explicit stock restoration and fail-closed setup.

Defined before implementation. All writes target an initially shutdown synthetic
lifecycle device; an optional old-runtime device is only used for a pre-boot refusal.
The unreviewed-version case substitutes only a version-reporting CLI in its evidence dir.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
RUNNER = ROOT / "scripts/verify_simulator.py"
PROFILE = ROOT / ".agents/skills/verify-mural/simslim-default.json"


def devices():
    data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"], timeout=30))
    return {d["udid"]: d for group in data["devices"].values() for d in group}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--udid", required=True)
    parser.add_argument("--old-udid")
    parser.add_argument("--evidence", required=True, type=Path)
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    initial = devices()
    assert initial[args.udid]["state"] == "Shutdown"
    assert initial[args.udid]["name"].startswith("Mural Lifecycle")
    results = []

    def check(name, flags=(), expected=0, env=None, udid=None, message=None):
        output = evidence / name
        command = [sys.executable, str(RUNNER), "--udid", udid or args.udid,
                   "--evidence", str(output), *flags, "--", "bash", "-c",
                   'printf ran > "$EVIDENCE/command-ran"']
        result = subprocess.run(command, cwd="/tmp", env=env, capture_output=True, text=True, timeout=300)
        (evidence / f"{name}.log").write_text(result.stdout + result.stderr)
        assert result.returncode == expected, (name, result.returncode, result.stderr)
        assert (output / "command-ran").exists() == (expected == 0), name
        assert devices()[udid or args.udid]["state"] == "Shutdown", name
        if message:
            assert message in result.stderr, result.stderr
        if (output / "cleanup.json").exists():
            report = json.loads((output / "cleanup.json").read_text())
            assert report["cleanup"] == "PASS", report
        results.append(name)
        return output

    default = check("default-from-other-cwd")
    report = json.loads((default / "cleanup.json").read_text())
    assert report["slimming"]["result"] == "applied and verified", report
    assert Path(report["slimming"]["profile"]).name == "simslim-default.json"
    assert json.loads((default / "service-state.json").read_text())["managedDisabled"] > 0

    custom_profile = evidence / "custom-conservative.json"
    categories = json.loads(subprocess.check_output(["simslim", "profiles", "--json"], timeout=30))
    custom_profile.write_text(json.dumps({"except": [c["id"] for c in categories if c["id"] != "search"]}))
    custom = check("custom-conservative", ("--slim-profile", str(custom_profile)))
    assert json.loads((custom / "cleanup.json").read_text())["slimming"]["profile"] == str(custom_profile)

    # Fail after real setup has mutated/booted the owned simulator. Tests must not run.
    import shutil
    real_cli = shutil.which("simslim")
    partial = evidence / "partial-setup-shim"
    partial.mkdir()
    executable = partial / "simslim"
    executable.write_text(f'#!/bin/bash\n{real_cli!r} "$@"\nstatus=$?\nif [[ "$1" == on && "$status" == 0 ]]; then exit 19; fi\nexit "$status"\n')
    executable.chmod(0o755)
    check("partial-setup-failure", expected=1,
          env={**os.environ, "PATH": f"{partial}:{os.environ['PATH']}"}, message="tests not started")
    stock = check("stock-restores", ("--stock",))
    state = json.loads((stock / "service-state.json").read_text())
    assert state["managedDisabled"] == 0 and state["verdict"] == "stock", state

    no_cli = {**os.environ, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"}
    check("missing-cli-default", expected=1, env=no_cli, message="brew install")
    check("missing-cli-stock", ("--stock",), expected=1, env=no_cli, message="brew install")

    malformed = evidence / "malformed.json"
    malformed.write_text('{"except":')
    check("malformed-profile", ("--slim-profile", str(malformed)), expected=1)
    unknown = evidence / "unknown-category.json"
    unknown.write_text('{"except": ["not-a-real-category"]}')
    check("profile-setup-failure", ("--slim-profile", str(unknown)), expected=1)
    check("conflicting-options", ("--stock", "--slim-profile", str(PROFILE)), expected=2)

    shim = evidence / "version-shim"
    shim.mkdir()
    executable = shim / "simslim"
    executable.write_text('#!/bin/sh\necho "simslim 0.99.0"\n')
    executable.chmod(0o755)
    check("unreviewed-version", expected=1, env={**os.environ, "PATH": f"{shim}:{os.environ['PATH']}"},
          message="Review profile")
    if args.old_udid:
        assert initial[args.old_udid]["state"] == "Shutdown"
        assert initial[args.old_udid]["name"].startswith("Mural Lifecycle")
        check("unsupported-slim-runtime", expected=1, udid=args.old_udid, message="--stock")

    make = subprocess.run(["make", "agent-verify", f"SIM_UDID={args.udid}",
                           "SIMULATOR_MODE=invalid"], cwd=ROOT, capture_output=True, text=True, timeout=30)
    assert make.returncode != 0 and "SIMULATOR_MODE" in make.stderr
    (evidence / "invalid-make-mode.log").write_text(make.stdout + make.stderr)
    results.append("invalid-make-mode")
    suite = subprocess.run(["make", "agent-verify", f"SIM_UDID={args.udid}",
                            "VERIFY_SUITE=invalid"], cwd=ROOT, capture_output=True, text=True, timeout=30)
    assert suite.returncode != 0 and "VERIFY_SUITE" in suite.stderr
    (evidence / "invalid-make-suite.log").write_text(suite.stdout + suite.stderr)
    results.append("invalid-make-suite")
    result = {"result": "PASS", "checks": results, "owned_device": args.udid,
              "final_state": devices()[args.udid]["state"], "last_applied_mode": "stock"}
    (evidence / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
