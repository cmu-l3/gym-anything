#!/bin/bash
# Setup script for Grassland Food Web task

echo "=== Setting up Grassland Food Web Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Flipcharts directory exists and is clean
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove target file if it exists (anti-gaming)
TARGET_FILE="/home/ga/Documents/Flipcharts/grassland_food_web.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/grassland_food_web.flp"
rm -f "$TARGET_FILE" "$TARGET_FILE_ALT" 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming verification)
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(cat /tmp/task_start_time)"

# Ensure ActivInspire is running
ensure_activinspire_running
sleep 5

# Focus the ActivInspire window
focus_activinspire

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Target File: $TARGET_FILE"