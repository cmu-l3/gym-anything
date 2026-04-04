#!/bin/bash
set -euo pipefail

echo "=== Setting up set_meeting_password task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi is running and reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Room details
ROOM_NAME="premium-yoga-class"
ROOM_URL="${JITSI_BASE_URL}/${ROOM_NAME}"

echo "Target Room: $ROOM_URL"

# Stop any existing Firefox
stop_firefox

# Start Firefox directly at the room URL
restart_firefox "$ROOM_URL" 12

# Maximize Firefox
maximize_firefox
focus_firefox
sleep 2

# Join the meeting from the pre-join screen
# This function clicks the "Join meeting" button
join_meeting 15

# Ensure we are in the meeting by moving mouse to center (wakes up UI)
DISPLAY=:1 xdotool mousemove 960 540
sleep 2

# Take setup confirmation screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Agent is in room '$ROOM_NAME'. Task: Set password to 'FlowState24'."