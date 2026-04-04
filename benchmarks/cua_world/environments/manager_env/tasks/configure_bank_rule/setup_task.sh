#!/bin/bash
echo "=== Setting up Configure Bank Rule task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Manager.io is running
wait_for_manager 60

# Open Firefox at the Manager.io Summary page (Dashboard)
# This gives the agent a standard starting point to find "Settings"
echo "Opening Manager.io at Summary page..."
open_manager_at "summary"

# Verify we are on the right page (basic check)
sleep 5
CURRENT_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
echo "Initial window title: $CURRENT_TITLE"

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured."
else
    echo "WARNING: Failed to capture initial screenshot."
fi

echo "=== Task setup complete ==="