#!/bin/bash
set -e
echo "=== Setting up Configure Dual Network Streams Task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots
mkdir -p /home/ga/Documents/OpenBCI_GUI/Settings
chown -R ga:ga /home/ga/Documents/OpenBCI_GUI

# Clean up previous screenshots to avoid confusion
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/*.png
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/*.jpg

# Kill any existing OpenBCI instances
pkill -f "OpenBCI_GUI" || true
sleep 1

# Launch OpenBCI GUI to the initial System Control Panel
echo "Launching OpenBCI GUI..."
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "openbci" > /dev/null; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize the window
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="