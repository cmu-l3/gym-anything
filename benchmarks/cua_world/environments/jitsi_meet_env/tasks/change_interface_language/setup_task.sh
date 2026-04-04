#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up change_interface_language task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi is running
if ! wait_for_http "$JITSI_BASE_URL" 120; then
    echo "ERROR: Jitsi Meet not reachable"
    exit 1
fi

# Stop any existing Firefox to ensure clean profile loading
stop_firefox
sleep 2

# Clear any stale language settings from previous runs
# We remove the specific localStorage directory for localhost:8080
echo "Clearing previous language preferences..."
find /home/ga/snap/firefox/ /home/ga/.mozilla/firefox/ \
    -path "*/http+++localhost+8080/ls" -type d \
    -exec rm -rf {} + 2>/dev/null || true

# Also try to clear via cleaning the specific sqlite file if it exists in standard profile
rm -f /home/ga/.mozilla/firefox/jitsi.profile/storage/default/http+++localhost+8080/ls/data.sqlite 2>/dev/null || true

# Start Firefox with the interpreting session room
# This URL will land on the pre-join screen or join directly depending on config
TARGET_URL="${JITSI_BASE_URL}/InterpretingSession2024"
restart_firefox "$TARGET_URL" 12

# Maximize Firefox
maximize_firefox
sleep 2

# Join the meeting from the pre-join screen (enter name and click join)
join_meeting 8

# Move mouse to center to ensure toolbar is visible
DISPLAY=:1 xdotool mousemove 960 540
sleep 1

# Take screenshot of initial state (English UI)
take_screenshot /tmp/task_initial.png

# Verify initial screenshot
if [ -f /tmp/task_initial.png ]; then
    echo "Initial state captured."
else
    echo "WARNING: Failed to capture initial state."
fi

echo "=== Task setup complete ==="
echo "Meeting joined at $TARGET_URL"