#!/bin/bash
set -e
echo "=== Setting up create_warehouse_layout task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# Clean up previous run artifacts
rm -f /home/ga/Diagrams/warehouse_layout.eddx
rm -f /home/ga/Diagrams/warehouse_layout.png
rm -f /tmp/task_result.json

# Kill any existing EdrawMax instances to ensure clean state
kill_edrawmax

# Launch EdrawMax (opens to Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banner)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="