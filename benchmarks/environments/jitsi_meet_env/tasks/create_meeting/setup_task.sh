#!/bin/bash
set -euo pipefail

echo "=== Setting up create_meeting task ==="

source /workspace/scripts/task_utils.sh

# Verify Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Start Firefox at Jitsi home page (landing page with meeting name input)
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

sleep 3
take_screenshot /tmp/task_start.png

echo "Task start screenshot saved to /tmp/task_start.png"
echo "=== create_meeting task setup complete ==="
echo "TASK: Enter 'TeamStandup' in the meeting name field and click Start meeting"
