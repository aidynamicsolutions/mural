.PHONY: build agent-verify agent-verify-device agent-device-report

# Thin menu. All simulator operations stay inside the bounded lifecycle runner.
export SIM_UDID SIMULATOR_MODE SIMSLIM_PROFILE EVIDENCE DERIVED_DATA VERIFY_SUITE
# Make exports command-line/environment TESTS automatically. Keep omission distinct from empty.

build:
	@python3 scripts/mural_simulator.py build

agent-verify:
	@python3 scripts/mural_simulator.py verify

# Physical-only, explicit UDID. Default prepare never installs, launches or plays audio.
export DEVICE_UDID DEVICE_STAGE DEVICE_READY DEVICE_PREPARED DEVICE_PLACEMENT DEVICE_IDLE_PID DEVICE_RESTORE_MEANING
agent-verify-device:
	@python3 scripts/verify_device.py

# Saved results only; never accesses the phone. DEVICE_RUN may name an older run.
agent-device-report:
	@python3 scripts/verify_device.py --report $(if $(DEVICE_RUN),"$(DEVICE_RUN)",latest)
