#!/bin/bash
set -e
echo "=== Setting up Construct Gear Mechanism Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean state
kill_gcompris
rm -f /home/ga/gears_success.png

# Launch GCompris
echo "Launching GCompris..."
launch_gcompris

# Wait for window and maximize
sleep 5
maximize_gcompris
sleep 2

# Take initial screenshot of the Main Menu (starting state)
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "GCompris is running at the Main Menu."
echo "Agent must navigate to Discovery -> Gears and solve the puzzle."