#!/bin/bash
echo "=== Setting up gothic_arch_profile task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace
rm -f /home/ga/Documents/SolveSpace/gothic_arch.slvs
rm -f /tmp/gothic_arch.slvs
rm -f /tmp/task_result.json

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace with a fresh empty sketch
launch_solvespace

# Wait for it to appear
wait_for_solvespace 30
sleep 3

# Maximize and arrange windows
maximize_solvespace
sleep 1

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key --clearmodifiers Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

# Verify initial screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo "=== gothic_arch_profile task setup complete ==="