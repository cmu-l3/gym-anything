#!/bin/bash
set -e

echo "=== Setting up power_down_channels_hardware task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh || {
    echo "WARNING: Could not source openbci_task_utils.sh"
}

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous attempts
SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"
TARGET_FILE="PartialMontage.json"
rm -f "${SETTINGS_DIR}/${TARGET_FILE}"
rm -f "/tmp/PartialMontage.json" 2>/dev/null

# Ensure Settings directory exists
mkdir -p "$SETTINGS_DIR"
chown -R ga:ga "/home/ga/Documents/OpenBCI_GUI"

# Ensure OpenBCI GUI is running and ready at the main menu
# If it's already running, kill it to ensure a clean state at the Control Panel
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 1

echo "Launching OpenBCI GUI..."
# Launch via the user wrapper
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"

# Wait for window
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "openbci" > /dev/null; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize the window
sleep 2
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "OpenBCI" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="