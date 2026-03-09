#!/bin/bash
set -e
echo "=== Setting up determine_runaway_rpm task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/projects
mkdir -p /home/ga/Documents/airfoils
chown -R ga:ga /home/ga/Documents

# Cleanup previous attempts
rm -f /home/ga/Documents/projects/runaway_report.txt
rm -f /home/ga/Documents/projects/runaway_data.txt
rm -f /home/ga/Documents/projects/safety_analysis.wpa
rm -f /tmp/task_result.json

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for QBlade window
wait_for_qblade 30

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="