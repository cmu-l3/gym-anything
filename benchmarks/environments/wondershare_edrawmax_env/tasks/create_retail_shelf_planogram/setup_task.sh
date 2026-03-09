#!/bin/bash
echo "=== Setting up create_retail_shelf_planogram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create output directory
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# Clean up previous run artifacts
rm -f /home/ga/Diagrams/coffee_planogram.eddx
rm -f /home/ga/Diagrams/coffee_planogram.png

# Kill any existing EdrawMax instances to ensure fresh start
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax (opens to Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banners)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
take_screenshot /tmp/task_initial.png
echo "Start state screenshot saved to /tmp/task_initial.png"

echo "=== Setup complete ==="