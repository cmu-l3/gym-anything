#!/bin/bash
echo "=== Setting up open_wrench_head task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

# Remove any previous artifacts
rm -f /home/ga/Documents/SolveSpace/wrench_head.slvs 2>/dev/null
rm -f /home/ga/Documents/SolveSpace/wrench_head.stl 2>/dev/null

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with a blank canvas
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window and arrange panels
maximize_solvespace
sleep 1

# Take a screenshot to confirm initial state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="