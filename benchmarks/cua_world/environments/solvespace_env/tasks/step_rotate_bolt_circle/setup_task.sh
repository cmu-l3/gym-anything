#!/bin/bash
set -e

echo "=== Setting up step_rotate_bolt_circle task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists and is clean
mkdir -p /home/ga/Documents/SolveSpace
rm -f /home/ga/Documents/SolveSpace/circular_post_array.slvs
chown -R ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace with a blank canvas
echo "Launching SolveSpace..."
launch_solvespace ""

# Wait for window to appear
wait_for_solvespace 30
sleep 4

# Maximize the SolveSpace window
maximize_solvespace
sleep 1

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key --clearmodifiers Escape 2>/dev/null || true
sleep 1

# Take initial screenshot as evidence of starting state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="