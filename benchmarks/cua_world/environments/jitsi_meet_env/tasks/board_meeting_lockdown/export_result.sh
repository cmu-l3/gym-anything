#!/bin/bash
# Export script for Board Meeting Lockdown task

echo "=== Exporting Board Meeting Lockdown Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/board_task_end.png

# Get task start timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# --- Check summary file ---
SUMMARY_FILE="/home/ga/Desktop/board_security_summary.txt"
REPORT_EXISTS=0
REPORT_SIZE=0
REPORT_MTIME=0

if [ -f "$SUMMARY_FILE" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(wc -c < "$SUMMARY_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$SUMMARY_FILE" 2>/dev/null || echo "0")
fi

# --- Check summary content for procedure vocabulary ---
HAS_ROOM_NAME=0
HAS_LOBBY=0
HAS_PASSWORD=0

if [ -f "$SUMMARY_FILE" ]; then
    grep -qiE "Q4ExecutiveBoard|Q4.*Board|localhost:8080|executive.*board" "$SUMMARY_FILE" 2>/dev/null && HAS_ROOM_NAME=1
    grep -qi "lobby" "$SUMMARY_FILE" 2>/dev/null && HAS_LOBBY=1
    grep -qiE "password|Board2024|locked|room lock|lock.*room|PIN" "$SUMMARY_FILE" 2>/dev/null && HAS_PASSWORD=1
fi

# --- Check clipboard for meeting URL ---
CLIPBOARD=$(DISPLAY=:1 xclip -selection clipboard -o 2>/dev/null || echo "")
CLIPBOARD_HAS_URL=0
if echo "$CLIPBOARD" | grep -qiE "localhost:8080|Q4ExecutiveBoard|Q4.*Board|jitsi"; then
    CLIPBOARD_HAS_URL=1
fi

# --- Write result JSON ---
cat > /tmp/board_meeting_lockdown_result.json << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "has_room_name": $HAS_ROOM_NAME,
    "has_lobby": $HAS_LOBBY,
    "has_password": $HAS_PASSWORD,
    "clipboard_has_url": $CLIPBOARD_HAS_URL,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result written to /tmp/board_meeting_lockdown_result.json"
echo "=== Export Complete ==="
