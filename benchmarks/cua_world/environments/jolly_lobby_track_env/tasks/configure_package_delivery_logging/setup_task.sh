#!/bin/bash
set -e
echo "=== Setting up Configure Package Delivery Logging task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Lobby Track is running
ensure_lobbytrack_running

# Wait for window to be fully ready
wait_for_lobbytrack_window 60

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "lobby\|jolly\|visitor\|track" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="