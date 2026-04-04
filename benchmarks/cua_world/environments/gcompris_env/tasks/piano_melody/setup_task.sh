#!/bin/bash
set -e
echo "=== Setting up Piano Melody task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure a clean state by killing any existing instances
echo "Cleaning up previous sessions..."
kill_gcompris

# Launch GCompris at the main menu
echo "Launching GCompris..."
launch_gcompris
sleep 5

# maximize window to ensure all icons are visible
maximize_gcompris
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

# Remove any stale result files
rm -f /tmp/piano_result.png
rm -f /tmp/task_result.json

echo "=== Task setup complete ==="
echo "GCompris is open at the main menu."