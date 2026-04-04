#!/bin/bash
echo "=== Setting up create_statistical_infographic task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create output directory
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# Remove previous output files to ensure fresh creation
rm -f /home/ga/Diagrams/remote_work_infographic.eddx 2>/dev/null || true
rm -f /home/ga/Diagrams/remote_work_infographic.png 2>/dev/null || true

# Kill any running EdrawMax instances
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax (opens to Home/Template screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Notifications)
dismiss_edrawmax_dialogs

# Maximize the window for better agent visibility
maximize_edrawmax

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="