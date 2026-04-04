#!/bin/bash
# Setup script for Math Review Game Board task

echo "=== Setting up Math Review Game Board Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Documents/Flipcharts directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any pre-existing target file to ensure clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/math_review_jeopardy.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/math_review_jeopardy.flp"

if [ -f "$TARGET_FILE" ]; then
    echo "Removing pre-existing target: $TARGET_FILE"
    rm -f "$TARGET_FILE"
fi
if [ -f "$TARGET_FILE_ALT" ]; then
    echo "Removing pre-existing target: $TARGET_FILE_ALT"
    rm -f "$TARGET_FILE_ALT"
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(cat /tmp/task_start_time)"

# Ensure ActivInspire is running
ensure_activinspire_running
sleep 5

# Focus the ActivInspire window
focus_activinspire
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved"

echo "=== Setup Complete ==="
echo "Target File: $TARGET_FILE"
echo "Instructions: Create a 4-page Jeopardy game flipchart"