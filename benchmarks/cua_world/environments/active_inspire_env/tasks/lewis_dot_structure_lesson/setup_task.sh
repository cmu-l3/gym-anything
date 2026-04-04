#!/bin/bash
# Setup script for Lewis Dot Structure Lesson task

echo "=== Setting up Lewis Dot Structure Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Flipcharts directory exists and is clean
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Define target files
TARGET_FILE="/home/ga/Documents/Flipcharts/lewis_dot_structures.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/lewis_dot_structures.flp"

# Clean up any previous attempts to ensure a fresh start
if [ -f "$TARGET_FILE" ]; then
    echo "Removing pre-existing target: $TARGET_FILE"
    rm -f "$TARGET_FILE"
fi
if [ -f "$TARGET_FILE_ALT" ]; then
    echo "Removing pre-existing target: $TARGET_FILE_ALT"
    rm -f "$TARGET_FILE_ALT"
fi

# Record initial flipchart count for anti-gaming verification
INITIAL_COUNT=$(list_flipcharts "/home/ga/Documents/Flipcharts" 2>/dev/null | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_flipchart_count

# Record task start time (CRITICAL for valid submission check)
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(date)"

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