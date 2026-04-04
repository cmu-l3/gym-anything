#!/bin/bash
# Setup script for Civil Rights Timeline task

echo "=== Setting up Civil Rights Timeline Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Documents/Flipcharts directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Clean up any previous attempts to ensure a fresh start
TARGET_FILE="/home/ga/Documents/Flipcharts/civil_rights_timeline.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/civil_rights_timeline.flp"

if [ -f "$TARGET_FILE" ]; then
    echo "Removing existing target file: $TARGET_FILE"
    rm -f "$TARGET_FILE"
fi
if [ -f "$TARGET_FILE_ALT" ]; then
    echo "Removing existing target file: $TARGET_FILE_ALT"
    rm -f "$TARGET_FILE_ALT"
fi

# Record task start time (critical for anti-gaming verification)
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(cat /tmp/task_start_time)"

# Ensure ActivInspire is running
ensure_activinspire_running
sleep 5

# Focus the application window
focus_activinspire
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial state captured"

echo "=== Setup Complete ==="
echo "Target: $TARGET_FILE"