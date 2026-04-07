#!/bin/bash
echo "=== Setting up radial_pin_shaft_collar task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists and is clean
WORKSPACE="/home/ga/Documents/SolveSpace"
mkdir -p "$WORKSPACE"
chown ga:ga "$WORKSPACE"

rm -f "$WORKSPACE/radial_collar.slvs"
rm -f "$WORKSPACE/radial_collar.stl"

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with a blank canvas
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window and move property browser
maximize_solvespace
sleep 1

# Take a screenshot to confirm start state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== radial_pin_shaft_collar task setup complete ==="