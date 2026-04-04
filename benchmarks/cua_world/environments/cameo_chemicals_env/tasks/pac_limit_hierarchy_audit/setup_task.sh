#!/bin/bash
# setup_task.sh - Pre-task hook for PAC hierarchy audit
set -e

echo "=== Setting up PAC Limit Hierarchy Audit Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure clean state: Remove output file if it exists
OUTPUT_FILE="/home/ga/Desktop/pac_audit_results.txt"
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing previous output file..."
    rm -f "$OUTPUT_FILE"
fi

# Ensure Firefox is running and valid
# If it's already running, kill it to ensure a fresh session
if pgrep -f firefox > /dev/null; then
    echo "Restarting Firefox for clean state..."
    kill_firefox "ga"
fi

# Launch Firefox to CAMEO Chemicals homepage
launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga"

# Take initial screenshot for evidence
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="