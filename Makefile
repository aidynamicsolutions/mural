.PHONY: build agent-verify

# Thin menu. All simulator operations stay inside the bounded lifecycle runner.
export SIM_UDID SIMULATOR_MODE SIMSLIM_PROFILE EVIDENCE DERIVED_DATA VERIFY_SUITE
# Make exports command-line/environment TESTS automatically. Keep omission distinct from empty.

build:
	@python3 scripts/mural_simulator.py build

agent-verify:
	@python3 scripts/mural_simulator.py verify
