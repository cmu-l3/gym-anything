#!/bin/bash
echo "=== Setting up Decomposition Product Screening Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Remove any previous report file to ensure a fresh start
rm -f /home/ga/Documents/decomposition_report.txt

# Kill any existing Firefox instances to start clean
kill_firefox ga

# Launch Firefox to CAMEO Chemicals homepage
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga 45

# Wait for page to load
sleep 5

# Maximize and focus (Critical for agent visibility)
maximize_firefox

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="