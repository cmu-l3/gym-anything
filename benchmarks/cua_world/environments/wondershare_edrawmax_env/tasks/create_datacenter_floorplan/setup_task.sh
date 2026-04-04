#!/bin/bash
echo "=== Setting up create_datacenter_floorplan task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any running EdrawMax instances to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any leftover output files from previous runs
rm -f /home/ga/Documents/datacenter_floorplan.eddx 2>/dev/null || true
rm -f /home/ga/Documents/datacenter_floorplan.png 2>/dev/null || true

# Launch EdrawMax fresh (no file argument - opens to home/new screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banner)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
take_screenshot /tmp/task_initial.png
echo "Start state screenshot saved to /tmp/task_initial.png"

echo "=== setup_task.sh complete ==="
echo "EdrawMax is open. Agent should create floor plan and save to ~/Documents/datacenter_floorplan.eddx"