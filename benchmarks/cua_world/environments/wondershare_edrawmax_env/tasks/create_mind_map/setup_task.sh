#!/bin/bash
echo "=== Setting up create_mind_map task ==="

source /workspace/scripts/task_utils.sh

# Kill any running EdrawMax instances
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any leftover output files from previous runs
rm -f /home/ga/linux_kernel_mindmap.eddx 2>/dev/null || true

# Launch EdrawMax fresh (no file argument - opens to home/editor screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login and File Recovery)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
take_screenshot /tmp/create_mind_map_start.png
echo "Start state screenshot saved to /tmp/create_mind_map_start.png"

echo "=== create_mind_map task setup complete ==="
echo "EdrawMax is open. Agent should create a new Mind Map diagram and save as /home/ga/linux_kernel_mindmap.eddx"
