#!/bin/bash
echo "=== Setting up parametric_floor_plan_layout task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Define output path
OUTPUT_DIR="/home/ga/Documents/SolveSpace"
OUTPUT_FILE="$OUTPUT_DIR/l_shape_floor_plan.slvs"

# Ensure workspace directory exists and has correct permissions
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "/home/ga/Documents"

# Remove any previous output file to ensure clean state
rm -f "$OUTPUT_FILE" 2>/dev/null || true

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with a blank canvas
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window so agent has full workspace
maximize_solvespace
sleep 1

# Take an initial screenshot as evidence of starting state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Setup complete ==="