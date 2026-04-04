#!/bin/bash
# Setup script for Algorithm Flowchart Lesson task

echo "=== Setting up Algorithm Flowchart Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure target directory exists and permissions are correct
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any pre-existing target files to ensure a clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/algorithm_flowchart.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/algorithm_flowchart.flp"
rm -f "$TARGET_FILE" "$TARGET_FILE_ALT" 2>/dev/null || true

# Record initial state (file count) for verification
INITIAL_COUNT=$(list_flipcharts "/home/ga/Documents/Flipcharts" 2>/dev/null | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_flipchart_count

# Record task start time for anti-gaming timestamp check
date +%s > /tmp/task_start_time
echo "Task start time: $(cat /tmp/task_start_time)"

# Ensure ActivInspire is running
echo "Ensuring ActivInspire is running..."
ensure_activinspire_running
sleep 3

# Focus the application
focus_activinspire
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved"

echo "=== Setup Complete ==="
echo "Target File: $TARGET_FILE"