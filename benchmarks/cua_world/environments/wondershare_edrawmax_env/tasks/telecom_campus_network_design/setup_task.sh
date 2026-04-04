#!/bin/bash
echo "=== Setting up telecom_campus_network_design task ==="

source /workspace/scripts/task_utils.sh

# Kill any running EdrawMax instances
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any leftover output file from previous runs
rm -f /home/ga/campus_network_topology.eddx 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/telecom_campus_network_design_start_ts

# Launch EdrawMax fresh (opens to home/new screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
sleep 2
take_screenshot /tmp/telecom_campus_network_design_start.png
echo "Start state screenshot saved to /tmp/telecom_campus_network_design_start.png"

echo "=== telecom_campus_network_design task setup complete ==="
echo "EdrawMax is open. Agent should design a campus network topology and save as /home/ga/campus_network_topology.eddx"
