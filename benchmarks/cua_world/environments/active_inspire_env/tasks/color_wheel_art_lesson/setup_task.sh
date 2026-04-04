#!/bin/bash
echo "=== Setting up Color Wheel Art Lesson Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure Documents/Flipcharts directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents

# Remove any existing target file to ensure a clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/color_wheel_art.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/color_wheel_art.flp"
rm -f "$TARGET_FILE" "$TARGET_FILE_ALT" 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure ActivInspire is running
echo "Checking ActivInspire status..."
ensure_activinspire_running

# Wait for window to settle
sleep 5

# Focus and maximize ActivInspire
focus_activinspire
DISPLAY=:1 wmctrl -r "ActivInspire" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Inspire" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="