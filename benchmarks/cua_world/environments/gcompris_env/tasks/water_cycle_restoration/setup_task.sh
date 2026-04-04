#!/bin/bash
set -e

echo "=== Setting up Water Cycle Restoration Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous task artifacts to ensure a clean start
rm -f /home/ga/Documents/water_cycle_status.txt
rm -f /home/ga/Documents/active_cycle.png
rm -f /tmp/task_result.json

# Kill any existing GCompris instances
kill_gcompris

# Launch GCompris at the main menu
# The script in task_utils handles launching as 'ga' user and waiting for the window
echo "Launching GCompris..."
launch_gcompris

# Maximize the window for better visibility
maximize_gcompris

# Take initial screenshot of the main menu
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "GCompris is running at the main menu."
echo "Agent goal: Navigate to Science -> Water Cycle, activate components, and report status."