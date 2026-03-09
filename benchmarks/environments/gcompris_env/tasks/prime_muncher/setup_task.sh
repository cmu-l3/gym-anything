#!/bin/bash
set -e

echo "=== Setting up Prime Number Muncher task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ensure clean state
kill_gcompris

# Launch GCompris
echo "Launching GCompris..."
launch_gcompris

# Wait and maximize
sleep 5
maximize_gcompris
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "GCompris is running at Main Menu."
echo "Agent must navigate to: Math -> Calculation -> Number Munchers."