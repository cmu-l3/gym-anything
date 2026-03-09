#!/bin/bash
echo "=== Setting up create_aws_cloud_architecture task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# Clean up any previous run artifacts
rm -f /home/ga/Diagrams/aws_architecture.eddx
rm -f /home/ga/Diagrams/aws_architecture.png

# Kill any existing EdrawMax processes
kill_edrawmax

# Launch EdrawMax (starts at Home/Template selection screen)
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
echo "Initial state captured to /tmp/task_initial.png"

echo "=== Task setup complete ==="