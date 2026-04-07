#!/bin/bash
echo "=== Exporting multi_language_cinematic_conforming result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if Ardour is running, save session gracefully
APP_RUNNING="false"
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    APP_RUNNING="true"
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    kill_ardour
fi

sleep 1

# Check exports
EXPORTS_DIR="/home/ga/Audio/exports"
ES_FILE="$EXPORTS_DIR/cinematic_es.wav"
FR_FILE="$EXPORTS_DIR/cinematic_fr.wav"

check_file() {
    local file_path=$1
    if [ -f "$file_path" ]; then
        local size=$(stat -c%s "$file_path" 2>/dev/null || echo "0")
        local mtime=$(stat -c%Y "$file_path" 2>/dev/null || echo "0")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size_bytes\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size_bytes\": 0, \"created_during_task\": false}"
    fi
}

ES_JSON=$(check_file "$ES_FILE")
FR_JSON=$(check_file "$FR_FILE")

# Dump session XML path
SESSION_XML="/home/ga/Audio/sessions/MyProject/MyProject.ardour"
SESSION_EXISTS="false"
if [ -f "$SESSION_XML" ]; then
    SESSION_EXISTS="true"
fi

# Write results
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "session_exists": $SESSION_EXISTS,
    "exports": {
        "es": $ES_JSON,
        "fr": $FR_JSON
    }
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="