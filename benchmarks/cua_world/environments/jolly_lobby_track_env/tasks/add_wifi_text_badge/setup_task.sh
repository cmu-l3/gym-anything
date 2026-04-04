#!/bin/bash
set -e
echo "=== Setting up add_wifi_text_badge task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure Lobby Track is running
echo "Ensuring Lobby Track is running..."
ensure_lobbytrack_running

# Wait for window to be ready
wait_for_lobbytrack_window 30

# Maximize the window (critical for visual recognition)
WID=$(DISPLAY=:1 wmctrl -l | grep -i "lobby\|jolly\|visitor" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing window $WID..."
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    # Focus the window
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot for evidence
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="