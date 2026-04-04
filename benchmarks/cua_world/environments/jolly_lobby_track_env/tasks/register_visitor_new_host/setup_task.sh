#!/bin/bash
echo "=== Setting up register_visitor_new_host task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp check)
record_start_time "register_visitor_new_host"

# Kill any existing Lobby Track instance to ensure clean state
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 3

# Launch Lobby Track
launch_lobbytrack

# Ensure window is maximized for better visibility
WID=$(wait_for_lobbytrack_window 30)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== register_visitor_new_host task setup complete ==="
echo "Task: Register visitor Jordan Lee to see NEW host Amanda Sterling"