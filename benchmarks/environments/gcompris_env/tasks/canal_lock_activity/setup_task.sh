#!/bin/bash
set -e
echo "=== Setting up Canal Lock Activity task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Remove any previous screenshot artifacts
rm -f /home/ga/canal_lock_complete.png

# Kill any existing GCompris instance
kill_gcompris

# Launch GCompris at home screen
launch_gcompris

# Maximize and focus
maximize_gcompris

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Canal Lock Activity task setup complete ==="