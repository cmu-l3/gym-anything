#!/bin/bash
echo "=== Exporting jazz_session_setup results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final state screenshot
echo "Capturing final state..."
take_screenshot /tmp/task_final.png 2>/dev/null || true

# If Ardour is still running, trigger a save to ensure the main file reflects current state
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        echo "Saving current session..."
        focus_window "$WID"
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    echo "Closing Ardour..."
    kill_ardour
fi

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SNAPSHOT_FILE="$SESSION_DIR/Pre_Show_Template.ardour"
MAIN_FILE="$SESSION_DIR/MyProject.ardour"

SNAPSHOT_EXISTS="false"
SNAPSHOT_MTIME=0
if [ -f "$SNAPSHOT_FILE" ]; then
    SNAPSHOT_EXISTS="true"
    SNAPSHOT_MTIME=$(stat -c %Y "$SNAPSHOT_FILE" 2>/dev/null || echo "0")
fi

MAIN_FILE_EXISTS="false"
if [ -f "$MAIN_FILE" ]; then
    MAIN_FILE_EXISTS="true"
fi

# Create JSON result securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "snapshot_exists": $SNAPSHOT_EXISTS,
    "snapshot_mtime": $SNAPSHOT_MTIME,
    "main_file_exists": $MAIN_FILE_EXISTS,
    "snapshot_path": "$SNAPSHOT_FILE",
    "main_path": "$MAIN_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="