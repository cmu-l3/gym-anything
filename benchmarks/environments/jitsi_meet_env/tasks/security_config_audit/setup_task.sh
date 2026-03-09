#!/bin/bash
set -euo pipefail

echo "=== Setting up Security Config Audit task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f /home/ga/security_audit.txt
rm -f /home/ga/security_options_screenshot.png
rm -f /tmp/task_result.json

# Verify Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Define meeting URL
ROOM_URL="http://localhost:8080/ConfidentialBoardRoom"

# Start Firefox at the pre-join screen for the specific room
echo "Starting Firefox at $ROOM_URL..."
restart_firefox "$ROOM_URL" 10
maximize_firefox
focus_firefox

# Allow UI to stabilize
sleep 2

# Take initial screenshot of the pre-join screen
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task ready: Agent is at pre-join screen for ConfidentialBoardRoom"