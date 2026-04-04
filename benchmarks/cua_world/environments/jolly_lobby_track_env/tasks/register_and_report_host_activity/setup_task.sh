#!/bin/bash
set -e
echo "=== Setting up register_and_report_host_activity task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task started at $(date)"

# Ensure clean state for output directory
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/james_wilson_report.* 2>/dev/null

# Kill any existing instances to start fresh
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
sleep 2

# Launch the application
# Using the shared utility to launch and handle window waiting
launch_lobbytrack

# Ensure window is maximized for best VLM visibility
WID=$(DISPLAY=:1 wmctrl -l | grep -i "lobby\|jolly\|track" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    # Focus the window
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="