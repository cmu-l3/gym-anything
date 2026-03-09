#!/bin/bash
set -e
echo "=== Setting up Tic-Tac-Toe Win task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any pre-existing victory screenshot to ensure fresh creation
rm -f /home/ga/tic_tac_toe_victory.png

# Kill any existing GCompris instances to ensure clean state
kill_gcompris

# Launch GCompris at the main menu
# Note: GCompris starts at the main menu by default
launch_gcompris
sleep 2

# Maximize the window for better VLM visibility
maximize_gcompris
sleep 2

# Take initial state screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "GCompris launched at main menu."
echo "Target: Strategy > Tic-Tac-Toe > Win > Screenshot to /home/ga/tic_tac_toe_victory.png"