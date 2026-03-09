#!/bin/bash
echo "=== Setting up create_timeline_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running EdrawMax instances to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any previous task artifacts
rm -f /home/ga/Documents/migration_timeline.eddx 2>/dev/null || true
rm -f /home/ga/Documents/migration_timeline.png 2>/dev/null || true

# Launch EdrawMax fresh (opens to home/template gallery)
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

echo "=== create_timeline_diagram task setup complete ==="