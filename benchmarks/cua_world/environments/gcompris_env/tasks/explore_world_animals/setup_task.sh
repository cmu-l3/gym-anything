#!/bin/bash
set -e
echo "=== Setting up Explore World Animals task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Clean any previous task artifacts to ensure a fresh start
rm -f /home/ga/Documents/world_animals_report.txt
rm -f /home/ga/Documents/world_animals_screenshot.png
rm -f /tmp/task_result.json

# Ensure Documents directory exists with correct permissions
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Kill any existing GCompris instances
kill_gcompris

# Launch GCompris at main menu
# The agent is responsible for navigating to the specific activity
echo "Launching GCompris..."
launch_gcompris

# Maximize the window for better visibility
maximize_gcompris

# Take screenshot of initial state
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="