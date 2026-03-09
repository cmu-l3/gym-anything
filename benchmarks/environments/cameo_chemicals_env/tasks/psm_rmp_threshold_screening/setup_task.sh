#!/bin/bash
echo "=== Setting up PSM/RMP Threshold Screening Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Clean up any previous run artifacts
rm -f /home/ga/Documents/regulatory_threshold_audit.csv 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Kill any existing Firefox instances to ensure clean state
kill_firefox ga

# Launch Firefox to CAMEO Chemicals homepage
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga 60

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="