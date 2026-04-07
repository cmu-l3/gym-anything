#!/bin/bash
echo "=== Setting up hydraulic_manifold_block task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any previous output file to ensure a clean slate
rm -f /home/ga/Documents/SolveSpace/manifold_block.slvs

# Ensure workspace directory exists and has correct permissions
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with a blank canvas
launch_solvespace ""

# Wait for SolveSpace window to appear
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 4

# Maximize the window and arrange panels so agent has full visibility
maximize_solvespace
sleep 1

# Take a screenshot to confirm the start state
take_screenshot /tmp/task_initial.png
echo "Task initial state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="