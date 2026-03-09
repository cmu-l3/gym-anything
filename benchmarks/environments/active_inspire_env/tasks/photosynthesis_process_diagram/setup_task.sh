#!/bin/bash
echo "=== Setting up Photosynthesis Diagram Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure target directory exists and is owned by ga
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any pre-existing file to ensure a clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/photosynthesis_lesson.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/photosynthesis_lesson.flp"
rm -f "$TARGET_FILE" "$TARGET_FILE_ALT" 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time

# Ensure ActivInspire is running
ensure_activinspire_running

# Focus the window
focus_activinspire

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="