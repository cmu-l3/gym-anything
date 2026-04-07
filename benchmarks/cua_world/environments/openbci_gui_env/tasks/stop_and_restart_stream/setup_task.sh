#!/bin/bash
set -e
echo "=== Setting up stop_and_restart_stream task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh

# 1. Clean up previous artifacts
rm -f /home/ga/Documents/OpenBCI_GUI/stream_lifecycle_log.txt
rm -f /tmp/task_result.json

# 2. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 3. Ensure OpenBCI GUI is running at the Control Panel (start screen)
# The utility function handles killing old instances and waiting for the new window
echo "Launching OpenBCI GUI..."
launch_openbci

# 4. Maximize the window for consistent visibility
echo "Maximizing window..."
WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l | grep -i "OpenBCI" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    # Ensure focus
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID"
fi

# 5. Capture initial state screenshot
echo "Capturing initial state..."
sleep 2 # Wait for render
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="