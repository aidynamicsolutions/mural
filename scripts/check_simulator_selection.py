#!/usr/bin/env python3
"""Selector and shared-deadline checks, defined before the speedup implementation.

No simulator/build operations: fake only the expensive boundary so exhausted-build
and slow-cleanup cases do not require repeated ten-minute runs. Real Make/XCTest
runs separately prove the selected UI behavior and shutdown.
"""
import json
import os
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

import mural_simulator as driver


def main():
    smoke = [
        "testOnboardingChoosesLearningAndSubtitleLanguagesWithoutAnAccount",
        "testMeaningLabelWorksAfterEndingAndManualResetKeepsHistory",
        "testOnDeviceVoiceSelectionPersists",
    ]
    qualification = {
        *smoke,
        "testExistingUserCanDeclineThenAcceptAIConsentWithoutRepeatingOnboarding",
        "testMeaningLanguageSelectsOnDeviceRecognizerAndUnsupportedCombinationsFailClosed",
        "testSpeechSetupCancelKeepsAdmissionClosedUntilDrain",
        "testMuralVoiceSelectionPersists",
        "testThemeSurvivesNavigationToWords",
        "testThemeSearchFiltersLocally",
        "testSettingsOfferSecureKeyEntryAndBackups",
        "testOpenTranscriptRemainsReadableUntilManualNewConversation",
        "testSettingsLanguageRowAtAccessibilityTextSize",
        "testSettingsDropdownTransitions",
    }
    assert driver.select_tests("smoke", None) == smoke
    full = driver.select_tests("qualification", None)
    assert len(full) == 13 and set(full) == qualification
    focused = "testSettingsDropdownTransitions"
    for suite in ("smoke", "qualification"):
        assert driver.select_tests(suite, focused) == [focused]
    for suite, requested in [("invalid", None), ("invalid", focused), ("smoke", ""), ("smoke", "  "),
                             ("smoke", "-only-testing:Other"), ("smoke", "testX;exit"),
                             ("smoke", "testX testX")]:
        try:
            driver.select_tests(suite, requested)
        except ValueError:
            pass
        else:
            raise AssertionError((suite, requested))

    def dispatch(name, build_duration, runtime_duration, build_code=0, runtime_code=0,
                 expected=0, runtime_expected=True, suite="smoke"):
        clock = [100.0]
        calls = []
        device = "00000000-0000-0000-0000-000000000001"

        def wait(command, env, timeout, lifecycle=False):
            calls.append((command, env, timeout, lifecycle))
            clock[0] += runtime_duration if lifecycle else build_duration
            return runtime_code if lifecycle else build_code

        with tempfile.TemporaryDirectory(prefix="mural-selection-") as temporary:
            env = {"EVIDENCE": f"{temporary}/evidence", "DERIVED_DATA": f"{temporary}/derived",
                   "SIM_UDID": device, "SIMULATOR_MODE": "slim", "SIMSLIM_PROFILE": "",
                   "VERIFY_SUITE": suite}
            devices = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                {"udid": device, "isAvailable": True, "state": "Shutdown"}]}}
            with patch.dict(os.environ, env, clear=True), patch.object(sys, "argv", ["mural_simulator.py", "verify"]), \
                    patch.object(driver, "snapshot", return_value=devices), \
                    patch.object(driver.time, "monotonic", side_effect=lambda: clock[0]), \
                    patch.object(driver, "wait", side_effect=wait):
                assert driver.main() == expected, name
            report = json.loads(Path(env["EVIDENCE"], "timings.json").read_text())
            assert report["total_seconds"] == build_duration + (runtime_duration if runtime_expected else 0), name
            assert report["exit_code"] == expected, (name, report)
            assert len(calls) == (2 if runtime_expected else 1), name
            assert not calls[0][3] and calls[0][2] <= report["budget_seconds"] - 180
            selection = json.loads(Path(env["EVIDENCE"], "make-action.json").read_text())
            assert selection["tests"] == driver.select_tests(suite, None)
            if runtime_expected:
                command, passed_env, outer_timeout, lifecycle = calls[1]
                remaining = int(command[command.index("--timeout") + 1])
                assert remaining == report["budget_seconds"] - 180 - build_duration, (name, remaining)
                assert lifecycle and outer_timeout > remaining
                assert passed_env["TESTS"].split() == selection["tests"]
            return name

    checks = ["smoke-selection", "unchanged-qualification", "focused-replaces-default", "invalid-selection"]
    checks += [
        dispatch("shared-build-runtime-budget", 300, 30),
        dispatch("no-boot-after-budget-exhaustion", 420, 0, expected=124, runtime_expected=False),
        dispatch("build-failure-no-boot", 20, 0, build_code=23, expected=23, runtime_expected=False),
        dispatch("runtime-timeout-preserved", 20, 400, runtime_code=124, expected=124),
        dispatch("cancellation-preserved", 20, 10, runtime_code=143, expected=143),
        dispatch("slow-cleanup-not-a-fast-pass", 300, 350, expected=124),
        dispatch("failure-not-hidden-by-overrun", 300, 350, runtime_code=23, expected=23),
        dispatch("qualification-separate-budget", 300, 900, suite="qualification"),
    ]
    print(json.dumps({"result": "PASS", "checks": checks, "simulator_operations": 0}, indent=2))


if __name__ == "__main__":
    main()
