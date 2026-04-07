#!/bin/bash
set -e

echo "=== Setting up set_notch_filter_50hz task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# Kill any existing OpenBCI instances
pkill -f "OpenBCI_GUI" || true
sleep 2

# Launch OpenBCI GUI
echo "Launching OpenBCI GUI..."
launch_openbci

# Wait for the System Control Panel to be ready
sleep 5

# Automate startup sequence to get to Synthetic session
# 1. Select Synthetic mode
# Coordinates are approximate for 1920x1080 resolution based on standard UI layout
# "Synthetic" is usually the default selection in the dropdown or list, 
# but we click the "Synthetic" button in the Data Source list to be sure.
# Center-left area.
echo "Selecting Synthetic mode..."
click_at 400 350
sleep 1

# 2. Click "Start Session"
# Usually a large button in the top-left or top-center area of the control panel
echo "Starting Session..."
click_at 300 150
sleep 1
click_at 300 150 # Double check/click to ensure

# Wait for the main GUI to load (Time Series widget)
echo "Waiting for session to load..."
sleep 5

# Ensure window is maximized
WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l | grep -i "OpenBCI" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -i -a "$WID"
fi

# Take initial screenshot for debug/verification
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "GUI should be running in Synthetic mode."