#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up send_chat_message task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi Meet is reachable
wait_for_http "$JITSI_BASE_URL" 120

# Stop any existing Firefox instances to ensure clean state
stop_firefox

# Start Firefox at the MorningFitness room pre-join screen
# This places the agent at the point where they need to enter name and join
ROOM_URL="${JITSI_BASE_URL}/MorningFitness"
echo "Starting Firefox at $ROOM_URL..."
restart_firefox "$ROOM_URL" 10

# Maximize Firefox window
maximize_firefox
sleep 3

# Take screenshot showing pre-join screen
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Firefox is open at the MorningFitness pre-join screen."
echo "Agent must join meeting as 'Coach Mara' and send the chat message."