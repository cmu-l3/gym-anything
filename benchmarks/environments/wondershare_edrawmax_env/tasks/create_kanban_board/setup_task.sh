#!/bin/bash
echo "=== Setting up create_kanban_board task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /home/ga/Documents/sprint_board.eddx 2>/dev/null || true
rm -f /home/ga/Documents/sprint_board.png 2>/dev/null || true

# Kill any running EdrawMax instances to ensure a clean start
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax (opens to Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banners)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
take_screenshot /tmp/kanban_start.png
echo "Start state screenshot saved to /tmp/kanban_start.png"

echo "=== create_kanban_board task setup complete ==="
echo "EdrawMax is open. Agent is ready to create the Kanban board."