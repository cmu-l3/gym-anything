#!/bin/bash
set -e
echo "=== Setting up Projectile Physics Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
kill_gcompris

# Launch GCompris
echo "Launching GCompris..."
launch_gcompris

# Wait for window and maximize
sleep 5
maximize_gcompris
sleep 2

# Take initial screenshot of the Main Menu
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "GCompris is at the Main Menu."
echo "Agent must navigate to Science -> Gravity and complete the task."