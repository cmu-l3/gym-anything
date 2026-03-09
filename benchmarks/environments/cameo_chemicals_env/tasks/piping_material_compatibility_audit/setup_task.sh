#!/bin/bash
# Setup script for Piping Material Compatibility Audit task

echo "=== Setting up Piping Material Compatibility Audit ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists and clean previous artifacts
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/piping_audit.csv 2>/dev/null || true

# Kill any existing Firefox instances to ensure clean state
kill_firefox ga

# Launch Firefox directly to CAMEO Chemicals
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Agent should now search for chemicals and create the audit CSV."