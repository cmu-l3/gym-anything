#!/bin/bash
set -e
echo "=== Setting up Water Reactivity Assessment task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Clean any previous report file to ensure freshness
rm -f /home/ga/Documents/water_reactivity_report.txt
echo "Cleaned previous report file."

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Kill any existing Firefox instances to start fresh
kill_firefox ga

# Launch Firefox to CAMEO Chemicals homepage
# Using a slightly longer timeout to ensure it loads
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga 45

# Additional wait for page load and DOM readiness
sleep 5

# Ensure window is maximized for best visibility
maximize_firefox

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Water Reactivity Assessment task setup complete ==="