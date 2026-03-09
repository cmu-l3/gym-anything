#!/bin/bash
echo "=== Setting up Isomer Physical State Differentiation Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/isomer_analysis.txt
echo "Cleaned previous output files."

# Launch Firefox to CAMEO Chemicals homepage
# Using the shared utility function to ensure consistent robust startup
launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga" 60

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="