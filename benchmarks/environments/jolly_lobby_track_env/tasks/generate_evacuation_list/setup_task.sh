#!/bin/bash
set -e
echo "=== Setting up Generate Evacuation List Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
record_start_time "generate_evacuation_list"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
# Clean up any previous run artifacts
rm -f /home/ga/Documents/evacuation_list.csv

# Kill any existing Lobby Track instance to ensure fresh start
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
sleep 2

# Launch Lobby Track using the shared utility
# This handles waiting for the window, maximizing it, and dismissing dialogs
launch_lobbytrack

# Double check window state
WID=$(DISPLAY=:1 wmctrl -l | grep -i "lobby\|jolly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Ensuring window $WID is focused..."
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="