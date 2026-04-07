#!/bin/bash
echo "=== Setting up parametric_warren_truss_2d task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create workspace directory for the agent
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Clean up any existing file from previous runs
rm -f /home/ga/Documents/SolveSpace/warren_truss.slvs

# Kill any existing SolveSpace instances to ensure a clean slate
kill_solvespace

# Launch SolveSpace with no file (blank canvas for creating from scratch)
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window and move property browser so agent has full workspace
maximize_solvespace
sleep 1

# Take a screenshot to confirm initial clean state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="