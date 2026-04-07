#!/bin/bash
echo "=== Setting up parametric_stair_stringer task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists and is clean
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace
rm -f /home/ga/Documents/SolveSpace/stair_stringer.*

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace with a blank canvas
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window for full workspace visibility
maximize_solvespace
sleep 1

# Take an initial screenshot to confirm start state
take_screenshot /tmp/task_initial.png
echo "Task start state screenshot saved to /tmp/task_initial.png"

echo "=== Setup complete ==="