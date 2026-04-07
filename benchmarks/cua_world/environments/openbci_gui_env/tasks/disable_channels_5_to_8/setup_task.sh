#!/bin/bash
set -e

echo "=== Setting up disable_channels_5_to_8 task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh || {
    echo "WARNING: Could not source openbci_task_utils.sh"
}

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/four_channel_display.png
rm -f /tmp/task_result.json

# Ensure OpenBCI GUI is running at the Control Panel (hub)
# We use the utility function if available, otherwise manual launch
if command -v launch_openbci >/dev/null; then
    launch_openbci
else
    # Fallback launch logic
    pkill -f "OpenBCI_GUI" 2>/dev/null || true
    sleep 2
    su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        bash /home/ga/launch_openbci.sh > /tmp/openbci_task.log 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "openbci"; then
            echo "OpenBCI GUI window detected"
            break
        fi
        sleep 1
    done
fi

# Ensure window is maximized and focused
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "OpenBCI_GUI" 2>/dev/null || true

# Take initial state screenshot
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="