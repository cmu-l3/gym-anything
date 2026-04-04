#!/bin/bash
echo "=== Setting up Configure Kiosk Mode task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp check)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Record initial modification time of Wine registry (where settings are often stored)
REGISTRY_FILE="/home/ga/.wine/user.reg"
if [ -f "$REGISTRY_FILE" ]; then
    stat -c %Y "$REGISTRY_FILE" > /tmp/initial_reg_mtime.txt
else
    echo "0" > /tmp/initial_reg_mtime.txt
fi

# Ensure Lobby Track is running and focused
# We use the shared utility to launch/focus
ensure_lobbytrack_running

# Wait for window to settle
sleep 5
WID=$(DISPLAY=:1 wmctrl -l | grep -i "lobby\|jolly\|visitor\|track" | head -1 | awk '{print $1}')

if [ -n "$WID" ]; then
    echo "Maximizing Lobby Track window..."
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
fi

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Configure Kiosk Mode"
echo "1. Enable Kiosk/Self-Service Mode"
echo "2. Set Welcome Text: 'Welcome to Summit Coworks'"
echo "3. Set Subtitle: 'Please sign in using the form below'"