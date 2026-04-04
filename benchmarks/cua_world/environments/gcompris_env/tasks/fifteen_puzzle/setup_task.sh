#!/bin/bash
set -e
echo "=== Setting up Fifteen Puzzle task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous attempts
rm -f /home/ga/Documents/fifteen_puzzle_solved.png
mkdir -p /home/ga/Documents

# Ensure GCompris is clean
kill_gcompris

# Launch GCompris at the main menu
# We do NOT navigate to the activity; the agent must find it.
echo "Launching GCompris..."
launch_gcompris
sleep 2

# Ensure window is maximized for visibility
maximize_gcompris
sleep 2

# Take initial screenshot of the main menu
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "GCompris launched at main menu."