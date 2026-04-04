#!/bin/bash
echo "=== Setting up Roman Numerals Study Guide Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing target file to ensure fresh creation
rm -f /home/ga/Documents/roman_guide.txt

# Launch GCompris
# We use the utility function to ensure it starts correctly and we wait for the window
echo "Launching GCompris..."
launch_gcompris

# Maximize the window for the agent
maximize_gcompris

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="