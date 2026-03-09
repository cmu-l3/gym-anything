#!/bin/bash
# setup_task.sh - Setup for Odor Warning Property Safety Audit

echo "=== Setting up Odor Warning Audit Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time
echo "Task start time: $(cat /tmp/task_start_time)"

# Clean up any previous run artifacts
rm -f /home/ga/Documents/odor_safety_audit.csv 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Kill any existing Firefox instances to ensure clean state
kill_firefox ga

# Launch Firefox to CAMEO Chemicals homepage
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga 60

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="