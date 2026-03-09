#!/bin/bash
echo "=== Setting up create_stakeholder_matrix task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running EdrawMax instances to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any leftover output files from previous runs
rm -f /home/ga/Documents/stakeholder_map.eddx 2>/dev/null || true
rm -f /home/ga/Documents/stakeholder_map.png 2>/dev/null || true

# Launch EdrawMax fresh (no file argument - opens to home/template screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Notifications)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
take_screenshot /tmp/stakeholder_matrix_start.png
echo "Start state screenshot saved to /tmp/stakeholder_matrix_start.png"

echo "=== create_stakeholder_matrix task setup complete ==="