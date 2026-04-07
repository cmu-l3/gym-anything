#!/bin/bash
echo "=== Setting up cam_spline_profile task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is empty of previous results
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace
rm -f /home/ga/Documents/SolveSpace/cam_plate.slvs

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace with a fresh blank sketch
launch_solvespace

# Wait for window to appear
wait_for_solvespace 30
sleep 3

# Maximize canvas window
maximize_solvespace

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key --clearmodifiers Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== cam_spline_profile task setup complete ==="