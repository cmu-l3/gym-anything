#!/bin/bash
echo "=== Setting up Molecular Formula Hazard Analysis task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure clean state: Remove output files if they exist
rm -f /home/ga/Desktop/isomer_hazards.csv
rm -f /home/ga/Desktop/worst_case_analysis.txt

# Create Firefox profile and ensure it's ready
# (handled by environment setup, but we double check processes)
kill_firefox "ga"

# Launch Firefox to CAMEO Chemicals homepage
launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga"

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="