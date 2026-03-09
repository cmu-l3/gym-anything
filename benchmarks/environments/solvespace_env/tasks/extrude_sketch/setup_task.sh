#!/bin/bash
echo "=== Setting up extrude_sketch task ==="

source /workspace/scripts/task_utils.sh

# Remove any previous output file
rm -f /home/ga/Documents/SolveSpace/block.slvs

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with no file (blank canvas for creating the sketch from scratch)
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window
maximize_solvespace
sleep 1

# Take a screenshot to confirm start state
take_screenshot /tmp/extrude_sketch_start.png
echo "Task start state screenshot saved to /tmp/extrude_sketch_start.png"

echo "=== extrude_sketch task setup complete ==="
echo "Agent should see: SolveSpace with blank canvas"
echo "Goal: Draw 40x30mm rectangle sketch, extrude 15mm, save as ~/Documents/SolveSpace/block.slvs"
