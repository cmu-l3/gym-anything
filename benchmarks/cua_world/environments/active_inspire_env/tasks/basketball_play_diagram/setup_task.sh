#!/bin/bash
# Setup script for Basketball Playbook task

echo "=== Setting up Basketball Playbook Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Flipcharts directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any pre-existing target files to ensure a clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/basketball_playbook.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/basketball_playbook.flp"

if [ -f "$TARGET_FILE" ]; then
    echo "Removing pre-existing: $TARGET_FILE"
    rm -f "$TARGET_FILE"
fi
if [ -f "$TARGET_FILE_ALT" ]; then
    echo "Removing pre-existing: $TARGET_FILE_ALT"
    rm -f "$TARGET_FILE_ALT"
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time
echo "Task start time recorded."

# Ensure ActivInspire is running
ensure_activinspire_running
sleep 5

# Focus the ActivInspire window
focus_activinspire
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved."

echo "=== Setup Complete ==="
echo "Target: $TARGET_FILE"
echo "Instructions: Create a 3-page basketball playbook flipchart."