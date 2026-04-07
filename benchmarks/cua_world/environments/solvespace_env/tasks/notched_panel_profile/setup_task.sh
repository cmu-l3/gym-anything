#!/bin/bash
set -e

echo "=== Setting up notched_panel_profile task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f /home/ga/Documents/SolveSpace/notched_panel.slvs

# Ensure workspace directory exists and has correct permissions
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Kill any existing SolveSpace instances to ensure clean state
kill_solvespace

# Launch SolveSpace with a blank new sketch
launch_solvespace

# Wait for SolveSpace to appear
if ! wait_for_solvespace 30; then
    echo "ERROR: SolveSpace did not launch"
    exit 1
fi

# Allow UI to settle
sleep 3

# Maximize and arrange windows (custom utility from env)
maximize_solvespace
sleep 1

# Dismiss any startup dialogs that might block the agent
DISPLAY=:1 xdotool key --clearmodifiers Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state as evidence
take_screenshot /tmp/task_initial_state.png

echo "=== notched_panel_profile task setup complete ==="
echo "SolveSpace is open with a blank new sketch."
echo "Agent should create the 80x50mm notched panel profile and save to ~/Documents/SolveSpace/notched_panel.slvs"