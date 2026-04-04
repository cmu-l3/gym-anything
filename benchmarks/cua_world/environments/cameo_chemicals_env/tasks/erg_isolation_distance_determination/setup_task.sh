#!/bin/bash
echo "=== Setting up ERG Isolation Distance Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure clean state
rm -f /home/ga/Documents/evacuation_zones.txt 2>/dev/null || true
sudo -u ga mkdir -p /home/ga/Documents

# Kill any existing Firefox instances
kill_firefox ga

# Launch Firefox to CAMEO Chemicals homepage
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="