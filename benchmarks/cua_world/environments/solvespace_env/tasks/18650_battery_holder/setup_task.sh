#!/bin/bash
echo "=== Setting up 18650_battery_holder task ==="

source /workspace/scripts/task_utils.sh

# Remove any previous files (reset state)
rm -f /home/ga/Documents/SolveSpace/18650_holder.slvs
rm -f /home/ga/Documents/SolveSpace/18650_holder.stl

# Ensure correct workspace directory
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with blank canvas
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window so agent has full workspace (CRITICAL for visual access)
maximize_solvespace
sleep 1

# Take a screenshot to confirm start state
take_screenshot /tmp/task_initial.png
echo "Task start state screenshot saved to /tmp/task_initial.png"

echo "=== Setup complete ==="