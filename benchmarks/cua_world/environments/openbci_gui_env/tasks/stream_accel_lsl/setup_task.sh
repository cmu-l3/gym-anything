#!/bin/bash
echo "=== Setting up stream_accel_lsl task ==="

source /workspace/utils/openbci_utils.sh || true

su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Recordings"
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots"
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Settings"

# Clean up previous run artifacts
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/lsl_accel_config.png

# Launch OpenBCI GUI with synthetic session running
launch_openbci_synthetic

echo "=== Task setup complete ==="
