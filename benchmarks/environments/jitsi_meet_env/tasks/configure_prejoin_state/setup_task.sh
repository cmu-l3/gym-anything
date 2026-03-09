#!/bin/bash
set -e
echo "=== Setting up configure_prejoin_state task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Start Firefox at the base URL (Agent must navigate to specific room)
# We start at the landing page so the agent has to type the full URL or navigate
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# Clear any previous result artifacts
rm -f /tmp/task_result.json

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Navigate to room 'TownHall_2024_Auditor', mute Mic/Cam on Pre-Join screen, set name to 'Silent_Observer', and Join."