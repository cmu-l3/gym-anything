#!/bin/bash
echo "=== Setting up draw_rectangle task ==="

source /workspace/scripts/task_utils.sh

# Remove any previous output file
rm -f /home/ga/Documents/SolveSpace/rectangle.slvs

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

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
take_screenshot /tmp/draw_rectangle_start.png
echo "Task start state screenshot saved to /tmp/draw_rectangle_start.png"

echo "=== draw_rectangle task setup complete ==="
echo "Agent should see: SolveSpace with blank canvas"
echo "Goal: Draw 80x50mm constrained rectangle, save as ~/Documents/SolveSpace/rectangle.slvs"
