#!/bin/bash
set -e
echo "=== Setting up algorithm_pattern task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts to ensure fresh run
rm -f /home/ga/algorithm_level1.png
rm -f /home/ga/algorithm_level2.png
rm -f /home/ga/algorithm_level3.png

# Kill any existing GCompris processes
kill_gcompris

# Launch GCompris at main menu
# The agent must find the specific activity themselves
launch_gcompris

# Ensure window is maximized for consistent coordinates/visiblity
maximize_gcompris

# Dismiss any startup dialogs if they appear
sleep 1
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="