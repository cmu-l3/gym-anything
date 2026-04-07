#!/bin/bash
echo "=== Setting up optical_breadboard_grid task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any previous output file to ensure a clean slate
rm -f /home/ga/Documents/SolveSpace/optical_breadboard.slvs
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with a blank canvas
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window
maximize_solvespace
sleep 1

# Take a screenshot to confirm start state
take_screenshot /tmp/task_initial.png
echo "Task start state screenshot saved to /tmp/task_initial.png"

echo "=== Setup complete ==="