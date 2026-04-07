#!/bin/bash
set -e
echo "=== Setting up Configure Channel Gain Settings task ==="

# Source shared utilities if available, otherwise define basics
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
else
    echo "WARNING: openbci_task_utils.sh not found, defining fallbacks"
    function take_screenshot() { scrot "$1" 2>/dev/null || true; }
fi

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/gain_config.png
rm -f /home/ga/Documents/OpenBCI_GUI/gain_report.txt

# Ensure OpenBCI GUI is running and at the start screen
# We kill any existing instance to ensure a clean state
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 2

echo "Launching OpenBCI GUI..."
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"

# Wait for window
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "openbci" > /dev/null; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "OpenBCI" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="