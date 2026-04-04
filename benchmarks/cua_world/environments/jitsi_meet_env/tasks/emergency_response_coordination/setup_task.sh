#!/bin/bash
# Setup script for Emergency Response Coordination task
# Occupation: General and Operations Managers / IT Incident Response
# Difficulty: Very Hard

echo "=== Setting up Emergency Response Coordination Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi
if ! type wait_for_http &>/dev/null; then
    wait_for_http() {
        local url="$1" timeout="${2:-120}" elapsed=0
        while [ $elapsed -lt $timeout ]; do
            curl -sfk "$url" >/dev/null 2>&1 && return 0
            sleep 3; elapsed=$((elapsed + 3))
        done
        return 1
    }
fi
if ! type restart_firefox &>/dev/null; then
    restart_firefox() {
        pkill -f firefox 2>/dev/null || true; sleep 2
        pkill -9 -f firefox 2>/dev/null || true; sleep 1
        rm -f /home/ga/.mozilla/firefox/jitsi.profile/lock \
              /home/ga/.mozilla/firefox/jitsi.profile/.parentlock \
              /home/ga/snap/firefox/common/.mozilla/firefox/jitsi.profile/lock \
              /home/ga/snap/firefox/common/.mozilla/firefox/jitsi.profile/.parentlock 2>/dev/null || true
        DISPLAY=:1 nohup firefox "${1:-http://localhost:8080}" >/tmp/firefox_task.log 2>&1 &
        sleep "${2:-8}"
    }
fi

# Verify Jitsi Meet is reachable
echo "Checking Jitsi Meet availability..."
if ! wait_for_http "http://localhost:8080" 120; then
    echo "ERROR: Jitsi Meet not reachable"
    exit 1
fi
echo "Jitsi Meet is available."

# Remove any pre-existing incident report for clean starting state
rm -f /home/ga/Desktop/incident_response_meeting_report.txt 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Clear clipboard to establish baseline
echo "" | DISPLAY=:1 xclip -selection clipboard 2>/dev/null || true

# Open Jitsi home page — agent must create the room from scratch
restart_firefox "http://localhost:8080" 10

# Maximize Firefox window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Task: Deploy emergency response meeting Incident-Response-CRIT001."
echo "Required: lobby, password, muted policy, chat message, invite copy, incident report."
echo "Report must be at: /home/ga/Desktop/incident_response_meeting_report.txt"
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"
