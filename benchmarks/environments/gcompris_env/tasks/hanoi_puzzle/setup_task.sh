#!/bin/bash
echo "=== Setting up Tower of Hanoi task ==="

# Load shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure a clean start
kill_gcompris

# Clear any previous screenshots
rm -f /tmp/hanoi_*.png

# Launch GCompris at the main menu
echo "Launching GCompris..."
launch_gcompris
sleep 5

# Maximize the window for better visibility
maximize_gcompris
sleep 2

# Take initial screenshot of the main menu
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "GCompris is open at the Main Menu."
echo "Agent must navigate to Puzzle category -> Tower of Hanoi -> Solve it."