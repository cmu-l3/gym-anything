#!/bin/bash
set -e
echo "=== Setting up Binary Bulbs Activity ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure a clean state by killing any existing GCompris instances
kill_gcompris

# Launch GCompris at the main menu
# The agent is responsible for navigation, so we start at the root menu
echo "Launching GCompris..."
launch_gcompris

# Wait for window to settle
sleep 2

# Maximize the window to ensure elements are visible to the agent
maximize_gcompris

# Remove any stale screenshot from previous runs
rm -f /tmp/binary_bulb_final.png

# Take an initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "GCompris is running at the main menu."
echo "Task: Find 'Binary Bulbs', complete 3 levels, and screenshot to /tmp/binary_bulb_final.png"