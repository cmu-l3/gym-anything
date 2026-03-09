#!/bin/bash
set -e
echo "=== Setting up Cartesian Coordinates Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure GCompris config directory exists and has correct permissions
mkdir -p /home/ga/.config/gcompris-qt
mkdir -p /home/ga/.local/share/GCompris
chown -R ga:ga /home/ga/.config
chown -R ga:ga /home/ga/.local

# Kill any existing instances to ensure a fresh start
kill_gcompris

# Launch GCompris at the main menu
# The agent is expected to navigate from here
echo "Launching GCompris..."
launch_gcompris

# Maximize the window to ensure VLM can see icons clearly
maximize_gcompris

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "GCompris is running at the main menu."
echo "Agent must navigate: Math -> Geometry -> Cartesian Coordinates"