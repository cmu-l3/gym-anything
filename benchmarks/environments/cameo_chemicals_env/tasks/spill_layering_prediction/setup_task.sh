#!/bin/bash
set -e
echo "=== Setting up Spill Layering Prediction Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(cat /tmp/task_start_time)"

# Clean up any previous results to ensure fresh start
rm -f /home/ga/Desktop/spill_layering_results.txt

# Ensure Firefox is clean and ready
kill_firefox ga

# Launch Firefox to CAMEO Chemicals homepage
# Using the utility function from task_utils.sh which handles waiting/window management
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga 45

# Explicit wait for page load
sleep 5

# Ensure window is maximized for VLM visibility
maximize_firefox

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="