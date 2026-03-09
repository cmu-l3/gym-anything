#!/bin/bash
set -e
echo "=== Setting up Geography Quiz Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean state
rm -f /home/ga/Documents/geography_score.png 2>/dev/null || true
mkdir -p /home/ga/Documents

# Kill any existing instances
kill_gcompris

# Launch GCompris at the main menu
echo "Launching GCompris..."
launch_gcompris

# Maximize window for best visibility
maximize_gcompris

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "GCompris is running at Main Menu."
echo "Agent must navigate to Geography > Locate Region > South America."