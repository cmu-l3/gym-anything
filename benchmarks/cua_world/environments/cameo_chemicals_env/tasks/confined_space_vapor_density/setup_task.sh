#!/bin/bash
set -e
echo "=== Setting up Confined Space Vapor Density Assessment task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
record_start_time

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Remove any pre-existing report file to ensure new creation
rm -f /home/ga/Documents/confined_space_vapor_report.txt

# Kill any existing Firefox instances
kill_firefox ga

# Launch Firefox to CAMEO Chemicals homepage
# Using a slightly longer timeout as the first launch can be slow
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga 45

# Wait for page to fully load
sleep 5

# Ensure window is maximized for best visibility
maximize_firefox

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="