#!/bin/bash
echo "=== Setting up hex_prism_standoff task ==="

source /workspace/scripts/task_utils.sh

# Record task start time to detect 'do nothing' behavior
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists and is clean of previous attempts
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace
rm -f /home/ga/Documents/SolveSpace/hex_standoff.slvs
rm -f /home/ga/Documents/SolveSpace/hex_standoff.stl

# Kill any existing SolveSpace instance to ensure a clean slate
kill_solvespace

# Launch SolveSpace with a blank canvas
launch_solvespace ""

# Wait for the application to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window and arrange the UI for the agent
maximize_solvespace
sleep 1

# Take an initial screenshot for verification records
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== hex_prism_standoff task setup complete ==="