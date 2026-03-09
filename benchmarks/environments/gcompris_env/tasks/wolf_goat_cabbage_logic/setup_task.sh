#!/bin/bash
set -e
echo "=== Setting up Wolf, Goat, Cabbage Logic Task ==="

# Load shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f /home/ga/Documents/river_mid_step.png
rm -f /home/ga/Documents/river_solved.png
rm -f /tmp/task_result.json

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Kill any existing GCompris instances to ensure fresh state
kill_gcompris

# Launch GCompris at the main menu
# The agent is responsible for navigating to the specific activity
echo "Launching GCompris..."
launch_gcompris
sleep 2

# Maximize window for best visibility
maximize_gcompris
sleep 2

# Take initial screenshot of the main menu
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Solve Wolf, Goat, Cabbage puzzle"
echo "Required: Save screenshots to ~/Documents/river_mid_step.png and ~/Documents/river_solved.png"