#!/bin/bash
set -e
echo "=== Setting up create_wireframe_mockup task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# Clean up any previous run artifacts
rm -f /home/ga/Diagrams/patient_portal_wireframe.eddx
rm -f /home/ga/Diagrams/patient_portal_wireframe.png
rm -f /tmp/task_result.json

# Kill any existing EdrawMax instances to ensure clean start
kill_edrawmax

# Launch EdrawMax (opens to Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, etc.)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="