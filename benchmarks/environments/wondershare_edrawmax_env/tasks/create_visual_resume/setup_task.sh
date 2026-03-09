#!/bin/bash
echo "=== Setting up create_visual_resume task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
echo "Cleaning up previous files..."
rm -f /home/ga/Documents/jordan_smith_resume.eddx
rm -f /home/ga/Documents/jordan_smith_resume.pdf
rm -f /tmp/task_result.json

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Kill any running EdrawMax instances to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax fresh (opens to home/template selection screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
# The app is heavy, so we give it ample time
wait_for_edrawmax 90

# Dismiss standard startup dialogs (Account Login, File Recovery, Banner)
dismiss_edrawmax_dialogs

# Maximize the window to ensure all tools are visible to the agent
maximize_edrawmax

# Take a screenshot of the initial state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== create_visual_resume setup complete ==="
echo "EdrawMax is open. Agent is ready to create the resume."