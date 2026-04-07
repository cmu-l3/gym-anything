#!/bin/bash
echo "=== Setting up angled_flange_construction task ==="

source /workspace/scripts/task_utils.sh

# Ensure workspace directory exists and clean up previous artifacts
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace
rm -f /home/ga/Documents/SolveSpace/angled_flange.slvs
rm -f /tmp/angled_flange.slvs
rm -f /tmp/task_result.json

# Record start time for anti-gaming (verifying file is created during task)
date +%s > /tmp/task_start_time.txt

# Ensure clean state
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

# Take a screenshot to confirm initial start state
take_screenshot /tmp/task_initial.png
echo "Task start state screenshot saved to /tmp/task_initial.png"

echo "=== setup complete ==="