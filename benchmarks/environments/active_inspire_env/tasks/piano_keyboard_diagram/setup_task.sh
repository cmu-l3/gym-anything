#!/bin/bash
echo "=== Setting up Piano Keyboard Diagram task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure target directory exists and is clean
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any existing file to ensure clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/piano_keyboard.flipchart"
rm -f "$TARGET_FILE" 2>/dev/null || true
rm -f "${TARGET_FILE%.flipchart}.flp" 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time

# Ensure ActivInspire is running
ensure_activinspire_running

# Focus the window
focus_activinspire

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="