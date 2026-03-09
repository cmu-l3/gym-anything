#!/bin/bash
# Setup script for Animal Classification Chart task

echo "=== Setting up Animal Classification Chart Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure target directory exists
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any pre-existing target file to ensure clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/animal_classification.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/animal_classification.flp"

if [ -f "$TARGET_FILE" ]; then
    echo "Removing pre-existing: $TARGET_FILE"
    rm -f "$TARGET_FILE"
fi
if [ -f "$TARGET_FILE_ALT" ]; then
    echo "Removing pre-existing: $TARGET_FILE_ALT"
    rm -f "$TARGET_FILE_ALT"
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(date)"

# Ensure ActivInspire is running
ensure_activinspire_running
sleep 3

# Focus ActivInspire window
focus_activinspire
sleep 1

# Take initial screenshot of the starting state
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved"

echo "=== Setup Complete ==="
echo "Target: $TARGET_FILE"