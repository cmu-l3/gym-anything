#!/bin/bash
echo "=== Setting up Punnett Square Genetics Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure Documents/Flipcharts directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any pre-existing file to ensure clean state
TARGET_FILE="/home/ga/Documents/Flipcharts/punnett_square_genetics.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/punnett_square_genetics.flp"

if [ -f "$TARGET_FILE" ]; then
    echo "Removing pre-existing file: $TARGET_FILE"
    rm -f "$TARGET_FILE"
fi
if [ -f "$TARGET_FILE_ALT" ]; then
    echo "Removing pre-existing file: $TARGET_FILE_ALT"
    rm -f "$TARGET_FILE_ALT"
fi

# Record start time for anti-gaming (file must be created AFTER this)
date +%s > /tmp/task_start_time

# Ensure ActivInspire is running
ensure_activinspire_running
sleep 5

# Focus the window
focus_activinspire

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="