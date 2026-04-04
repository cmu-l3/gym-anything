#!/bin/bash
# setup_task.sh - Setup for Fire Fighting Foam Compatibility Audit

echo "=== Setting up Fire Fighting Foam Audit Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state: remove previous report if it exists
rm -f /home/ga/Documents/foam_audit.txt

# Create Documents directory if it doesn't exist
sudo -u ga mkdir -p /home/ga/Documents

# Launch Firefox to CAMEO Chemicals
echo "Launching Firefox..."
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga 60

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Instructions: Audit 6 chemicals for foam compatibility and save report to ~/Documents/foam_audit.txt"