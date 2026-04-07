#!/bin/bash
echo "=== Setting up T-Beam Cross-Section task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing SolveSpace
kill_solvespace

# Ensure output directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Clean state: remove any previous output
rm -f /home/ga/Documents/SolveSpace/t_beam_profile.slvs

# Launch SolveSpace with a blank sketch
launch_solvespace

# Wait for SolveSpace to appear
if wait_for_solvespace 30; then
    echo "SolveSpace launched successfully"
else
    echo "WARNING: SolveSpace window not detected, retrying..."
    kill_solvespace
    sleep 2
    launch_solvespace
    wait_for_solvespace 30
fi

# Maximize and arrange windows
sleep 2
maximize_solvespace
sleep 1

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key --clearmodifiers Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== T-Beam Cross-Section task setup complete ==="
echo "Agent should see SolveSpace with a blank sketch ready for drawing."