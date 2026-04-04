#!/bin/bash
echo "=== Setting up Export Menu Usage Report task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure the Desktop directory exists
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Clean up any existing target file to ensure we detect NEW creation
TARGET_FILE="/home/ga/Desktop/menu_usage.pdf"
if [ -f "$TARGET_FILE" ]; then
    echo "Removing existing target file..."
    rm -f "$TARGET_FILE"
fi

# Ensure Floreant POS is running and ready
# We use the shared utility to start cleanly and maximize
start_and_login

# Wait a moment for UI to settle
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target: Generate Menu Usage report and save to $TARGET_FILE"