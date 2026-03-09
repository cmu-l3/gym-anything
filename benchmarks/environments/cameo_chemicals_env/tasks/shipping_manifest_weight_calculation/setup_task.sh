#!/bin/bash
echo "=== Setting up shipping_manifest_weight_calculation task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Clean up any previous run artifacts to ensure fresh start
rm -f /home/ga/Documents/shipping_manifest.txt 2>/dev/null || true

# Kill any existing Firefox instances
kill_firefox ga

# Launch Firefox to CAMEO Chemicals homepage
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga 60

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="