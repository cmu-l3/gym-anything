#!/bin/bash
echo "=== Exporting Studio Cue Mix Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot showing end state
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Trigger a save in Ardour if it's running, to ensure agent's last actions are captured
WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    echo "Forcing session save..."
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
    sleep 2
fi

# Cleanly close Ardour to flush any pending disk writes
kill_ardour

# Gather timestamps for anti-gaming verification
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"
SESSION_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")

# Write minimal JSON export. The verifier will directly copy and parse the XML session file.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "session_mtime": $SESSION_MTIME,
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false")
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="