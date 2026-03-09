#!/bin/bash
set -e
echo "=== Setting up Share the Candies task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create Documents directory if it doesn't exist
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous attempt files
rm -f /home/ga/Documents/candy_problem.txt
rm -f /home/ga/Documents/candy_success.png

# Kill any existing GCompris instances to ensure fresh start
kill_gcompris

# Launch GCompris at the main menu
echo "Launching GCompris..."
launch_gcompris
sleep 2

# Maximize the window for better visibility
maximize_gcompris
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="