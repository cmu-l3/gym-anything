#!/bin/bash
set -e
echo "=== Setting up collect_webrtc_logs task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f /home/ga/jitsi_debug.log
rm -f /home/ga/console_evidence.png
rm -f /tmp/task_result.json

# Ensure Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Start Firefox at the home page (Agent must navigate to the specific room)
echo "Starting Firefox..."
restart_firefox "${JITSI_BASE_URL:-http://localhost:8080}" 8

# Maximize to ensure ample space for DevTools
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Starting state: Firefox open on Jitsi Meet home page."