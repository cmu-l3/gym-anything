#!/bin/bash
set -e
echo "=== Setting up VAWT Torque Ripple Analysis Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/projects
chown -R ga:ga /home/ga/Documents

# Clean up any previous run artifacts
rm -f /home/ga/Documents/projects/vawt_ripple.wpa
rm -f /home/ga/Documents/projects/ripple_report.txt
rm -f /tmp/task_result.json

# Record initial state
INITIAL_PROJECTS=$(ls /home/ga/Documents/projects/*.wpa 2>/dev/null | wc -l)
echo "$INITIAL_PROJECTS" > /tmp/initial_project_count

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for QBlade window
wait_for_qblade 30

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "QBlade" -e 0,0,0,1920,1080 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="