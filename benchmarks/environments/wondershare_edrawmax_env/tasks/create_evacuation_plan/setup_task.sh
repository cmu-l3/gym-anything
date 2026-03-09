#!/bin/bash
echo "=== Setting up create_evacuation_plan task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create Documents directory if it doesn't exist
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous attempts to ensure a clean state
rm -f /home/ga/Documents/evacuation_plan.eddx 2>/dev/null || true
rm -f /home/ga/Documents/evacuation_plan.png 2>/dev/null || true

# Kill any running EdrawMax instances to start fresh
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax to the Home/New screen
# We do NOT open a template; the agent must navigate the libraries themselves
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banner)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
take_screenshot /tmp/task_initial.png
echo "Start state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="