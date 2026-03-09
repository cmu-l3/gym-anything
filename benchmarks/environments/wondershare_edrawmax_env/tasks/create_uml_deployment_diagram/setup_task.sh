#!/bin/bash
echo "=== Setting up create_uml_deployment_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running EdrawMax instances to start fresh
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Ensure output directory exists
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# Remove any leftover output files from previous runs
rm -f /home/ga/Diagrams/wms_deployment_diagram.eddx 2>/dev/null || true
rm -f /home/ga/Diagrams/wms_deployment_diagram.png 2>/dev/null || true

# Launch EdrawMax fresh (no file argument - opens to home/new screen)
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