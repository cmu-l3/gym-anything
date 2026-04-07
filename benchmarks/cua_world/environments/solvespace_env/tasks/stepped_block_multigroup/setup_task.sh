#!/bin/bash
echo "=== Setting up stepped_block_multigroup task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Target output file
OUTPUT_FILE="/home/ga/Documents/SolveSpace/stepped_block.slvs"

# Remove any previous output file
rm -f "$OUTPUT_FILE"

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with no file (blank canvas for creating the model from scratch)
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window and move Property Browser
maximize_solvespace
sleep 1

# Take a screenshot to confirm start state
take_screenshot /tmp/task_initial.png
echo "Task start state screenshot saved to /tmp/task_initial.png"

echo "=== setup complete ==="
echo "Agent should see: SolveSpace with a blank canvas"
echo "Goal: Draw an 80x60mm rectangle, extrude 20mm, sketch 40x30mm rectangle on top face, extrude 15mm, save as $OUTPUT_FILE"