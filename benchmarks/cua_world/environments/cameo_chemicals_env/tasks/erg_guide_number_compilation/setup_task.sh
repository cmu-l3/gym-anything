#!/bin/bash
set -e
echo "=== Setting up ERG Guide Number Compilation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
rm -f /home/ga/Desktop/erg_guide_numbers.txt 2>/dev/null || true

# Kill any existing Firefox
kill_firefox ga

# Wait a moment
sleep 2

# Launch Firefox to CAMEO Chemicals homepage
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga 45

# Wait for page to fully load
sleep 5

# Maximize and focus Firefox
maximize_firefox

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== ERG Guide Number Compilation Task Setup Complete ==="
echo "Firefox is open to CAMEO Chemicals homepage."