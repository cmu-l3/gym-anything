#!/bin/bash
set -e
echo "=== Setting up Mirror Image Symmetry Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any previous result files
rm -f /home/ga/mirror_solved.png
rm -f /tmp/task_result.json

# Kill any existing GCompris instances to ensure clean state
kill_gcompris

# Launch GCompris at the main menu
echo "Launching GCompris..."
launch_gcompris
sleep 5

# Maximize the window (Critical for VLM visibility)
maximize_gcompris
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "GCompris is running at the main menu."
echo "Agent goal: Find 'Reflections' activity, solve the symmetry puzzle, and screenshot the result."