#!/bin/bash
echo "=== Setting up create_uml_class_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists and is empty of target files
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/patient_portal_class_diagram.eddx
rm -f /home/ga/Documents/patient_portal_class_diagram.png

# Kill any running EdrawMax instances to start fresh
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax (opens to Home/New screen)
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