#!/bin/bash
set -e
echo "=== Setting up Simple Word Processing Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists and is clean
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/field_trip_notice.png

# Kill any existing GCompris instances to ensure clean state
kill_gcompris

# Launch GCompris at the main menu
launch_gcompris

# Wait for window and maximize
sleep 2
maximize_gcompris
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "GCompris launched at main menu."
echo "Agent must navigate to Computer Discovery > Word Processor."