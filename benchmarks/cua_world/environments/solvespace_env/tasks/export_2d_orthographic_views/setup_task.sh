#!/bin/bash
echo "=== Setting up export_2d_orthographic_views task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

# Remove any previous output files to ensure a clean state
rm -f /home/ga/Documents/SolveSpace/side_face.svg
rm -f /home/ga/Documents/SolveSpace/side_edge.svg

# Verify the source file exists (downloaded during environment install)
if [ ! -f "/opt/solvespace_samples/side.slvs" ]; then
    echo "ERROR: /opt/solvespace_samples/side.slvs not found!"
    exit 1
fi

FSIZE=$(stat -c%s "/opt/solvespace_samples/side.slvs")
echo "Source file verified: /opt/solvespace_samples/side.slvs ($FSIZE bytes)"

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace directly with the required part file
launch_solvespace "/opt/solvespace_samples/side.slvs"

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window and arrange UI
maximize_solvespace
sleep 1

# Take an initial screenshot to confirm the start state
take_screenshot /tmp/task_initial.png
echo "Task start state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="