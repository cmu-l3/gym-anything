#!/bin/bash
set -e

echo "=== Setting up digital_logic_circuit task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists for the agent's output
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up previous run artifacts
rm -f /home/ga/Documents/digital_circuit_success.png
rm -f /tmp/task_result.json

# Kill any existing GCompris instances to ensure fresh start
kill_gcompris

# Launch GCompris at the main menu
# We do not navigate to the specific activity; the agent must find it.
echo "Launching GCompris..."
launch_gcompris

# Ensure window is maximized for best visibility
maximize_gcompris

# Take initial screenshot of the starting state (Main Menu)
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="