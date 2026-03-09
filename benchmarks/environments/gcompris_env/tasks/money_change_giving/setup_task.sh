#!/bin/bash
set -e
echo "=== Setting up Money Change Giving task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists for agent output
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any previous run artifacts
rm -f /home/ga/Documents/change_giving_ui.png
rm -f /home/ga/Documents/task_complete.png

# Kill any existing GCompris instances to ensure clean state
kill_gcompris

# Launch GCompris at the main menu
# The agent must navigate to the activity themselves
echo "Launching GCompris..."
launch_gcompris
sleep 2

# Maximize the window for better VLM visibility
maximize_gcompris
sleep 1

# Take initial screenshot of the starting state (Main Menu)
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "GCompris is running at the main menu."
echo "Agent instruction: Find 'Give Change' activity, complete 5 rounds, and document with screenshots."