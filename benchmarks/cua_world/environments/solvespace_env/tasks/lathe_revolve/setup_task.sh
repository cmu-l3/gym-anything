#!/bin/bash
echo "=== Setting up lathe_revolve task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists and is clean of previous attempts
mkdir -p /home/ga/Documents/SolveSpace
rm -f /home/ga/Documents/SolveSpace/stepped_shaft.slvs
rm -f /home/ga/Documents/SolveSpace/stepped_shaft.stl
chown -R ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with a blank canvas
launch_solvespace ""

# Wait for SolveSpace window to appear
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window for the agent
maximize_solvespace
sleep 1

# Take a screenshot to confirm initial state
take_screenshot /tmp/task_initial.png
echo "Task start state screenshot saved to /tmp/task_initial.png"

echo "=== lathe_revolve task setup complete ==="
echo "Goal: Draw half-profile, revolve 360 degrees, save .slvs and export .stl"