#!/bin/bash
echo "=== Setting up step_translate_pattern task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

# Remove any previous output files
rm -f /home/ga/Documents/SolveSpace/side_with_holes.slvs

# Verify the source file exists
if [ ! -f "/opt/solvespace_samples/side.slvs" ]; then
    echo "ERROR: /opt/solvespace_samples/side.slvs not found"
    exit 1
fi

# Record initial group count of the source file
INITIAL_GROUPS=$(grep -c "AddGroup" /opt/solvespace_samples/side.slvs 2>/dev/null || echo "0")
echo "$INITIAL_GROUPS" > /tmp/initial_group_count.txt

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace with the source file
launch_solvespace "/opt/solvespace_samples/side.slvs"

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 6

# Maximize the window and move property browser out of the way
maximize_solvespace
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target output: /home/ga/Documents/SolveSpace/side_with_holes.slvs"