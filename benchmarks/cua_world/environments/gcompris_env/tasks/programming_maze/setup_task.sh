#!/bin/bash
set -e
echo "=== Setting up Programming Maze task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean state by killing existing instances
kill_gcompris

# Clean up previous artifacts
rm -f /home/ga/Documents/programming_maze_*.png
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Launch GCompris at the main menu
# The agent is responsible for navigation, so we just start the app
echo "Launching GCompris..."
launch_gcompris

# Ensure window is maximized for visibility
maximize_gcompris

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "GCompris is open at the main menu."
echo "Agent must find 'Programming Maze' in 'Computer Discovery' category."