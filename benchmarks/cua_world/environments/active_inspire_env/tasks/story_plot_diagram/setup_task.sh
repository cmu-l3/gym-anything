#!/bin/bash
# Setup script for Story Plot Diagram task
set -e

echo "=== Setting up Story Plot Diagram Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Documents/Flipcharts directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents

# Remove any pre-existing target file to ensure clean state
TARGET_FILE="/home/ga/Documents/Flipcharts/plot_diagram_dangerous_game.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/plot_diagram_dangerous_game.flp"

rm -f "$TARGET_FILE" "$TARGET_FILE_ALT" 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure ActivInspire is running
ensure_activinspire_running

# Focus ActivInspire window
focus_activinspire

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target file: $TARGET_FILE"