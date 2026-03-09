#!/bin/bash
set -e
echo "=== Setting up connect_dots_mystery task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean state
rm -f /home/ga/Documents/solved_dots.png
rm -f /home/ga/Documents/object_id.txt
mkdir -p /home/ga/Documents

# Kill any existing GCompris instances
kill_gcompris

# Launch GCompris and wait for it to be ready
# The agent is expected to start from the Main Menu
launch_gcompris
sleep 5

# Maximize window for consistent VLM analysis
maximize_gcompris
sleep 2

# Take initial screenshot of the starting state (Main Menu)
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "GCompris launched at main menu."
echo "Agent must navigate to: Math -> Numeracy -> Connect the Dots"