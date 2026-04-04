#!/bin/bash
set -e
echo "=== Setting up create_gantt_chart task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f /home/ga/migration_gantt.eddx 2>/dev/null || true
rm -f /home/ga/migration_gantt.png 2>/dev/null || true

# Kill any existing EdrawMax instances to ensure fresh state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax fresh (no file argument = opens to home screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load (can take a while)
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banner)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take initial state screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== create_gantt_chart task setup complete ==="
echo "EdrawMax is open. Agent needs to create a Gantt chart and save/export it."