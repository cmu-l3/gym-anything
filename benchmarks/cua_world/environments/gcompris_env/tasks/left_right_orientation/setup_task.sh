#!/bin/bash
set -e
echo "=== Setting up Left/Right Orientation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
kill_gcompris

# Launch GCompris
echo "Launching GCompris..."
launch_gcompris
sleep 2

# Maximize window
maximize_gcompris
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "GCompris is open at the main menu."