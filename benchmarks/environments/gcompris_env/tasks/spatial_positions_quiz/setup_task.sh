#!/bin/bash
set -e
echo "=== Setting up Spatial Positions Quiz task ==="

# Load shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /home/ga/Documents/positions_question.png
rm -f /home/ga/Documents/positions_success.png
rm -f /tmp/task_result.json

# Ensure GCompris is running
# We launch it fresh to ensure a clean state
kill_gcompris
launch_gcompris
sleep 2

# Maximize the window for better visibility
maximize_gcompris

# Take screenshot of initial state (Main Menu)
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "GCompris launched at main menu."
echo "Agent must navigate to 'Positions' activity and complete 5 rounds."