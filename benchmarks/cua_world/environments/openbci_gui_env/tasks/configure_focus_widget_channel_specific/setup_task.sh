#!/bin/bash
set -e
echo "=== Setting up Configure Focus Widget Task ==="

# Source shared utilities
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
else
    echo "WARNING: Task utils not found, defining minimal fallbacks"
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure OpenBCI data directories exist (clean slate)
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Recordings"
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Settings"

# Kill any existing instance to ensure clean start
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 2

# Launch OpenBCI GUI at the System Control Panel (Main Menu)
echo "Launching OpenBCI GUI..."
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "openbci"; then
        echo "OpenBCI GUI window detected"
        break
    fi
    sleep 1
done

# Maximize the window for consistent coordinates/visibility
DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="