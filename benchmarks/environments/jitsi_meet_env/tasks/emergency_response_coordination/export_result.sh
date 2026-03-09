#!/bin/bash
# Export script for Emergency Response Coordination task

echo "=== Exporting Emergency Response Coordination Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/emergency_task_end.png

# Get task start timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# --- Check incident report file ---
REPORT_FILE="/home/ga/Desktop/incident_response_meeting_report.txt"
REPORT_EXISTS=0
REPORT_SIZE=0
REPORT_MTIME=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(wc -c < "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
fi

# --- Check report content for procedure vocabulary ---
HAS_ROOM_URL=0
HAS_LOBBY=0
HAS_PASSWORD=0
HAS_CHAT_MSG=0
HAS_INCIDENT=0

if [ -f "$REPORT_FILE" ]; then
    grep -qiE "Incident.Response.CRIT001|CRIT001|localhost:8080/Incident|Incident.*Response.*CRIT" \
        "$REPORT_FILE" 2>/dev/null && HAS_ROOM_URL=1
    grep -qi "lobby" "$REPORT_FILE" 2>/dev/null && HAS_LOBBY=1
    grep -qiE "password|locked|room lock|lock.*meeting|PIN|access code" "$REPORT_FILE" 2>/dev/null && HAS_PASSWORD=1
    # Check for the specific chat message text or evidence of chat usage
    grep -qiE "INCIDENT RESPONSE ACTIVE|responders acknowledge|attendance|chat.*message|message.*sent|sent.*chat" \
        "$REPORT_FILE" 2>/dev/null && HAS_CHAT_MSG=1
    grep -qiE "incident|response|emergency|CRIT|critical|security.*incident" "$REPORT_FILE" 2>/dev/null && HAS_INCIDENT=1
fi

# --- Check clipboard for meeting URL ---
CLIPBOARD=$(DISPLAY=:1 xclip -selection clipboard -o 2>/dev/null || echo "")
CLIPBOARD_HAS_URL=0
if echo "$CLIPBOARD" | grep -qiE "localhost:8080|Incident.Response|CRIT001|jitsi"; then
    CLIPBOARD_HAS_URL=1
fi

# --- Check if the prosody container shows an active conference room ---
# This is a secondary signal: if prosody knows about the room, it was actually created
ROOM_CREATED_IN_PROSODY=0
PROSODY_CONTAINER=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -i prosody | head -1 || echo "")
if [ -n "$PROSODY_CONTAINER" ]; then
    # Check prosody data directory for room state (muc = multi-user chat rooms)
    ROOM_DATA=$(docker exec "$PROSODY_CONTAINER" bash -c \
        "ls /var/lib/prosody/localhost%2f8080/muc/ 2>/dev/null || ls /var/lib/prosody/ 2>/dev/null" \
        2>/dev/null || echo "")
    if echo "$ROOM_DATA" | grep -qiE "incident.response|CRIT001|crit001"; then
        ROOM_CREATED_IN_PROSODY=1
    fi
fi

# --- Write result JSON ---
cat > /tmp/emergency_response_coordination_result.json << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "has_room_url": $HAS_ROOM_URL,
    "has_lobby": $HAS_LOBBY,
    "has_password": $HAS_PASSWORD,
    "has_chat_msg": $HAS_CHAT_MSG,
    "has_incident": $HAS_INCIDENT,
    "clipboard_has_url": $CLIPBOARD_HAS_URL,
    "room_created_in_prosody": $ROOM_CREATED_IN_PROSODY,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result written to /tmp/emergency_response_coordination_result.json"
echo "=== Export Complete ==="
