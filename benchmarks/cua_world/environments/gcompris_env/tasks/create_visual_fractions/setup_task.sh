#!/bin/bash
set -e
echo "=== Setting up Create Visual Fractions Task ==="

# Load shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up previous run artifacts
rm -f /home/ga/fractions_log.txt
rm -f /home/ga/fraction_success.png
rm -f /tmp/task_result.json

# Ensure GCompris is in a clean state
kill_gcompris

# Launch GCompris
# We launch it to the main menu so the agent has to navigate
echo "Launching GCompris..."
launch_gcompris

# Maximize the window for better visibility
maximize_gcompris

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "GCompris is running at the main menu."
echo "Agent goal: Navigate to Math > Numeration > Create fractions."