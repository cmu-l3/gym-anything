#!/bin/bash
echo "=== Setting up modify_parametric_dimensions task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create workspace directory
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

# Remove any previous task artifacts
rm -f /home/ga/Documents/SolveSpace/base_enlarged.slvs

# Copy the real starting file from the official samples
if [ ! -f "/opt/solvespace_samples/base.slvs" ]; then
    echo "ERROR: /opt/solvespace_samples/base.slvs not found!"
    exit 1
fi

cp /opt/solvespace_samples/base.slvs /home/ga/Documents/SolveSpace/base.slvs
chown ga:ga /home/ga/Documents/SolveSpace/base.slvs

echo "Copied base.slvs to workspace."

# Kill any existing SolveSpace instance to ensure a clean state
kill_solvespace

# Launch SolveSpace with the starting file
launch_solvespace "/home/ga/Documents/SolveSpace/base.slvs"

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

echo "=== modify_parametric_dimensions task setup complete ==="