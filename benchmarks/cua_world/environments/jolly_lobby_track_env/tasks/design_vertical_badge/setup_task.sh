#!/bin/bash
set -e
echo "=== Setting up Design Vertical Badge Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
record_start_time "design_vertical_badge"

# Clean up any previous attempts (anti-gaming)
echo "Cleaning up previous template files..."
find /home/ga/.wine/drive_c -name "Vertical_Standard*" -delete 2>/dev/null || true

# Ensure Lobby Track is running
ensure_lobbytrack_running

# Wait for window to be ready
wait_for_lobbytrack_window 30

# Maximize the window ensures buttons are visible
WID=$(DISPLAY=:1 wmctrl -l | grep -i "lobby\|jolly\|visitor\|track" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Window maximized: $WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="