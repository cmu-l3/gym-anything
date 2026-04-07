#!/bin/bash
echo "=== Setting up symmetric_trapezoid_channel task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create output directory
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Remove any previous result
rm -f /home/ga/Documents/SolveSpace/channel_profile.slvs

# Kill any existing SolveSpace
kill_solvespace

# Launch SolveSpace with a fresh empty sketch
launch_solvespace ""

# Wait for SolveSpace window to appear
wait_for_solvespace 30

# Maximize and arrange windows
sleep 2
maximize_solvespace
sleep 1

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key --clearmodifiers Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "SolveSpace is open with a new empty sketch."
echo "Agent should create a trapezoid profile and save to ~/Documents/SolveSpace/channel_profile.slvs"