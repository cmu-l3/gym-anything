#!/bin/bash
echo "=== Setting up create_flowchart task ==="

source /workspace/scripts/task_utils.sh

# Kill any running EdrawMax instances
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any leftover output files from previous runs
rm -f /home/ga/git_pr_flowchart.eddx 2>/dev/null || true

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
take_screenshot /tmp/create_flowchart_start.png
echo "Start state screenshot saved to /tmp/create_flowchart_start.png"

echo "=== create_flowchart task setup complete ==="
echo "EdrawMax is open. Agent should create a new Flowchart diagram and save as /home/ga/git_pr_flowchart.eddx"
