#!/bin/bash
echo "=== Setting up create_soccer_tactic_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any existing EdrawMax processes to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Clean up previous task artifacts
rm -f /home/ga/Documents/soccer_tactic.eddx 2>/dev/null || true
rm -f /home/ga/Documents/soccer_tactic.jpg 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p /home/ga/Documents

# Launch EdrawMax fresh (opens to Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login and File Recovery)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="