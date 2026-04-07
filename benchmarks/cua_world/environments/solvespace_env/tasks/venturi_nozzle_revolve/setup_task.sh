#!/bin/bash
echo "=== Setting up venturi_nozzle_revolve task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Remove any previous output files
rm -f /home/ga/Documents/SolveSpace/venturi_nozzle.slvs
rm -f /home/ga/Documents/SolveSpace/venturi_nozzle.step

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with no file (blank canvas for creating the sketch from scratch)
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window
maximize_solvespace
sleep 1

# Take a screenshot to confirm start state
take_screenshot /tmp/venturi_nozzle_start.png
echo "Task start state screenshot saved to /tmp/venturi_nozzle_start.png"

echo "=== venturi_nozzle_revolve task setup complete ==="