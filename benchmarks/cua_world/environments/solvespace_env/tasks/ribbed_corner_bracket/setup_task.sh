#!/bin/bash
echo "=== Setting up ribbed_corner_bracket task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Remove any previous output files to ensure a clean state
rm -f /home/ga/Documents/SolveSpace/ribbed_bracket.slvs
rm -f /tmp/ribbed_bracket.stl

# Ensure workspace directory exists with proper permissions
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with no file (blank canvas for creating from scratch)
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window and arrange panels
maximize_solvespace
sleep 1

# Take an initial screenshot to confirm the starting state
take_screenshot /tmp/task_initial.png
echo "Task start state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="