#!/bin/bash
echo "=== Setting up Chemical Cloud Behavior Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts to ensure fresh start
rm -f /home/ga/Desktop/cloud_behavior_assessment.txt

# Kill any existing Firefox instances
kill_firefox ga

# Launch Firefox directly to CAMEO Chemicals homepage
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga 45

# Wait for page to settle
sleep 5

# Ensure window is maximized for the agent
maximize_firefox

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Firefox open at CAMEO Chemicals."
echo "Previous output files removed."