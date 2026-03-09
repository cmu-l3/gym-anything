#!/bin/bash
echo "=== Setting up create_uml_activity_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous run artifacts
rm -f /home/ga/Documents/order_processing_activity.eddx 2>/dev/null || true
rm -f /home/ga/Documents/order_processing_activity.png 2>/dev/null || true

# Kill any running EdrawMax instances
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax fresh (opens to home/new screen)
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
echo "EdrawMax is open. Agent should create the UML Activity Diagram and save files to ~/Documents/."