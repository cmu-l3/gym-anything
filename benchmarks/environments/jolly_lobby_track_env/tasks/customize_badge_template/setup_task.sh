#!/bin/bash
set -e
echo "=== Setting up customize_badge_template task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(date)"

# Create output directory for the user screenshot
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Snapshot existing badge template files (before state) to detect modifications later
# We look in common Wine locations for Jolly/Lobby Track data
echo "Snapshotting badge template files..."
find /home/ga/.wine/drive_c -type f \( -iname "*.btf" -o -iname "*.bdg" -o -iname "*.badge" -o -iname "*.xml" -o -iname "*.btp" \) 2>/dev/null > /tmp/badge_files_before.txt || true

# Launch Lobby Track
ensure_lobbytrack_running

# Wait a moment for UI to stabilize
sleep 5

# Maximize and focus the window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "lobby\|jolly\|visitor\|track" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss any startup dialogs
dismiss_startup_dialogs
sleep 2

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="