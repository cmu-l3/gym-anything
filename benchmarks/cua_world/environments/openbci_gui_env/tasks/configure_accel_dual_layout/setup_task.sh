#!/bin/bash
set -e
echo "=== Setting up Configure Accelerometer Layout Task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/accel_layout.png
mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots

# Ensure OpenBCI GUI is running and starts at the System Control Panel
# We kill any existing instances to ensure a clean state
echo "Restarting OpenBCI GUI..."
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 2

# Launch the GUI using the shared utility or direct command
if type launch_openbci >/dev/null 2>&1; then
    launch_openbci
else
    # Fallback if utility not sourced
    su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        bash /home/ga/launch_openbci.sh > /tmp/openbci_task.log 2>&1 &"
    
    # Wait for window
    echo "Waiting for OpenBCI GUI window..."
    for i in $(seq 1 45); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "openbci"; then
            echo "Window found."
            break
        fi
        sleep 1
    done
fi

# Maximize the window to ensure all controls are visible
echo "Maximizing window..."
sleep 2
DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenBCI_GUI" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="