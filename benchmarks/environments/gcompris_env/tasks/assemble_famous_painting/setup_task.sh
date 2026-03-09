#!/bin/bash
set -e
echo "=== Setting up assemble_famous_painting task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists and is clean
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/painting_solved.png
rm -f /home/ga/Documents/painting_info.txt
chown -R ga:ga /home/ga/Documents

# Kill any existing instances to ensure fresh start
kill_gcompris

# Launch GCompris at main menu
# We do not navigate to the specific activity; the agent must find "Puzzles" -> "Paintings"
echo "Launching GCompris..."
launch_gcompris

# Ensure window is maximized for best VLM visibility
maximize_gcompris

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="