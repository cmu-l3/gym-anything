#!/bin/bash
set -e
echo "=== Setting up chess_activity task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up previous run artifacts
rm -f /home/ga/chess_progress.png
rm -f /tmp/task_result.json

# Kill any existing GCompris instances to ensure clean state
kill_gcompris

# Launch GCompris at the main menu
# The agent must find the activity themselves
echo "Launching GCompris..."
launch_gcompris

# Maximize the window for better visibility
maximize_gcompris

# Take initial state screenshot (evidence of start state)
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "GCompris launched. Agent must navigate to Chess and play."