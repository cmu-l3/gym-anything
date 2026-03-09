#!/bin/bash
set -euo pipefail

echo "=== Setting up create_meeting_poll task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Verify Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Define room URL
ROOM_URL="${JITSI_BASE_URL:-http://localhost:8080}/TranslatorPlanning"

echo "Navigating to $ROOM_URL"

# Restart Firefox at the pre-join screen for the specific room
restart_firefox "$ROOM_URL" 10

# Ensure window is maximized for consistent VLM analysis
maximize_firefox
focus_firefox

# Clear any previous result artifacts
rm -f /tmp/task_result.json
rm -f /tmp/task_final.png

# Take initial screenshot for evidence of clean state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "You are on the pre-join screen for 'TranslatorPlanning'."
echo "Join the meeting and create the poll as described."