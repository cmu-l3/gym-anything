#!/bin/bash
set -e
echo "=== Setting up Protractor Geometry task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ensure Documents directory exists for the agent to save the screenshot
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any stale result files
rm -f /home/ga/Documents/protractor_success.png

# Kill any existing GCompris instances to ensure fresh start
kill_gcompris

# Launch GCompris at the main menu
# The agent is expected to navigate to the activity themselves
echo "Launching GCompris..."
launch_gcompris

# Wait for window and maximize
sleep 5
maximize_gcompris

# Ensure we are at the main menu (no specific activity loaded)
# (launch_gcompris defaults to main menu)

# Capture initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="