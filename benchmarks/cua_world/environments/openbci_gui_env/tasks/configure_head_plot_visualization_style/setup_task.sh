#!/bin/bash
set -e
echo "=== Setting up Configure Head Plot Task ==="

# Source shared utilities if available
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
else
    echo "WARNING: Task utils not found, using fallback setup."
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure OpenBCI GUI directories exist
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots"
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Settings"

# Clean up any previous attempts
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/head_plot_viridis.png

# Launch OpenBCI GUI at the Control Panel (Start Screen)
# We want the agent to perform the startup sequence (Select Synthetic -> Start Session)
echo "Launching OpenBCI GUI..."
if [ -f "/home/ga/launch_openbci.sh" ]; then
    # Kill existing
    pkill -f "OpenBCI_GUI" 2>/dev/null || true
    sleep 2
    
    # Launch in background
    su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"
else
    echo "ERROR: Launch script not found."
    exit 1
fi

# Wait for window
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "openbci"; then
        echo "OpenBCI GUI window detected."
        break
    fi
    sleep 1
done

# Maximize window to ensure all controls are visible
sleep 2
DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Focus window
DISPLAY=:1 wmctrl -a "OpenBCI_GUI" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="