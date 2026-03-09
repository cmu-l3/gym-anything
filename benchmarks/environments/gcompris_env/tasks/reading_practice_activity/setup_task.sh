#!/bin/bash
set -e
echo "=== Setting up Reading Practice Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f /home/ga/Documents/reading_log.txt
mkdir -p /home/ga/Documents

# Ensure GCompris is in a known state (closed)
kill_gcompris

# Launch GCompris at the main menu
# We use the utility function which handles finding the binary and waiting for the window
launch_gcompris

# Maximize the window to ensure VLM can see details clearly
maximize_gcompris

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "GCompris launched. Agent must navigate to Reading -> Reading Practice."