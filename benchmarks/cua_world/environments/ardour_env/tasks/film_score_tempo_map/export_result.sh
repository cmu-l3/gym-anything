#!/bin/bash
echo "=== Exporting film_score_tempo_map task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE closing anything
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Save and close if Ardour is running (Trigger Ctrl+S just in case agent forgot)
ARDOUR_RUNNING="false"
if pgrep -f ardour > /dev/null 2>&1; then
    ARDOUR_RUNNING="true"
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 0.5
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 2
    fi
    pkill -f ardour 2>/dev/null || true
    sleep 2
fi

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"
SESSION_EXISTS="false"
SESSION_MTIME="0"
MODIFIED_DURING_TASK="false"

# Check the session file
if [ -f "$SESSION_FILE" ]; then
    SESSION_EXISTS="true"
    SESSION_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
    
    # Copy the session file to /tmp for safe export reading
    cp "$SESSION_FILE" /tmp/session_export.ardour 2>/dev/null || true
    chmod 666 /tmp/session_export.ardour 2>/dev/null || true
    
    if [ "$SESSION_MTIME" -ge "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    fi
fi

# Grab initial metrics
INITIAL_TEMPO_COUNT=$(cat /tmp/initial_tempo_count.txt 2>/dev/null || echo "0")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "session_exists": $SESSION_EXISTS,
    "session_mtime": $SESSION_MTIME,
    "modified_during_task": $MODIFIED_DURING_TASK,
    "ardour_was_running": $ARDOUR_RUNNING,
    "initial_tempo_count": $INITIAL_TEMPO_COUNT,
    "exported_session_xml": "/tmp/session_export.ardour"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "Session XML copied to /tmp/session_export.ardour"
echo "=== Export complete ==="