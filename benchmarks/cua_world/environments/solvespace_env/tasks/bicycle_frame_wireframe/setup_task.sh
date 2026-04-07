#!/bin/bash
set -e
echo "=== Setting up bicycle_frame_wireframe task ==="

source /workspace/scripts/task_utils.sh

# Define expected output path
OUTPUT_PATH="/home/ga/Documents/SolveSpace/bike_wireframe.slvs"

# Clean up any existing file
rm -f "$OUTPUT_PATH"

# Ensure workspace directory exists and has correct permissions
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace with a blank canvas
echo "Launching SolveSpace..."
launch_solvespace ""

# Wait for SolveSpace window to appear
wait_for_solvespace 30
sleep 5

# Maximize the window to ensure the agent has full view of the canvas
maximize_solvespace
sleep 1

# Take an initial screenshot to provide evidence of the starting state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== bicycle_frame_wireframe task setup complete ==="