#!/bin/bash
set -e
echo "=== Setting up Flammability Range Assessment Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time

# Clean up any previous task artifacts
rm -f /home/ga/Documents/flammability_assessment.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Kill any existing Firefox
kill_firefox ga

# Wait a moment
sleep 2

# Launch Firefox to CAMEO Chemicals homepage
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga 45

# Additional wait for page to fully load
sleep 5

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Flammability Range Assessment Task Setup Complete ==="