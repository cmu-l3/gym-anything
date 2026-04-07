#!/bin/bash
echo "=== Setting up spatial_tetrahedron_wireframe task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists and is clean
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace
rm -f /home/ga/Documents/SolveSpace/tetrahedron.slvs

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace with a blank canvas
launch_solvespace ""

# Wait for SolveSpace window to appear
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window for full visibility
maximize_solvespace
sleep 1

# Take an initial screenshot to document starting state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Setup complete ==="
echo "Goal: Draw a 50mm regular tetrahedron in 'Sketch In 3D' mode, anchor to origin, save as ~/Documents/SolveSpace/tetrahedron.slvs"