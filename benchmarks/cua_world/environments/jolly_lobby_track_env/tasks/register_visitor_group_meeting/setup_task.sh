#!/bin/bash
set -e
echo "=== Setting up register_visitor_group_meeting task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# cleanup previous artifacts
rm -f /tmp/visitor_log_screenshot.png
rm -f /tmp/task_result.json

# Ensure Lobby Track is running
ensure_lobbytrack_running

# Wait for window to settle and maximize
# This ensures the agent sees the main screen immediately
sleep 5
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "lobby\|jolly\|visitor\|track" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing Lobby Track window ($WID)..."
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss any potential startup dialogs/popups
dismiss_startup_dialogs

# Take initial state screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="