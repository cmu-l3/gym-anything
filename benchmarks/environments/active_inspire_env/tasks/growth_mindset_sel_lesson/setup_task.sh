#!/bin/bash
# Setup script for Growth Mindset SEL Lesson task
# Creates a clean starting state for the agent.

echo "=== Setting up Growth Mindset SEL Lesson Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Flipcharts directory exists with correct ownership
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any pre-existing target file to ensure clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/growth_mindset_lesson.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/growth_mindset_lesson.flp"

if [ -f "$TARGET_FILE" ]; then
    echo "Removing pre-existing: $TARGET_FILE"
    rm -f "$TARGET_FILE"
fi
if [ -f "$TARGET_FILE_ALT" ]; then
    echo "Removing pre-existing: $TARGET_FILE_ALT"
    rm -f "$TARGET_FILE_ALT"
fi

# Record baseline flipchart count (for anti-gaming checks)
INITIAL_COUNT=$(list_flipcharts "/home/ga/Documents/Flipcharts" 2>/dev/null | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_flipchart_count
echo "Initial flipchart count: $INITIAL_COUNT"

# Record task start time
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(date)"

# Ensure ActivInspire is running and ready
ensure_activinspire_running
sleep 3

# Focus the ActivInspire window
focus_activinspire
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved"

echo "=== Setup Complete ==="
echo "Target: $TARGET_FILE"
echo "Task: Create a 4-page Growth Mindset SEL flipchart"