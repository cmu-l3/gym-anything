#!/bin/bash
echo "=== Setting up connecting_rod_profile task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists and is clean
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Remove any previous output files
rm -f /home/ga/Documents/SolveSpace/connecting_rod.slvs
rm -f /home/ga/Documents/SolveSpace/connecting_rod.stl

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace with a blank canvas
launch_solvespace ""

# Wait for SolveSpace to fully initialize
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window and adjust Property Browser
maximize_solvespace
sleep 1

# Take a screenshot to document initial state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== setup_task complete ==="