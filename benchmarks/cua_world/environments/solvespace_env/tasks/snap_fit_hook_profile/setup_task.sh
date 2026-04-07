#!/bin/bash
echo "=== Setting up snap_fit_hook_profile task ==="

source /workspace/scripts/task_utils.sh

# Remove any previous output files
rm -f /home/ga/Documents/SolveSpace/snap_fit_hook.slvs
rm -f /home/ga/Documents/SolveSpace/snap_fit_hook.stl

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with no file (blank canvas)
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

echo "=== setup complete ==="