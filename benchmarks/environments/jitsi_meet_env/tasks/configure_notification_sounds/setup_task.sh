#!/bin/bash
set -e
echo "=== Setting up configure_notification_sounds task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi Meet is accessible
wait_for_http "http://localhost:8080" 120

# Kill any existing Firefox to start clean
stop_firefox
sleep 2

# Start Firefox at the specific meeting room pre-join page
# The agent starts OUTSIDE the meeting (pre-join screen)
TARGET_URL="http://localhost:8080/InterpreterBooth42"
restart_firefox "$TARGET_URL" 10

# Maximize Firefox window
maximize_firefox
sleep 3

# Dismiss any first-run dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot (evidence of starting state)
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent is positioned at pre-join screen for InterpreterBooth42"