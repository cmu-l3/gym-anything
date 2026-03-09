#!/bin/bash
echo "=== Setting up create_server_rack_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous run artifacts
rm -f /home/ga/Documents/rack_elevation.eddx 2>/dev/null || true
rm -f /home/ga/Documents/rack_elevation.png 2>/dev/null || true

# Kill any existing EdrawMax instances to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax (opens to Home/New screen by default)
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