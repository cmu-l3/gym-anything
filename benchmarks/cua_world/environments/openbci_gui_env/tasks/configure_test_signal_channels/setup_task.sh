#!/bin/bash
set -e

echo "=== Setting up configure_test_signal_channels task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# Clean up any existing settings files to ensure we detect a NEW save
# We don't delete them, just note the current time to filter later, 
# but moving them aside is safer to prevent confusion.
SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"
if [ -d "$SETTINGS_DIR" ]; then
    mkdir -p "/home/ga/Documents/OpenBCI_GUI/OldSettings"
    mv "$SETTINGS_DIR"/*.json "/home/ga/Documents/OpenBCI_GUI/OldSettings/" 2>/dev/null || true
    echo "Moved old settings files to backup."
fi

# Kill any existing OpenBCI GUI instance
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 2

# Launch OpenBCI GUI
echo "Launching OpenBCI GUI..."
launch_openbci

# Wait for window to stabilize
sleep 5

# Maximize the window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
echo "Window maximized."

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png
echo "Initial state screenshot captured."

echo "=== Task setup complete ==="