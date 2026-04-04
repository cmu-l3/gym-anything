#!/bin/bash
echo "=== Setting up set_bandpass_filter task ==="

source /workspace/utils/openbci_utils.sh || true

kill_openbci
launch_openbci_synthetic

echo "=== Task setup complete: GUI running in Synthetic mode with default 5-50 Hz bandpass filter ==="
echo "Agent should open Filters dialog and change the Start frequency from 5 Hz to 1 Hz (1-50 Hz range)"
