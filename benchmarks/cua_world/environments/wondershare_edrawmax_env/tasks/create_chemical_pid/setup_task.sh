#!/bin/bash
set -e
echo "=== Setting up create_chemical_pid task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create output directory
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# Cleanup previous run artifacts
rm -f /home/ga/Diagrams/pid_unit100.eddx
rm -f /home/ga/Diagrams/pid_unit100.pdf

# Kill any existing EdrawMax instances to ensure clean state
kill_edrawmax

# Launch EdrawMax to the Home/New screen
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Notifications)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="