#!/bin/bash
echo "=== Setting up square_flange_shaft task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f /home/ga/Documents/SolveSpace/square_flange_shaft.slvs
rm -f /tmp/task_export.stl
rm -f /tmp/task_result.json

# Ensure output directory exists and has proper permissions
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instances to start fresh
kill_solvespace
sleep 1

# Launch SolveSpace with a fresh new sketch
launch_solvespace ""

# Wait for SolveSpace window to appear
if ! wait_for_solvespace 30; then
    echo "WARNING: SolveSpace did not appear to start"
fi

# Maximize canvas and position property browser appropriately
maximize_solvespace
sleep 1

# Dismiss any popup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial state screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "SolveSpace is open with a new empty sketch."
echo "Agent should create the square-flanged shaft and save to:"
echo "  /home/ga/Documents/SolveSpace/square_flange_shaft.slvs"