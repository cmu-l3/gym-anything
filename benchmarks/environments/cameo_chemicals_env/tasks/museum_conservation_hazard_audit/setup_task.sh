#!/bin/bash
# setup_task.sh - Setup for museum_conservation_hazard_audit
set -e

echo "=== Setting up Museum Conservation Hazard Audit ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure Document directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up previous run artifacts (Anti-gaming: ensure fresh file creation)
OUTPUT_FILE="/home/ga/Documents/conservation_safety_audit.csv"
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing stale output file: $OUTPUT_FILE"
    rm "$OUTPUT_FILE"
fi

# Launch Firefox to CAMEO Chemicals
echo "Launching Firefox..."
launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga" 45

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="