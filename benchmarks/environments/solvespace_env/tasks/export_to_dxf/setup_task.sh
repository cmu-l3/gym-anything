#!/bin/bash
echo "=== Setting up export_to_dxf task ==="

source /workspace/scripts/task_utils.sh

# Remove any previous output file
rm -f /home/ga/Documents/SolveSpace/divider.dxf

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

# Verify the real source file exists (downloaded during install)
if [ ! -f "/opt/solvespace_samples/divider.slvs" ]; then
    echo "ERROR: /opt/solvespace_samples/divider.slvs not found"
    exit 1
fi

FSIZE=$(stat -c%s "/opt/solvespace_samples/divider.slvs")
echo "Source file: /opt/solvespace_samples/divider.slvs ($FSIZE bytes)"

# Copy divider.slvs to the workspace so the agent can see it
cp /opt/solvespace_samples/divider.slvs /home/ga/Documents/SolveSpace/divider.slvs
chown ga:ga /home/ga/Documents/SolveSpace/divider.slvs

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with the divider.slvs file
launch_solvespace "/home/ga/Documents/SolveSpace/divider.slvs"

# Wait for SolveSpace to fully load the file
echo "Waiting for SolveSpace to load divider.slvs..."
wait_for_solvespace 30
sleep 6

# Maximize the window
maximize_solvespace
sleep 1

# Take a screenshot to confirm start state
take_screenshot /tmp/export_to_dxf_start.png
echo "Task start state screenshot saved to /tmp/export_to_dxf_start.png"

echo "=== export_to_dxf task setup complete ==="
echo "Agent should see: SolveSpace with divider.slvs loaded"
echo "Goal: Export drawing to /home/ga/Documents/SolveSpace/divider.dxf"
