#!/bin/bash
set -e
echo "=== Setting up Waterway Spill Behavior Classification task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (critical for anti-gaming verification)
record_start_time

# Clean up any previous run artifacts to ensure a clean state
echo "Cleaning up previous outputs..."
rm -f /home/ga/Documents/spill_behavior_report.txt
rm -f /home/ga/Documents/spill_behavior_summary.csv

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Kill any existing Firefox instances to ensure fresh start
kill_firefox ga

# Launch Firefox to CAMEO Chemicals homepage
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga 45

# Wait for page to load
sleep 5

# Maximize and focus for visibility
maximize_firefox

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="