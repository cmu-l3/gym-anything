#!/bin/bash
set -euo pipefail

echo "=== Setting up toggle_lobby task ==="

source /workspace/scripts/task_utils.sh

# Verify Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Navigate to the meeting room
ROOM_URL="http://localhost:8080/SecurityMeeting"

restart_firefox "$ROOM_URL" 8
maximize_firefox
focus_firefox

# Join the meeting from the pre-join screen
join_meeting 10

take_screenshot /tmp/task_start.png

echo "Task start screenshot saved to /tmp/task_start.png"
echo "=== toggle_lobby task setup complete ==="
echo "TASK: Enable the Lobby feature for the meeting (Security → Lobby toggle)"
