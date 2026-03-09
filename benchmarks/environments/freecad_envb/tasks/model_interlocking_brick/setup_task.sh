#!/bin/bash
set -e
echo "=== Setting up model_interlocking_brick task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Clean up previous artifacts
rm -f /home/ga/Documents/FreeCAD/brick_2x2.FCStd
rm -f /tmp/brick_analysis.json
rm -f /tmp/task_result.json

# Ensure document directory exists
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Launch FreeCAD with an empty document
# We use the Part Design workbench by default for this task as it's most suitable,
# but the agent can switch.
echo "Starting FreeCAD..."
kill_freecad
launch_freecad

# Wait for window and maximize
wait_for_freecad 30
maximize_freecad

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="