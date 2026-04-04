#!/bin/bash
set -euo pipefail

echo "=== Setting up share_invite_link task ==="

source /workspace/scripts/task_utils.sh

# Verify Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Navigate to the meeting room
ROOM_URL="http://localhost:8080/DesignReview"

restart_firefox "$ROOM_URL" 8
maximize_firefox
focus_firefox

# Join the meeting from the pre-join screen
join_meeting 10

take_screenshot /tmp/task_start.png

echo "Task start screenshot saved to /tmp/task_start.png"
echo "=== share_invite_link task setup complete ==="
echo "TASK: Use the invite feature to copy the meeting invitation link"
