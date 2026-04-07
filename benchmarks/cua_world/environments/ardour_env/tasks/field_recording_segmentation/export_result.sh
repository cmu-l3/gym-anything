#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting field_recording_segmentation Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Save and close Ardour
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

# Check log file
LOG_FILE="/home/ga/Audio/field_notes/species_log.txt"
LOG_EXISTS="false"
LOG_CONTENT=""
if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    # Read up to 1000 bytes to avoid huge JSON if agent did something weird
    LOG_CONTENT=$(head -c 1000 "$LOG_FILE" | sed 's/"/\\"/g' | tr '\n' ' ' | tr '\r' ' ')
fi

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

cat > /tmp/field_recording_segmentation_result.json << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "task_start_timestamp": $TASK_START,
    "export_timestamp": "$(date -Iseconds)",
    "log_exists": $LOG_EXISTS,
    "log_content": "$LOG_CONTENT"
}
EOF

echo "Result saved to /tmp/field_recording_segmentation_result.json"
echo "=== Export Complete ==="