#!/bin/bash
set -e
echo "=== Setting up Find Details Art task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Remove any previous result file
rm -f /home/ga/art_detective_success.png
rm -f /tmp/task_result.json

# Kill any existing GCompris instances to ensure clean state
kill_gcompris

# Launch GCompris at the main menu
# Note: We launch it maximized so the agent has a consistent view
launch_gcompris
sleep 5
maximize_gcompris
sleep 2

# Take screenshot of initial state (Main Menu)
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "GCompris launched at Main Menu."
echo "Agent goal: Navigate to 'Find the details' (Puzzles category), complete level 1, and screenshot result."