#!/bin/bash
set -e
echo "=== Setting up Simulate Tidal Turbine Performance task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /home/ga/Documents/projects/tidal_project.wpa 2>/dev/null || true
rm -f /home/ga/Documents/tidal_report.txt 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure directories exist
mkdir -p /home/ga/Documents/projects
mkdir -p /home/ga/Documents/airfoils
chown -R ga:ga /home/ga/Documents

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for QBlade window to appear
wait_for_qblade 30

# Maximize the window (important for VLM/screenshots)
sleep 2
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="