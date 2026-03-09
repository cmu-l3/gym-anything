#!/bin/bash
set -e
echo "=== Setting up design_vawt_blade task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and has correct permissions
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects

# Remove any pre-existing output file to ensure fresh creation
OUTPUT_FILE="/home/ga/Documents/projects/urban_darrieus_vawt.wpa"
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing previous output file..."
    rm -f "$OUTPUT_FILE"
fi

# Ensure QBlade is running
if ! is_qblade_running > /dev/null 2>&1; then
    echo "Launching QBlade..."
    launch_qblade
    wait_for_qblade 30
else
    echo "QBlade is already running."
fi

# Maximize window for visibility
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="