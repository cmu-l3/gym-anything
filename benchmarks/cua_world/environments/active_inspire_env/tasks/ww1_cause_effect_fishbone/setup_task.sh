#!/bin/bash
echo "=== Setting up WWI Fishbone Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure target directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any pre-existing target file to ensure clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/ww1_fishbone.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/ww1_fishbone.flp"

if [ -f "$TARGET_FILE" ]; then
    rm -f "$TARGET_FILE"
fi
if [ -f "$TARGET_FILE_ALT" ]; then
    rm -f "$TARGET_FILE_ALT"
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time

# Ensure ActivInspire is running and focused
ensure_activinspire_running
sleep 2
focus_activinspire

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="