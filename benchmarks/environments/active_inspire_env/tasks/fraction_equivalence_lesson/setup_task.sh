#!/bin/bash
echo "=== Setting up Fraction Equivalence Lesson Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Documents/Flipcharts directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any pre-existing target files to ensure a clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/fraction_lesson.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/fraction_lesson.flp"

if [ -f "$TARGET_FILE" ]; then
    echo "Removing pre-existing file: $TARGET_FILE"
    rm -f "$TARGET_FILE"
fi
if [ -f "$TARGET_FILE_ALT" ]; then
    echo "Removing pre-existing file: $TARGET_FILE_ALT"
    rm -f "$TARGET_FILE_ALT"
fi

# Record task start time for anti-gaming (timestamp verification)
date +%s > /tmp/task_start_time

# Ensure ActivInspire is running
echo "Ensuring ActivInspire is ready..."
ensure_activinspire_running
sleep 5

# Focus the window
focus_activinspire

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Target: $TARGET_FILE"