#!/bin/bash
set -e
echo "=== Setting up create_value_stream_map task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# Clean up previous run artifacts
rm -f /home/ga/Diagrams/deployment_vsm.eddx 2>/dev/null || true

# Kill any existing EdrawMax instances to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax fresh (no file argument - opens to home/template screen)
# This forces the agent to find the Value Stream Mapping category/template themselves
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

# Verify setup success
if [ -f /tmp/task_initial.png ]; then
    echo "Setup complete: EdrawMax running and initial screenshot captured."
else
    echo "WARNING: Setup finished but screenshot missing."
fi