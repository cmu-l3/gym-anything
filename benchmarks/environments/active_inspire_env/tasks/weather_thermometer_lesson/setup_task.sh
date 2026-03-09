#!/bin/bash
echo "=== Setting up Weather Thermometer Lesson Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure Documents/Flipcharts directory exists and is owned by ga
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Clean up any previous attempts (anti-gaming)
TARGET_FILE="/home/ga/Documents/Flipcharts/weather_tracker.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/weather_tracker.flp"
rm -f "$TARGET_FILE" "$TARGET_FILE_ALT" 2>/dev/null || true

# Record task start time for timestamp verification
date +%s > /tmp/task_start_time

# Ensure ActivInspire is running
ensure_activinspire_running

# Focus the window to ensure it's ready for input
focus_activinspire

# Take an initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="