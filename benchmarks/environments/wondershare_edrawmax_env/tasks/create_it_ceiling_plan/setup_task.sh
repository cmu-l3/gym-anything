#!/bin/bash
echo "=== Setting up Reflected Ceiling Plan task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state: Kill any running EdrawMax instances
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any previous task artifacts
rm -f /home/ga/Documents/conference_room_rcp.eddx 2>/dev/null || true
rm -f /home/ga/Documents/conference_room_rcp.png 2>/dev/null || true

# Launch EdrawMax fresh (opens to home/template selection screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banners)
dismiss_edrawmax_dialogs

# Maximize the window for better agent visibility
maximize_edrawmax

# Take a screenshot to verify initial state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="
echo "EdrawMax is open on the Home screen."