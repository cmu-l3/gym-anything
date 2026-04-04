#!/bin/bash
echo "=== Setting up Historical Newspaper Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure target directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any pre-existing target file to ensure clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/independence_gazette.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/independence_gazette.flp"

rm -f "$TARGET_FILE" 2>/dev/null || true
rm -f "$TARGET_FILE_ALT" 2>/dev/null || true

# Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(date)"

# Ensure ActivInspire is running
ensure_activinspire_running
sleep 5

# Focus the ActivInspire window and maximize
focus_activinspire
DISPLAY=:1 wmctrl -r "ActivInspire" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "Inspire" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved"

echo "=== Setup Complete ==="
echo "Target File: $TARGET_FILE"