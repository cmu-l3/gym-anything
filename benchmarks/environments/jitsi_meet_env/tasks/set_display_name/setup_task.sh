#!/bin/bash
set -euo pipefail

echo "=== Setting up set_display_name task ==="

source /workspace/scripts/task_utils.sh

# Verify Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Navigate to the specific meeting room URL
# This ensures the agent lands at the pre-join/prejoin screen for the room
ROOM_URL="http://localhost:8080/ProductReview"

restart_firefox "$ROOM_URL" 10
maximize_firefox
focus_firefox

sleep 3
take_screenshot /tmp/task_start.png

echo "Task start screenshot saved to /tmp/task_start.png"
echo "=== set_display_name task setup complete ==="
echo "TASK: Set display name to 'Alex Johnson' and join the meeting"
