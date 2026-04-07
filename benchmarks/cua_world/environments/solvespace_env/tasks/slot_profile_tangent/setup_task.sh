#!/bin/bash
echo "=== Setting up slot_profile_tangent task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

OUTPUT_DIR="/home/ga/Documents/SolveSpace"
OUTPUT_FILE="$OUTPUT_DIR/slot_profile.slvs"

# Remove any previous output file
rm -f "$OUTPUT_FILE"

# Ensure workspace directory exists
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with no file (blank canvas)
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window so agent has full workspace
maximize_solvespace
sleep 1

# Take a screenshot to confirm start state
take_screenshot /tmp/task_initial.png
echo "Task start state screenshot saved to /tmp/task_initial.png"

echo "=== Setup complete ==="
echo "Goal: Draw 40x12mm slot profile with tangent arcs, save as $OUTPUT_FILE"