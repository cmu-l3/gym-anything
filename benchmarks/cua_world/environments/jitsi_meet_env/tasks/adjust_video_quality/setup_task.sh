#!/bin/bash
set -e
echo "=== Setting up adjust_video_quality task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi Meet is running
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not running"
    exit 1
fi

# Define the meeting room URL
ROOM_URL="${JITSI_BASE_URL:-http://localhost:8080}/VirtualFitnessQ4"

# Stop any existing Firefox instances
stop_firefox

# Start Firefox with the meeting room URL (pre-join screen)
# NOTE: We do NOT auto-join here. The agent must enter the name and join.
echo "Starting Firefox at $ROOM_URL..."
restart_firefox "$ROOM_URL" 10

# Maximize Firefox window for consistent VLM analysis
maximize_firefox
sleep 2

# Focus Firefox
focus_firefox
sleep 2

# Dismiss any first-run or notification dialogs that might block view
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Firefox is open at: $ROOM_URL"
echo "Agent should see the Jitsi pre-join screen"