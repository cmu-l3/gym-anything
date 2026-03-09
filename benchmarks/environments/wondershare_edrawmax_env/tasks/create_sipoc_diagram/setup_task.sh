#!/bin/bash
echo "=== Setting up create_sipoc_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any running EdrawMax instances to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Clean up any previous attempts
rm -f /home/ga/Documents/help_desk_sipoc.eddx 2>/dev/null || true
rm -f /home/ga/Documents/help_desk_sipoc.png 2>/dev/null || true

# Launch EdrawMax (opens to Home/New screen by default)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banners)
dismiss_edrawmax_dialogs

# Maximize the window for better agent visibility
maximize_edrawmax

# Take a screenshot of the initial state
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured: /tmp/task_initial.png"

echo "=== Task setup complete ==="