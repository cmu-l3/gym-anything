#!/bin/bash
echo "=== Setting up create_bpmn_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any previous attempts
rm -f /home/ga/Documents/bpmn_order_fulfillment.eddx
rm -f /home/ga/Documents/bpmn_order_fulfillment.png

# Kill any running EdrawMax instances
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax (starts at Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax window to appear and initialize
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banner)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="