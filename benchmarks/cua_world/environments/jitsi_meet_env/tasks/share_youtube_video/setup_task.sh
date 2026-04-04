#!/bin/bash
set -e

echo "=== Setting up share_youtube_video task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi is running
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Define meeting room URL
MEETING_URL="${JITSI_BASE_URL:-http://localhost:8080}/fitness-demo-session"

echo "Setting up Firefox..."
# Stop any existing Firefox
stop_firefox
sleep 2

# Start Firefox with the meeting URL
# Using restart_firefox utility which handles nohup and profiles
restart_firefox "$MEETING_URL" 15

# Maximize Firefox
maximize_firefox
sleep 2

# Take screenshot of pre-join screen
take_screenshot /tmp/task_prejoin.png

# Join the meeting (handles clicking the name input and join button)
echo "Joining meeting..."
join_meeting 15

# Move mouse to center to reveal toolbar, then move slightly up to avoid hovering buttons
DISPLAY=:1 xdotool mousemove 960 540
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Verify initial state
if [ -f /tmp/task_initial.png ]; then
    echo "Initial state captured."
else
    echo "WARNING: Failed to capture initial state."
fi

echo "=== Task setup complete ==="
echo "Agent is placed in meeting: $MEETING_URL"