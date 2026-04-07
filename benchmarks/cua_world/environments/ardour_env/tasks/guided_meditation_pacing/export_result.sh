#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Guided Meditation Pacing Result ==="

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot showing workspace before closing
take_screenshot /tmp/task_end_screenshot.png

# Trigger a save and graceful close if Ardour is running
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    kill_ardour
fi

sleep 1

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"

# Verify Export Artifacts
EXPORT_DIR="/home/ga/Audio/meditation_export"
EXPORT_EXISTS="false"
EXPORT_CREATED_DURING_TASK="false"
EXPORT_FILE=""

if [ -d "$EXPORT_DIR" ]; then
    # Find the newest wav file
    LATEST_WAV=$(ls -t "$EXPORT_DIR"/*.wav 2>/dev/null | head -1)
    if [ -n "$LATEST_WAV" ] && [ -f "$LATEST_WAV" ]; then
        EXPORT_EXISTS="true"
        EXPORT_FILE="$LATEST_WAV"
        
        # Check if it was created during the task
        WAV_MTIME=$(stat -c %Y "$LATEST_WAV" 2>/dev/null || echo "0")
        if [ "$WAV_MTIME" -ge "$TASK_START" ]; then
            EXPORT_CREATED_DURING_TASK="true"
        fi
    fi
fi

# Build JSON payload
TEMP_JSON=$(mktemp /tmp/guided_meditation_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "export_exists": $EXPORT_EXISTS,
    "export_created_during_task": $EXPORT_CREATED_DURING_TASK,
    "export_file_path": "$EXPORT_FILE",
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END
}
EOF

# Move payload to a predictable location the verifier will check
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="