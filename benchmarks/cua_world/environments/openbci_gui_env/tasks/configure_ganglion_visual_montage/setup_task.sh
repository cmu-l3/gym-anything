#!/bin/bash
set -e
echo "=== Setting up Configure Ganglion Visual Montage Task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure OpenBCI GUI is NOT running initially (fresh start)
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 1

# Launch OpenBCI GUI to the main menu (Data Source selection)
echo "Launching OpenBCI GUI..."
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "openbci" > /dev/null; then
        echo "OpenBCI GUI window detected."
        break
    fi
    sleep 1
done

# Maximize the window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="