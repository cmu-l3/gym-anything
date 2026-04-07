#!/bin/bash
echo "=== Setting up constrained_triangle task ==="

source /workspace/scripts/task_utils.sh

# Target file path
OUTPUT_DIR="/home/ga/Documents/SolveSpace"
OUTPUT_FILE="$OUTPUT_DIR/right_triangle.slvs"

# Ensure workspace directory exists and is clean
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"
rm -f "$OUTPUT_FILE"
rm -f /tmp/task_result.json
rm -f /tmp/right_triangle.slvs

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace with a blank canvas
echo "Launching SolveSpace..."
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace window..."
wait_for_solvespace 30
sleep 5

# Maximize the window to ensure the agent has full workspace visibility
maximize_solvespace
sleep 1

# Take a screenshot to document the initial state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== constrained_triangle task setup complete ==="