#!/bin/bash
set -e
echo "=== Setting up remove_disruptive_participant task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# 1. Start Agent Firefox (Moderator) first
# The first person to join becomes the moderator in default Jitsi config
echo "Starting Agent Firefox (Moderator)..."
AGENT_URL="http://localhost:8080/GovernanceMeeting#userInfo.displayName=%22Moderator%22"
restart_firefox "$AGENT_URL" 10
maximize_firefox
focus_firefox

# Join the meeting (click 'Join meeting' if stuck on pre-join)
# Pre-join screen usually requires hitting Enter or clicking Join
sleep 5
echo "Attempting to join meeting as Moderator..."
# Click the Join button coordinates (approximate for 1920x1080)
# Or just press Enter since name is usually pre-filled or focus is on name
DISPLAY=:1 xdotool key Return
sleep 5
# Press return again just in case
DISPLAY=:1 xdotool key Return
sleep 5

# 2. Start Disruptive User (Epiphany Browser)
# Epiphany is a separate browser, so no cookie/profile conflict
echo "Starting DisruptiveUser (Epiphany)..."
DISRUPTIVE_URL="http://localhost:8080/GovernanceMeeting#userInfo.displayName=%22DisruptiveUser%22"
DISPLAY=:1 nohup epiphany-browser "$DISRUPTIVE_URL" >/dev/null 2>&1 &
EPIPHANY_PID=$!
echo "$EPIPHANY_PID" > /tmp/disruptive_pid.txt

# Wait for Epiphany to load and join
sleep 15

# Handle Epiphany permissions dialogs (Camera/Mic) if they appear
# Usually Enter or clicking 'Allow' works.
# We'll just try to send a few Enters to the Epiphany window if we can find it
EPIPHANY_WIN=$(DISPLAY=:1 xdotool search --class "epiphany" | tail -1)
if [ -n "$EPIPHANY_WIN" ]; then
    echo "Handling Epiphany dialogs..."
    DISPLAY=:1 xdotool windowactivate "$EPIPHANY_WIN"
    sleep 1
    DISPLAY=:1 xdotool key Return
    sleep 1
    DISPLAY=:1 xdotool key Return
    sleep 1
fi

# 3. Refocus Agent Firefox
echo "Refocusing Agent Firefox..."
focus_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="
echo "TASK: Remove 'DisruptiveUser' from the meeting."