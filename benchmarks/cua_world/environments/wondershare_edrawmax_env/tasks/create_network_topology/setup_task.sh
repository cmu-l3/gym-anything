#!/bin/bash
set -e
echo "=== Setting up create_network_topology task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any running EdrawMax instances
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Ensure Documents directory exists and clean up previous task artifacts
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/network_topology.eddx 2>/dev/null || true
rm -f /home/ga/Documents/network_topology.png 2>/dev/null || true

# Launch EdrawMax fresh (opens to home/start screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login and File Recovery)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
take_screenshot /tmp/task_initial.png
echo "Start state screenshot saved to /tmp/task_initial.png"

echo "=== create_network_topology task setup complete ==="
echo "EdrawMax is open. Agent should create a network diagram and save to ~/Documents/network_topology.eddx and .png"