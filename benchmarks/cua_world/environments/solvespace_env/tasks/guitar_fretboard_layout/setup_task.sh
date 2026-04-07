#!/bin/bash
set -e
echo "=== Setting up guitar_fretboard_layout task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create workspace directory for the agent
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Remove any existing artifact from previous runs
rm -f /home/ga/Documents/SolveSpace/fretboard.slvs

# Ensure SolveSpace is not running from a previous session
kill_solvespace

# Launch SolveSpace with a blank canvas
echo "Starting SolveSpace..."
launch_solvespace ""

# Wait for window to appear
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window
maximize_solvespace
sleep 1

# Take screenshot of initial state (for evidence)
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="