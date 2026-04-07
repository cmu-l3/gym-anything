#!/bin/bash
set -e
echo "=== Setting up Configure Input Type Noise Check task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || source /workspace/utils/openbci_utils.sh || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots
chown -R ga:ga /home/ga/Documents/OpenBCI_GUI

# Clean up any previous screenshots
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/noise_floor_config.png

# Launch OpenBCI GUI to the main menu (System Control Panel)
# We do NOT start the session automatically; the agent must do that.
echo "Launching OpenBCI GUI..."
launch_openbci

# Ensure window is maximized for best visibility
WID=$(DISPLAY=:1 wmctrl -l | grep -i "OpenBCI" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    # Focus the window
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot of the starting state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "GUI is at System Control Panel. Agent needs to start Synthetic session and configure Hardware Settings."