#!/bin/bash
echo "=== Setting up Gas/Vapor Detection Profile Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Remove any previous report to ensure fresh creation
REPORT_FILE="/home/ga/Desktop/gas_detection_profiles.txt"
rm -f "$REPORT_FILE"
echo "Cleared previous report file at $REPORT_FILE"

# Ensure Desktop directory exists
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Launch Firefox to CAMEO Chemicals homepage
# This ensures the agent starts at the correct tool
launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga" 60

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Agent is positioned at CAMEO Chemicals homepage."
echo "Target output file: $REPORT_FILE"