#!/bin/bash
echo "=== Setting up create_traffic_accident_sketch task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents

# Clean up any previous attempts
rm -f /home/ga/Documents/accident_sketch_2024_891.eddx
rm -f /home/ga/Documents/accident_sketch_2024_891.pdf

# Kill any running EdrawMax instances to ensure clean start
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax (no specific file, just the app)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login and File Recovery)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
take_screenshot /tmp/task_initial.png
echo "Start state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="