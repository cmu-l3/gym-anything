#!/bin/bash
set -e
echo "=== Setting up configure_self_view_visibility task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# We need to start with a fresh state where self view is NOT hidden.
# Since we can't easily manipulate localStorage before opening, we rely on the
# fresh Firefox profile created/cleaned in the environment setup or previous task cleanup.
# The default for 'disableSelfView' is false/undefined.

# Navigate to the meeting room URL (Pre-join screen)
ROOM_URL="http://localhost:8080/WebinarPrep"

echo "Starting Firefox at $ROOM_URL..."
restart_firefox "$ROOM_URL" 10
maximize_firefox
focus_firefox

# Wait a moment for UI to settle
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "TASK: Join 'WebinarPrep' and hide self view (keep camera ON)"