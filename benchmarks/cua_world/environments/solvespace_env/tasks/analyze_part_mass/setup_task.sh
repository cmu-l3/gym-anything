#!/bin/bash
echo "=== Setting up analyze_part_mass task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists and is clean
mkdir -p /home/ga/Documents/SolveSpace
rm -f /home/ga/Documents/SolveSpace/side_extruded.slvs
rm -f /home/ga/Documents/SolveSpace/mass_report.txt

# Verify the source file exists
if [ ! -f "/opt/solvespace_samples/side.slvs" ]; then
    echo "ERROR: /opt/solvespace_samples/side.slvs not found"
    exit 1
fi

# Copy the file to the workspace
cp /opt/solvespace_samples/side.slvs /home/ga/Documents/SolveSpace/side.slvs
chown -R ga:ga /home/ga/Documents/SolveSpace

# Record original group count (to verify agent adds an extrusion group)
grep -c "Group.type" /home/ga/Documents/SolveSpace/side.slvs > /tmp/initial_group_count.txt

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace with the target file loaded
launch_solvespace "/home/ga/Documents/SolveSpace/side.slvs"

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window for full visibility
maximize_solvespace
sleep 1

# Take a screenshot to document the starting state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved."

echo "=== Task setup complete ==="