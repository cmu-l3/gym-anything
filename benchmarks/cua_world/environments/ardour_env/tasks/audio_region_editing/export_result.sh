#!/bin/bash
# Export script for audio_region_editing task

echo "=== Exporting task results ==="
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_REGIONS=$(cat /tmp/initial_region_count.txt 2>/dev/null || echo "0")

# Ensure session is saved by sending Ctrl+S to Ardour if running
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    echo "Ardour is active — sending save command..."
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    kill_ardour
fi

sleep 1

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check session file state
SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"
SESSION_MTIME=0
if [ -f "$SESSION_FILE" ]; then
    SESSION_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
fi

# Check exported WAV file
EXPORT_PATH="/home/ga/Audio/bumper_export/kpub_bumper.wav"
EXPORT_EXISTS="false"
EXPORT_SIZE=0
EXPORT_MTIME=0

if [ -f "$EXPORT_PATH" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_PATH" 2>/dev/null || echo "0")
    EXPORT_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
else
    # Fallback search
    FALLBACK=$(find /home/ga/Audio/bumper_export -name "*.wav" -type f 2>/dev/null | head -1)
    if [ -z "$FALLBACK" ]; then
        FALLBACK=$(find /home/ga/Audio/sessions/MyProject/export -name "*.wav" -type f 2>/dev/null | head -1)
    fi
    if [ -n "$FALLBACK" ]; then
        EXPORT_EXISTS="true"
        EXPORT_PATH="$FALLBACK"
        EXPORT_SIZE=$(stat -c %s "$FALLBACK" 2>/dev/null || echo "0")
        EXPORT_MTIME=$(stat -c %Y "$FALLBACK" 2>/dev/null || echo "0")
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_region_count": $INITIAL_REGIONS,
    "session_mtime": $SESSION_MTIME,
    "export_exists": $EXPORT_EXISTS,
    "export_path": "$EXPORT_PATH",
    "export_size_bytes": $EXPORT_SIZE,
    "export_mtime": $EXPORT_MTIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="