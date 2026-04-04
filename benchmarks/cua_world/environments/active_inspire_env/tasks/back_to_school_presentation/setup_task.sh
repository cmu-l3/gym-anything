#!/bin/bash
# Setup script for Back-to-School Presentation task

echo "=== Setting up Back-to-School Presentation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Documents/Flipcharts exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Clean up any previous attempts
TARGET_FILE="/home/ga/Documents/Flipcharts/back_to_school_night.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/back_to_school_night.flp"
rm -f "$TARGET_FILE" "$TARGET_FILE_ALT" 2>/dev/null || true

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure ActivInspire is running
ensure_activinspire_running

# Focus the window
focus_activinspire

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="