#!/bin/bash
echo "=== Exporting Renewable Energy Lesson Result ==="

source /workspace/scripts/task_utils.sh

# 1. Record basic info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check Screenshot File
SCREENSHOT_PATH="/home/ga/Documents/renewable_energy_screenshot.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE="0"
SCREENSHOT_CREATED_DURING="false"

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_PATH")
    FILE_TIME=$(stat -c %Y "$SCREENSHOT_PATH")
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING="true"
    fi
fi

# 3. Check Lesson Note File
NOTE_PATH="/home/ga/Documents/renewable_energy_lesson_note.txt"
NOTE_EXISTS="false"
NOTE_SIZE="0"
NOTE_CREATED_DURING="false"

if [ -f "$NOTE_PATH" ]; then
    NOTE_EXISTS="true"
    NOTE_SIZE=$(stat -c %s "$NOTE_PATH")
    FILE_TIME=$(stat -c %Y "$NOTE_PATH")
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        NOTE_CREATED_DURING="true"
    fi
fi

# 4. Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Capture Final Desktop State (Evidence)
take_screenshot /tmp/task_final.png

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size": $SCREENSHOT_SIZE,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING,
    "screenshot_path": "$SCREENSHOT_PATH",
    "note_exists": $NOTE_EXISTS,
    "note_size": $NOTE_SIZE,
    "note_created_during_task": $NOTE_CREATED_DURING,
    "note_path": "$NOTE_PATH",
    "app_running": $APP_RUNNING,
    "final_desktop_screenshot": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json