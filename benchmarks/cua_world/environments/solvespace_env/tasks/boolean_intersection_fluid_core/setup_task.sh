#!/bin/bash
echo "=== Setting up boolean_intersection_fluid_core task ==="

source /workspace/scripts/task_utils.sh

# Ensure python dependencies are available for geometry verification
if ! python3 -c "import trimesh" 2>/dev/null; then
    echo "Installing trimesh and numpy for verification..."
    apt-get update && apt-get install -y python3-numpy python3-pip
    pip3 install trimesh --break-system-packages 2>/dev/null || pip3 install trimesh
fi

# Record task start time (anti-gaming timestamp)
date +%s > /tmp/task_start_time.txt

# Clean up any previous attempts
rm -f /home/ga/Documents/SolveSpace/fluid_core.slvs
rm -f /home/ga/Documents/SolveSpace/fluid_core.stl

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with no file (blank canvas)
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window
maximize_solvespace
sleep 1

# Take a screenshot to confirm start state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="