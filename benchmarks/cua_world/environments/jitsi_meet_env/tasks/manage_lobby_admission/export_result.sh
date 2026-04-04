#!/bin/bash
set -e

echo "=== Exporting manage_lobby_admission results ==="

# 1. Capture final visual state
# We try to ensure we capture the whole desktop to see multiple windows
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check running processes
FIREFOX_RUNNING=$(pgrep -f firefox >/dev/null && echo "true" || echo "false")
EPIPHANY_RUNNING=$(pgrep -f "epiphany" >/dev/null && echo "true" || echo "false")

# 3. Get window titles to verify navigation
WINDOW_TITLES=$(DISPLAY=:1 wmctrl -l | awk '{$1=$2=$3=""; print $0}' | sed 's/^[ \t]*//')

# 4. Attempt to grab Jitsi Prosody logs for server-side verification of Lobby
# We look for "lobby enabled" or room creation events in the last 2 minutes
LOG_SEARCH_START=$(cat /tmp/task_start_time.txt 2>/dev/null || date +%s --date="5 minutes ago")
# Note: Docker logs might not support --since with raw timestamp easily, so we grab tail
PROSODY_LOGS=$(cd /home/ga/jitsi && docker compose logs --tail=200 prosody 2>/dev/null || echo "")

# Check for keywords in logs
LOBBY_ENABLED_LOG=$(echo "$PROSODY_LOGS" | grep -i "lobby" | grep -i "enabled" || echo "")
ROOM_CREATED_LOG=$(echo "$PROSODY_LOGS" | grep -i "HR_Interview_Confidential" || echo "")

# 5. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "firefox_running": $FIREFOX_RUNNING,
    "epiphany_running": $EPIPHANY_RUNNING,
    "window_titles": "$(echo "$WINDOW_TITLES" | tr '\n' '|')",
    "log_lobby_evidence": "$(echo "$LOBBY_ENABLED_LOG" | head -n 1 | sed 's/"/\\"/g')",
    "log_room_evidence": "$(echo "$ROOM_CREATED_LOG" | head -n 1 | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": $(date +%s)
}
EOF

# 6. Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"