#!/bin/bash
set -e

echo "=== Setting up Configure EMG Channel Selection Task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || source /workspace/utils/openbci_utils.sh || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure clean state
echo "Killing any existing OpenBCI instances..."
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 2

# 2. Launch OpenBCI GUI
echo "Launching OpenBCI GUI..."
# We use the utility function if available, otherwise manual launch
if type launch_openbci >/dev/null 2>&1; then
    launch_openbci
else
    # Manual launch fallback
    su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "openbci"; then
            echo "OpenBCI GUI window appeared."
            break
        fi
        sleep 1
    done
fi

# 3. Maximize and Focus
echo "Maximizing window..."
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "OpenBCI_GUI" 2>/dev/null || true

# 4. Capture Initial State
echo "Capturing initial state..."
if type take_screenshot >/dev/null 2>&1; then
    take_screenshot /tmp/task_initial.png
else
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="