#!/bin/bash
echo "=== Setting up nema17_base_modification task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Clean previous outputs if they exist
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace
rm -f /home/ga/Documents/SolveSpace/nema17_base.slvs
rm -f /home/ga/Documents/SolveSpace/nema17_base.stl
rm -f /tmp/nema17_base.slvs

# Verify the source real-data file exists
if [ ! -f "/opt/solvespace_samples/base.slvs" ]; then
    echo "ERROR: Missing required tutorial file /opt/solvespace_samples/base.slvs"
    exit 1
fi

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace empty (forcing agent to navigate File -> Open)
launch_solvespace ""

# Wait for window to load
echo "Waiting for SolveSpace..."
wait_for_solvespace 30
sleep 3

# Maximize window and separate property browser
maximize_solvespace
sleep 1

# Take initial screenshot of clean state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="