#!/bin/bash
set -e
echo "=== Setting up create_hoq_qfd_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous attempts
rm -f /home/ga/Documents/laptop_qfd.eddx
rm -f /home/ga/Documents/laptop_qfd.pdf
rm -f /tmp/task_result.json

# Ensure EdrawMax is NOT running initially (fresh start)
kill_edrawmax

# Launch EdrawMax to the home screen (no file open)
# This forces the agent to navigate the template library to find "House of Quality"
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for application to stabilize
wait_for_edrawmax 90

# Dismiss standard dialogs (Login, Recovery)
dismiss_edrawmax_dialogs

# Maximize window
maximize_edrawmax

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="