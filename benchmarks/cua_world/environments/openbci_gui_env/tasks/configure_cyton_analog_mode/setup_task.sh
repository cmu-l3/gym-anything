#!/bin/bash
set -e

echo "=== Setting up Configure Cyton Analog Mode task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || source /workspace/utils/openbci_utils.sh || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 1

# Launch OpenBCI GUI
# We use the wrapper from the environment which handles the java classpath and lib paths
echo "Launching OpenBCI GUI..."
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority /usr/local/bin/openbci_gui > /tmp/openbci.log 2>&1 &"

# Wait for window
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "openbci" > /dev/null; then
        echo "OpenBCI GUI window detected."
        break
    fi
    sleep 1
done

# Maximize the window to ensure standard layout for the agent
sleep 2
DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenBCI_GUI" 2>/dev/null || true

# Dismiss any potential first-run popups
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="