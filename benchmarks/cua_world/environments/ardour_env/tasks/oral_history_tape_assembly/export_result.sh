#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Oral History Tape Assembly Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running
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
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check exported WAV file
EXPORT_DIR="/home/ga/Audio/archival_exports"
EXPORT_EXISTS="false"
EXPORT_SIZE=0
EXPORT_MTIME=0

# Find the largest wav in export dir
LATEST_WAV=$(find "$EXPORT_DIR" -name "*.wav" -type f -printf "%s %p\n" 2>/dev/null | sort -nr | head -1 | awk '{print $2}')
if [ -n "$LATEST_WAV" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$LATEST_WAV" 2>/dev/null || echo "0")
    EXPORT_MTIME=$(stat -c %Y "$LATEST_WAV" 2>/dev/null || echo "0")
fi

# Create result JSON
cat > /tmp/oral_history_result.json << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "task_start_timestamp": $TASK_START,
    "export_exists": $EXPORT_EXISTS,
    "export_size": $EXPORT_SIZE,
    "export_mtime": $EXPORT_MTIME,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/oral_history_result.json"
echo "=== Export Complete ==="