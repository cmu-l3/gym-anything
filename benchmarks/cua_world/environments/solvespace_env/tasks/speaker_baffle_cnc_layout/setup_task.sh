#!/bin/bash
echo "=== Setting up speaker_baffle_cnc_layout task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists and is clean
mkdir -p /home/ga/Documents/SolveSpace
rm -f /home/ga/Documents/SolveSpace/speaker_baffle.slvs
chown -R ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace with no file (blank canvas)
launch_solvespace ""

# Wait for SolveSpace to start
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 3

# Maximize the window and arrange property browser
maximize_solvespace
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="