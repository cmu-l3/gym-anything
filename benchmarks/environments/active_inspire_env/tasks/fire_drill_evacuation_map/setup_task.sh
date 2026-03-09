#!/bin/bash
echo "=== Setting up Fire Drill Evacuation Map Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Flipcharts directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any pre-existing target file to ensure clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/fire_evacuation_plan.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/fire_evacuation_plan.flp"

if [ -f "$TARGET_FILE" ]; then
    rm -f "$TARGET_FILE"
fi
if [ -f "$TARGET_FILE_ALT" ]; then
    rm -f "$TARGET_FILE_ALT"
fi

# Record task start time
date +%s > /tmp/task_start_time

# Ensure ActivInspire is running
ensure_activinspire_running
sleep 5

# Focus the ActivInspire window
focus_activinspire
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="