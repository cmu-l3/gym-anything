#!/bin/bash
echo "=== Setting up Cell Organelle Frayer Model Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure target directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any pre-existing target file to ensure clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/cell_organelle_frayer.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/cell_organelle_frayer.flp"

if [ -f "$TARGET_FILE" ]; then
    echo "Removing pre-existing: $TARGET_FILE"
    rm -f "$TARGET_FILE"
fi
if [ -f "$TARGET_FILE_ALT" ]; then
    echo "Removing pre-existing: $TARGET_FILE_ALT"
    rm -f "$TARGET_FILE_ALT"
fi

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time

# Ensure ActivInspire is running and ready
ensure_activinspire_running
sleep 2

# Focus the ActivInspire window
focus_activinspire
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Target: $TARGET_FILE"