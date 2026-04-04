#!/bin/bash
# Setup script for Hamburger Writing Template task
set -e

echo "=== Setting up Hamburger Writing Template Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure target directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any pre-existing target file to ensure clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/hamburger_paragraph.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/hamburger_paragraph.flp"

if [ -f "$TARGET_FILE" ]; then
    echo "Removing pre-existing: $TARGET_FILE"
    rm -f "$TARGET_FILE"
fi
if [ -f "$TARGET_FILE_ALT" ]; then
    echo "Removing pre-existing: $TARGET_FILE_ALT"
    rm -f "$TARGET_FILE_ALT"
fi

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# Ensure ActivInspire is running and ready
ensure_activinspire_running
sleep 5

# Focus the ActivInspire window and maximize
focus_activinspire
DISPLAY=:1 wmctrl -r "ActivInspire" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved."

echo "=== Setup Complete ==="