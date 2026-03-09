#!/bin/bash
set -e
echo "=== Setting up configure_profile_email task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Room URL
ROOM_NAME="ManagementSync"
ROOM_URL="${JITSI_BASE_URL}/${ROOM_NAME}"

# Ensure Firefox is clean (kill existing)
stop_firefox

# Clear specific profile data to ensure no previous email is stored
# We don't want to delete the whole profile if possible, just ensure clean slate for this task
# But setup_jitsi.sh creates a fresh profile usually. We will just trust the restart.

# Start Firefox and join the meeting
echo "Starting Firefox and joining ${ROOM_NAME}..."
restart_firefox "$ROOM_URL" 10
maximize_firefox
focus_firefox

# Join the meeting (click through pre-join screen)
# The join_meeting function in task_utils handles the name input/click
join_meeting 10

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="
echo "You are in the meeting '${ROOM_NAME}'."
echo "Please configure your profile email to: alex.manager@corp.global"