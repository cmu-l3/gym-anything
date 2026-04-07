#!/bin/bash
set -e
echo "=== Setting up Add Spectrogram Widget task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial state (check if settings exist)
if [ -d "/home/ga/Documents/OpenBCI_GUI/Settings" ]; then
    ls -lR "/home/ga/Documents/OpenBCI_GUI/Settings" > /tmp/initial_settings_state.txt
else
    echo "No settings dir" > /tmp/initial_settings_state.txt
fi

# Ensure OpenBCI GUI is NOT running initially (fresh start)
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 2

# Launch OpenBCI GUI
echo "Launching OpenBCI GUI..."
launch_openbci || {
    echo "ERROR: Failed to launch OpenBCI GUI"
    exit 1
}

# Maximize the window using the utility or directly via wmctrl
WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l | grep -i "openbci" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID"
fi

# Dismiss any startup popups/dialogs if they appear (e.g., "What's New")
sleep 3
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true

# Capture initial screenshot (should show Data Source selection screen)
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="