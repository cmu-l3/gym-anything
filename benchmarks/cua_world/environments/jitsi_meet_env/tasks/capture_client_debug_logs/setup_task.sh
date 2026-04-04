#!/bin/bash
set -e
echo "=== Setting up capture_client_debug_logs task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Clean up any previous log files
rm -f /home/ga/Documents/firefox_console.log
rm -f /tmp/firefox_console.log
mkdir -p /home/ga/Documents

# Ensure Firefox is running initially (so the agent has to close it)
# This sets the stage for "Close any running Firefox instances"
restart_firefox "http://localhost:8080" 5
maximize_firefox
focus_firefox

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="