#!/bin/bash
echo "=== Setting up v_block_profile task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Target file path
OUTPUT_PATH="/home/ga/Documents/SolveSpace/v_block_profile.slvs"

# Remove any previous output file to ensure a clean state
rm -f "$OUTPUT_PATH"

# Ensure workspace directory exists and has correct permissions
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with no file (blank canvas for creating the sketch from scratch)
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window and adjust property browser
maximize_solvespace
sleep 1

# Take a screenshot to confirm start state
take_screenshot /tmp/task_initial.png
echo "Task start state screenshot saved to /tmp/task_initial.png"

echo "=== v_block_profile task setup complete ==="