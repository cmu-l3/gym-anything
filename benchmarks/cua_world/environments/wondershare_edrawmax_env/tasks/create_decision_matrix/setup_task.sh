#!/bin/bash
echo "=== Setting up create_decision_matrix task ==="

source /workspace/scripts/task_utils.sh

# Kill any running EdrawMax instances
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any leftover output files from previous runs
rm -f /home/ga/Documents/db_evaluation_matrix.eddx 2>/dev/null || true
rm -f /home/ga/Documents/db_evaluation_matrix.pdf 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Launch EdrawMax fresh (no file argument - opens to home/new screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login and File Recovery)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
take_screenshot /tmp/task_initial.png
echo "Start state screenshot saved to /tmp/task_initial.png"

echo "=== create_decision_matrix task setup complete ==="