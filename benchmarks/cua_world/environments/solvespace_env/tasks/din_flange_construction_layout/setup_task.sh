#!/bin/bash
echo "=== Setting up din_flange_construction_layout task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

# Remove any previous output file
rm -f /home/ga/Documents/SolveSpace/dn50_flange.slvs

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

echo "=== Task setup complete ==="
echo "Agent should see: SolveSpace with blank canvas"
echo "Goal: Model DN50 PN16 flange with construction pitch circle, save to ~/Documents/SolveSpace/dn50_flange.slvs"