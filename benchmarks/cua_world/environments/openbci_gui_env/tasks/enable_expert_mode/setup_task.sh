#!/bin/bash
echo "=== Setting up enable_expert_mode task ==="

source /workspace/utils/openbci_utils.sh || true

# Kill any running instance
kill_openbci

# Launch and start a Synthetic session
# The agent needs to be in an active session to find the Expert Mode toggle
launch_openbci_synthetic

echo "OpenBCI GUI is running in Synthetic mode."
echo "Agent needs to find and enable Expert Mode."

echo "=== Task setup complete ==="
