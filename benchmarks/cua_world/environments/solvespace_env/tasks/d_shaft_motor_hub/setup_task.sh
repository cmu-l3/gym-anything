#!/bin/bash
set -e
echo "=== Setting up d_shaft_motor_hub task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists and has proper permissions
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Clean up any potential previous attempt files
rm -f /home/ga/Documents/SolveSpace/d_shaft_hub.slvs

# Ensure SolveSpace is completely stopped before starting fresh
kill_solvespace

# Launch SolveSpace with a blank canvas
echo "Starting SolveSpace..."
launch_solvespace ""

# Wait for the UI to be ready
wait_for_solvespace 30
sleep 5

# Maximize to give the agent full view of the workspace
maximize_solvespace
sleep 1

# Take an initial screenshot for the trajectory
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="