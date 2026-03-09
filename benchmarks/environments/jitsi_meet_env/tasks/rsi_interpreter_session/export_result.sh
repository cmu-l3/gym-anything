#!/bin/bash
# Export script for RSI Interpreter Session task

echo "=== Exporting RSI Interpreter Session Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/rsi_task_end.png

# Get task start timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# --- Check report file ---
REPORT_FILE="/home/ga/Desktop/rsi_conference_report.txt"
REPORT_EXISTS=0
REPORT_SIZE=0
REPORT_MTIME=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(wc -c < "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
fi

# --- Check report content for procedure vocabulary ---
# Use grep -q (not grep -c) to avoid the grep-c/OR double-output bug
HAS_URL=0
HAS_LOBBY=0
HAS_MUTED=0
HAS_PASSWORD=0
HAS_INTERPRETER=0

if [ -f "$REPORT_FILE" ]; then
    grep -qiE "localhost:8080|rsi.intlconf|rsi-intlconf|RSI.*2024|8080/RSI" "$REPORT_FILE" 2>/dev/null && HAS_URL=1
    grep -qi "lobby" "$REPORT_FILE" 2>/dev/null && HAS_LOBBY=1
    grep -qiE "muted|everyone.*muted|start.*muted|microphone" "$REPORT_FILE" 2>/dev/null && HAS_MUTED=1
    grep -qiE "password|locked|room lock|lock.*room|Board" "$REPORT_FILE" 2>/dev/null && HAS_PASSWORD=1
    grep -qiE "interpret|RSI|simultaneous|translation|EN.FR|FR.EN" "$REPORT_FILE" 2>/dev/null && HAS_INTERPRETER=1
fi

# --- Check clipboard for meeting URL ---
# Kill Firefox first so any deferred state is flushed (for consistency)
# We do NOT kill it here since the agent may still need it — only kill after screenshot
CLIPBOARD=$(DISPLAY=:1 xclip -selection clipboard -o 2>/dev/null || echo "")
CLIPBOARD_HAS_URL=0
if echo "$CLIPBOARD" | grep -qiE "localhost:8080|RSI.IntlConf|jitsi"; then
    CLIPBOARD_HAS_URL=1
fi

# --- Write result JSON (use integer booleans throughout) ---
cat > /tmp/rsi_interpreter_session_result.json << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "has_url": $HAS_URL,
    "has_lobby": $HAS_LOBBY,
    "has_muted": $HAS_MUTED,
    "has_password": $HAS_PASSWORD,
    "has_interpreter": $HAS_INTERPRETER,
    "clipboard_has_url": $CLIPBOARD_HAS_URL,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result written to /tmp/rsi_interpreter_session_result.json"
echo "=== Export Complete ==="
