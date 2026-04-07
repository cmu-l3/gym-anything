#!/bin/bash
set -e
echo "=== Setting up Configure Spectrogram Dual Channels Task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous settings to ensure fresh state
rm -rf /home/ga/Documents/OpenBCI_GUI/Settings/* 2>/dev/null || true

# Launch OpenBCI GUI
# We use the utility function which handles process killing and waiting
launch_openbci

# Ensure window is maximized
DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "OpenBCI_GUI" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="