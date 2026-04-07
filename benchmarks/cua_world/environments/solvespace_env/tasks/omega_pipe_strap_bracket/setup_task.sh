#!/bin/bash
echo "=== Setting up omega_pipe_strap_bracket task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Remove any previous output file
rm -f /home/ga/Documents/SolveSpace/pipe_strap.slvs

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

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
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo "=== Task setup complete ==="