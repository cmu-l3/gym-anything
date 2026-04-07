#!/bin/bash
echo "=== Setting up countersunk_hex_bolt task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists and is clean
mkdir -p /home/ga/Documents/SolveSpace
rm -f /home/ga/Documents/SolveSpace/countersunk_bolt.slvs
rm -f /home/ga/Documents/SolveSpace/countersunk_bolt.stl
chown -R ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace with a clean new document
launch_solvespace ""

# Wait for SolveSpace window to appear
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 4

# Maximize the window for full visibility
maximize_solvespace
sleep 1

# Take a screenshot to record the initial state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Setup complete ==="