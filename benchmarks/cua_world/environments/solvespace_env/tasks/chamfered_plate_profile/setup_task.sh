#!/bin/bash
echo "=== Setting up chamfered_plate_profile task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean up any previous attempts
rm -f /home/ga/Documents/SolveSpace/chamfered_plate.slvs

# Ensure workspace directory exists and has correct permissions
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instance to start fresh
kill_solvespace

# Launch SolveSpace with a blank canvas
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window for full visibility
maximize_solvespace
sleep 1

# Take an initial screenshot to confirm starting state
take_screenshot /tmp/task_initial.png
echo "Initial state recorded."

echo "=== Task setup complete ==="