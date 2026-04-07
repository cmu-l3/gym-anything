#!/bin/bash
set -e
echo "=== Setting up Configure Ganglion Multimodal Dashboard ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# clean up previous run artifacts
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/ganglion_dashboard.png
rm -f /tmp/task_result.json

# Ensure data directories exist
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots"
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Settings"

# Kill any running OpenBCI GUI instance to ensure clean start
pkill -f "OpenBCI_GUI" 2>/dev/null || true
pkill -f "java" 2>/dev/null || true
sleep 2

# Launch OpenBCI GUI
# We use the user's launch script which handles paths correctly
echo "Launching OpenBCI GUI..."
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "openbci" > /dev/null; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Focus the window
DISPLAY=:1 wmctrl -a "OpenBCI" 2>/dev/null || true
sleep 1
# Maximize for best visibility
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="