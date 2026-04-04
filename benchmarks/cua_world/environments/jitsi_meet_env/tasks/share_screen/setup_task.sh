#!/bin/bash
set -euo pipefail

echo "=== Setting up share_screen task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f /tmp/screen_share_active.png 2>/dev/null || true
rm -f /tmp/screen_share_stopped.png 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Verify Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Navigate to the meeting room URL
ROOM_URL="http://localhost:8080/QuarterlyPlanningSync"
echo "Navigating to $ROOM_URL"

# Restart Firefox and load the room
restart_firefox "$ROOM_URL" 10
maximize_firefox
focus_firefox

# Capture initial state screenshot
sleep 2
take_screenshot /tmp/task_start.png

echo "=== share_screen task setup complete ==="
echo "TASK: Join 'QuarterlyPlanningSync', share screen, screenshot active state, stop sharing, screenshot stopped state."