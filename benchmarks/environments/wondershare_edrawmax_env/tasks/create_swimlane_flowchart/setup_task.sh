#!/bin/bash
set -e
echo "=== Setting up create_swimlane_flowchart task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# ensure directory exists
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# Clean up previous run artifacts
rm -f /home/ga/Diagrams/incident_management_swimlane.eddx
rm -f /home/ga/Diagrams/incident_management_swimlane.png
rm -f /tmp/task_result.json

# Kill any running EdrawMax instances to ensure clean start
echo "Killing existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax (no file argument -> starts at Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login and File Recovery)
dismiss_edrawmax_dialogs

# Maximize the window for better agent visibility
maximize_edrawmax

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="