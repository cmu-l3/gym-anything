#!/bin/bash
set -e
echo "=== Setting up Family Tree Relationship task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create Documents directory if it doesn't exist
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous result file to ensure clean state
rm -f /home/ga/Documents/family_tree_solved.png

# Kill any existing GCompris instances to start fresh
kill_gcompris

# Launch GCompris at the main menu
# The agent must perform the navigation as part of the task
echo "Launching GCompris..."
launch_gcompris
sleep 5

# Ensure window is maximized for best VLM visibility
maximize_gcompris

# Take screenshot of initial state (Main Menu)
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "GCompris launched at main menu."
echo "Agent needs to: Find 'Family' activity -> Solve -> Screenshot to ~/Documents/family_tree_solved.png"