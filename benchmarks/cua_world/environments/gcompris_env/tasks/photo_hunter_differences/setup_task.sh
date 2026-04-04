#!/bin/bash
set -e
echo "=== Setting up Photo Hunter task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure GCompris is clean
kill_gcompris

# Launch GCompris at the main menu
# We do not navigate to a specific category, forcing the agent to find it
# as per the task description ("From the main menu...").
echo "Launching GCompris..."
launch_gcompris

# Maximize the window for better VLM visibility
maximize_gcompris

# Wait a moment for the UI to stabilize
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "GCompris is running at the main menu."
echo "Agent must find 'Photo Hunter' and complete level 1."