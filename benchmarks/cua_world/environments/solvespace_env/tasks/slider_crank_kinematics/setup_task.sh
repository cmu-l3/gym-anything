#!/bin/bash
echo "=== Setting up slider_crank_kinematics task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Target output file
TARGET_FILE="/home/ga/Documents/SolveSpace/slider_crank.slvs"

# Clean up any existing file
rm -f "$TARGET_FILE" 2>/dev/null

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace with a clean blank canvas
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window and arrange the Property Browser so the canvas is unobstructed
maximize_solvespace
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved: $(stat -c %s /tmp/task_initial.png 2>/dev/null || echo 0) bytes"

echo "=== Task setup complete ==="