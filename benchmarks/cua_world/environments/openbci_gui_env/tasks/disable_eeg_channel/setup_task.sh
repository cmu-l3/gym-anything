#!/bin/bash
echo "=== Setting up disable_eeg_channel task ==="

source /workspace/utils/openbci_utils.sh || true

# Kill any running instance
kill_openbci

# Launch OpenBCI GUI in Synthetic mode
launch_openbci_synthetic

echo "=== Task setup complete: GUI running in Synthetic mode ==="
echo "Agent should click the numbered Channel 3 button (circle labeled '3') on the left side of the Time Series widget"
