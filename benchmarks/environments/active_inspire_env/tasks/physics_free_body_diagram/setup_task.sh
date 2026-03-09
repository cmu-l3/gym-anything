#!/bin/bash
echo "=== Setting up Physics FBD Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure target directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any existing file with the expected name (clean start)
TARGET_FILE="/home/ga/Documents/Flipcharts/physics_fbd.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/physics_fbd.flp"
rm -f "$TARGET_FILE" 2>/dev/null || true
rm -f "$TARGET_FILE_ALT" 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time

# Ensure ActivInspire is running
ensure_activinspire_running

# Focus ActivInspire window
focus_activinspire

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="