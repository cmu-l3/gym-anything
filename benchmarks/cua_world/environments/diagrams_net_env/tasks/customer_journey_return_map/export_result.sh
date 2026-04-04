#!/bin/bash
set -e
echo "=== Exporting Customer Journey Map Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DIAGRAM_FILE="/home/ga/Diagrams/return_journey.drawio"
EXPORT_FILE="/home/ga/Diagrams/exports/return_journey.png"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check export file existence and size
EXPORT_EXISTS="false"
EXPORT_SIZE=0
if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_FILE")
fi

# Check drawio file modification
FILE_MODIFIED="false"
FILE_MTIME=0
if [ -f "$DIAGRAM_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$DIAGRAM_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# App running check
APP_RUNNING="false"
if pgrep -f "drawio" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
# Note: Complex XML parsing is deferred to verifier.py which runs python
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "export_exists": $EXPORT_EXISTS,
    "export_size": $EXPORT_SIZE,
    "file_modified": $FILE_MODIFIED,
    "file_mtime": $FILE_MTIME,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "diagram_path": "$DIAGRAM_FILE"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="