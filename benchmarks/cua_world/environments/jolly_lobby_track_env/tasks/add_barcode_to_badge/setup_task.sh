#!/bin/bash
set -e
echo "=== Setting up Add Barcode to Badge Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (critical for checking file modifications)
date +%s > /tmp/task_start_time.txt

# Ensure Lobby Track is running
echo "Launching Lobby Track..."
launch_lobbytrack

# Wait for window to settle
sleep 5

# Maximize the window to ensure the Design button/menu is visible
WID=$(DISPLAY=:1 wmctrl -l | grep -i "lobby\|jolly\|visitor\|track" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="