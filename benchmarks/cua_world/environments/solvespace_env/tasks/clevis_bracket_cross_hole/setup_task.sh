#!/bin/bash
echo "=== Setting up clevis_bracket_cross_hole task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create workspace directory and set permissions
WORKSPACE="/home/ga/Documents/SolveSpace"
mkdir -p "$WORKSPACE"
chown ga:ga "$WORKSPACE"

# Clean up any existing files that might conflict
rm -f "$WORKSPACE/clevis_bracket.slvs"
rm -f "$WORKSPACE/clevis_bracket.stl"

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace with a blank canvas
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window and arrange the Property Browser so it's fully visible
maximize_solvespace
sleep 1

# Take an initial screenshot for the trajectory record
take_screenshot /tmp/task_initial.png
echo "Initial state recorded."

echo "=== Setup complete ==="