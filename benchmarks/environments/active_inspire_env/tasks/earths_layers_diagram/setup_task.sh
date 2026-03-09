#!/bin/bash
# Setup script for Earth's Layers Diagram task

echo "=== Setting up Earth's Layers Diagram Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Flipcharts directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any pre-existing target file to ensure clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/earths_layers.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/earths_layers.flp"

rm -f "$TARGET_FILE" 2>/dev/null || true
rm -f "$TARGET_FILE_ALT" 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time

# Ensure ActivInspire is running
ensure_activinspire_running
sleep 5

# Focus the ActivInspire window and maximize
focus_activinspire
DISPLAY=:1 wmctrl -r "ActivInspire" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Inspire" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="