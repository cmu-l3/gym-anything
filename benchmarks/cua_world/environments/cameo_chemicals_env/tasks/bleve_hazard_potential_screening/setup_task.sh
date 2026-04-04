#!/bin/bash
# setup_task.sh - Setup for BLEVE Hazard Potential Screening
set -e

echo "=== Setting up BLEVE Hazard Potential Screening Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(cat /tmp/task_start_time)"

# 2. Clean up previous artifacts
OUTPUT_FILE="/home/ga/Documents/bleve_risk_assessment.csv"
rm -f "$OUTPUT_FILE" 2>/dev/null || true
# Ensure directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"
chown ga:ga "$(dirname "$OUTPUT_FILE")"

# 3. Launch Firefox to CAMEO Chemicals
# Using the specific search page makes it slightly faster/more reliable for the agent to start
launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga"

# 4. Capture Initial State Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target Output: $OUTPUT_FILE"