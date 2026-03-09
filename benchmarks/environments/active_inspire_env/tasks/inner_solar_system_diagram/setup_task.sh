#!/bin/bash
echo "=== Setting up Inner Solar System Diagram Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure target directory exists and permissions are correct
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Clean up any previous attempts to ensure a fresh start
TARGET_FILE="/home/ga/Documents/Flipcharts/inner_solar_system.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/inner_solar_system.flp"
rm -f "$TARGET_FILE" "$TARGET_FILE_ALT" 2>/dev/null || true

# Record task start time for anti-gaming (file mtime check)
date +%s > /tmp/task_start_time

# Ensure ActivInspire is running
ensure_activinspire_running

# Focus the window and maximize it
focus_activinspire
DISPLAY=:1 wmctrl -r "ActivInspire" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Inspire" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup complete ==="