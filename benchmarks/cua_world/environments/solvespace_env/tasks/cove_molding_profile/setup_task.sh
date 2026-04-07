#!/bin/bash
echo "=== Setting up cove_molding_profile task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any previous output file to ensure a clean slate
rm -f /home/ga/Documents/SolveSpace/cove_molding.slvs

# Ensure workspace directory exists with correct permissions
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with no file (blank canvas)
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window for a better agent viewport
maximize_solvespace
sleep 1

# Take a screenshot to confirm start state
take_screenshot /tmp/task_initial.png
echo "Task start state screenshot saved to /tmp/task_initial.png"

echo "=== cove_molding_profile task setup complete ==="