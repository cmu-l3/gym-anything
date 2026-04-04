#!/bin/bash
echo "=== Setting up Configure Auto-Signout Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 1. Kill existing instances to ensure fresh start
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
sleep 2

# 2. Ensure we have a clean state for config files if possible
# (We don't delete them to avoid breaking the app, but we verify they exist)
echo "Checking configuration locations..."
find "/home/ga/.wine/drive_c/ProgramData/Jolly Technologies" -maxdepth 3 2>/dev/null || true

# 3. Launch Lobby Track
launch_lobbytrack

# 4. Wait for window and maximize
WID=$(wait_for_lobbytrack_window 60)
if [ -n "$WID" ]; then
    echo "Maximizing window $WID..."
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Enable Auto Sign Out and set to 8 hours (480 minutes)."