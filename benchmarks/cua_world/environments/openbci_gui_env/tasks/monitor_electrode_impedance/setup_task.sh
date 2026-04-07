#!/bin/bash
set -e
echo "=== Setting up Monitor Electrode Impedance task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || source /workspace/utils/openbci_utils.sh || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure OpenBCI directory structure exists
mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots
chown -R ga:ga /home/ga/Documents/OpenBCI_GUI

# Clean up previous attempts
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/impedance_check.png

# Launch OpenBCI GUI to the System Control Panel (startup screen)
# We do NOT start the session automatically; the agent must do that.
echo "Launching OpenBCI GUI..."
launch_openbci

# Ensure window is maximized and focused
WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool search --class "java" | tail -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="