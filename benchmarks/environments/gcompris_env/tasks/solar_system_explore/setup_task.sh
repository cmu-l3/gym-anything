#!/bin/bash
set -e
echo "=== Setting up Solar System Explore task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure ~/Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing output file (clean state)
rm -f /home/ga/Documents/planets_in_order.txt

# Kill any existing GCompris instance
kill_gcompris

# Launch GCompris at the main menu
# The agent must navigate the menus themselves
launch_gcompris

# Maximize the window
maximize_gcompris

# Dismiss any startup dialogs if they appear
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Solar System Explore task setup complete ==="