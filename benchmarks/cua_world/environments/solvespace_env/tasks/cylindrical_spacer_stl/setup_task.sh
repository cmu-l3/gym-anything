#!/bin/bash
echo "=== Setting up cylindrical_spacer_stl task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists and is clean of target files
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace
rm -f /home/ga/Documents/SolveSpace/spacer.slvs
rm -f /home/ga/Documents/SolveSpace/spacer.stl

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with no file (blank canvas for creating the sketch from scratch)
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window so agent has full workspace
maximize_solvespace
sleep 1

# Take a screenshot to confirm start state
take_screenshot /tmp/task_initial.png
echo "Task start state screenshot saved to /tmp/task_initial.png"

echo "=== task setup complete ==="