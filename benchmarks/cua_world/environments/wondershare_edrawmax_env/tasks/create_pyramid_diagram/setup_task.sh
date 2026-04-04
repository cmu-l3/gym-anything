#!/bin/bash
set -e
echo "=== Setting up create_pyramid_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f /home/ga/Documents/defense_in_depth_pyramid.eddx
rm -f /home/ga/Documents/defense_in_depth_pyramid.png
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Kill any existing EdrawMax instance
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax fresh (opens to Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Notifications)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png
echo "Initial state screenshot saved."

echo "=== Task setup complete ==="