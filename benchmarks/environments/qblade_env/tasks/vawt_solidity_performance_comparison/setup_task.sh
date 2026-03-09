#!/bin/bash
set -e
echo "=== Setting up VAWT Solidity Comparison Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/projects
mkdir -p /home/ga/Documents/airfoils
chown -R ga:ga /home/ga/Documents

# Clean up artifacts from previous runs
rm -f /home/ga/Documents/projects/solidity_study.wpa
rm -f /home/ga/Documents/projects/solidity_report.txt
rm -f /tmp/task_result.json

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for QBlade window
wait_for_qblade 30

# Maximize window for better visibility
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="