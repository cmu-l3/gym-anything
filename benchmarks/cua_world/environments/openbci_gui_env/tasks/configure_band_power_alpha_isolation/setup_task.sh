#!/bin/bash
set -e
echo "=== Setting up Configure Band Power Task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || source /workspace/utils/openbci_utils.sh || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OpenBCI GUI is running and at the Control Panel (Clean Slate)
echo "Ensuring OpenBCI GUI is open..."
if ! pgrep -f "OpenBCI_GUI" > /dev/null; then
    # Launch logic from utils or direct
    su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /tmp/openbci.log 2>&1 &"
    
    # Wait for window
    echo "Waiting for OpenBCI window..."
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -i "openbci" > /dev/null; then
            echo "Window detected."
            break
        fi
        sleep 1
    done
fi

# Ensure window is maximized and focused
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenBCI" 2>/dev/null || true
sleep 2

# Take initial screenshot for evidence
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="