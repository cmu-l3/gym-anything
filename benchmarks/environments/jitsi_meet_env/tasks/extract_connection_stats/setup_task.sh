#!/bin/bash
set -e
echo "=== Setting up extract_connection_stats task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Jitsi is running
if ! wait_for_http "$JITSI_BASE_URL" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Remove any previous output file to ensure clean state
rm -f /home/ga/jitsi_connection_stats.json

# Stop any existing Firefox instances
stop_firefox
sleep 2

# Launch Firefox at the specific meeting room URL
# This places the agent at the pre-join screen
ROOM_NAME="QualityAuditRoom2024"
ROOM_URL="${JITSI_BASE_URL}/${ROOM_NAME}"
echo "Opening Firefox at: $ROOM_URL"

restart_firefox "$ROOM_URL" 10

# Maximize Firefox window for better visibility
maximize_firefox
sleep 2

# Focus Firefox
focus_firefox
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Firefox is open at $ROOM_URL"