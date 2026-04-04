#!/bin/bash
set -e
echo "=== Setting up AEGL Exposure Threshold Comparison Task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
rm -f /home/ga/Documents/aegl_report.txt 2>/dev/null || true

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Kill any existing Firefox instances to ensure clean state
kill_firefox ga

# Launch Firefox to CAMEO Chemicals homepage
# Using the utility function from task_utils.sh which handles window waiting/maximizing
echo "Launching Firefox to CAMEO Chemicals..."
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga 45

# Wait a moment for page to fully render
sleep 5

# Ensure window is maximized (redundant check)
maximize_firefox

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Firefox should be open at https://cameochemicals.noaa.gov/"
echo "Agent should create: /home/ga/Documents/aegl_report.txt"