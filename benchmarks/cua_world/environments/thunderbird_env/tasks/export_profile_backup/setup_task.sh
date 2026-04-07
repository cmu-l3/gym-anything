#!/bin/bash
echo "=== Setting up Export Profile Backup Task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create target directory and ensure it's empty
TARGET_DIR="/home/ga/Documents/ProfileBackup"
mkdir -p "$TARGET_DIR"
rm -rf "${TARGET_DIR:?}"/*
chown -R ga:ga "/home/ga/Documents/ProfileBackup"

# Start Thunderbird if not already running
start_thunderbird

# Wait for Thunderbird window to appear
wait_for_thunderbird_window 30
sleep 2

# Maximize and focus the window
maximize_thunderbird

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="