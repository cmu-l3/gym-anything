#!/bin/bash
# Setup script for Moon Phases Diagram task

echo "=== Setting up Moon Phases Diagram Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Flipcharts directory exists and is owned by ga
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any pre-existing target file to ensure clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/moon_phases_lesson.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/moon_phases_lesson.flp"

rm -f "$TARGET_FILE" 2>/dev/null || true
rm -f "$TARGET_FILE_ALT" 2>/dev/null || true

# Record baseline flipchart count
INITIAL_COUNT=$(find /home/ga/Documents/Flipcharts -name "*.flipchart" -o -name "*.flp" 2>/dev/null | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_flipchart_count

# Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(date)"

# Ensure ActivInspire is running
ensure_activinspire_running
sleep 5

# Focus the ActivInspire window
focus_activinspire
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Target: $TARGET_FILE"
echo "Task: Create a 4-page Moon Phases lesson flipchart"