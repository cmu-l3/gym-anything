#!/bin/bash
set -e

echo "=== Setting up Enforce Follow Me View task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Generate a unique room name to ensure fresh state (agent becomes moderator)
TIMESTAMP=$(date +%s)
ROOM_NAME="TrainingSession_${TIMESTAMP}"
echo "$ROOM_NAME" > /tmp/room_name.txt

ROOM_URL="${JITSI_BASE_URL:-http://localhost:8080}/${ROOM_NAME}"

echo "Target Room: $ROOM_URL"

# Restart Firefox and navigate to the room URL (Pre-join screen)
restart_firefox "$ROOM_URL" 10
maximize_firefox
focus_firefox

# We stay at the pre-join screen. The agent must click "Join".
# This is part of the task flow ensuring they enter the room.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="