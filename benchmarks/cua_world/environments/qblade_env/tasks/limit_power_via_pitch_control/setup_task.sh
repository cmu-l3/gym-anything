#!/bin/bash
set -e
echo "=== Setting up limit_power_via_pitch_control task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create documents directory if it doesn't exist
mkdir -p /home/ga/Documents/projects
mkdir -p /home/ga/Documents/airfoils
chown -R ga:ga /home/ga/Documents/

# Clean up any previous task artifacts to ensure a fresh start
rm -f /home/ga/Documents/projects/derating_study.wpa
rm -f /home/ga/Documents/projects/target_power_result.txt
rm -f /home/ga/Documents/projects/pitch_setting.txt

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for QBlade window to appear
wait_for_qblade 30

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="