#!/bin/bash
set -e
echo "=== Setting up embed_meeting_iframe task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Clean up any previous attempt files
rm -f /home/ga/Documents/meeting_portal.html
rm -f /tmp/task_result.json

# Start Firefox at a neutral page (not Jitsi, so we can verify they load the file)
echo "Starting Firefox..."
restart_firefox "about:blank" 10
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="