#!/bin/bash
echo "=== Setting up start_synthetic_session task ==="

source /workspace/utils/openbci_utils.sh || {
    echo "Could not source openbci_utils.sh"
}

# Kill any running OpenBCI GUI instance
kill_openbci

# Ensure OpenBCI GUI data directories exist
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Recordings"
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Settings"

# Launch OpenBCI GUI fresh at the Control Panel (start screen)
# Do NOT auto-start Synthetic — the agent should do this
echo "Launching OpenBCI GUI at Control Panel..."
launch_openbci

echo "=== Task setup complete: OpenBCI GUI is at the Control Panel ==="
echo "Agent should select SYNTHETIC mode and click START SESSION"
