#!/bin/bash
set -e
echo "=== Setting up Configure Pulse Widget Task ==="

# Source shared utilities if available
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
fi

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Remove any previous screenshots to prevent stale evidence
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/pulse_config.png 2>/dev/null || true

# Ensure OpenBCI GUI is running at the Control Panel (Start Screen)
# If it's running, kill it to ensure a fresh start state
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 2

# Launch OpenBCI GUI
echo "Launching OpenBCI GUI..."
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "openbci"; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize the window
sleep 2
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="