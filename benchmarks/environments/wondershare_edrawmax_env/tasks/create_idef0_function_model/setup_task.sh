#!/bin/bash
echo "=== Setting up create_idef0_function_model task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f /home/ga/Documents/idef0_order_process.eddx
rm -f /home/ga/Documents/idef0_order_process.png

# Kill any running EdrawMax instances to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax fresh (opens to home/template screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login and File Recovery)
dismiss_edrawmax_dialogs

# Maximize the window for better visibility
maximize_edrawmax

# Take a screenshot to verify start state
take_screenshot /tmp/idef0_start.png
echo "Start state screenshot saved to /tmp/idef0_start.png"

echo "=== Task setup complete ==="
echo "EdrawMax is open. Agent must create IDEF0 diagram and save to ~/Documents/idef0_order_process.eddx"