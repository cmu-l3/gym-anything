#!/bin/bash
echo "=== Exporting update_downstream_dependencies result ==="

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/Documents/ReqView/update_dependencies_project"
SRS_JSON="$PROJECT_DIR/documents/SRS.json"

# Check if SRS.json was modified
FILE_MODIFIED="false"
if [ -f "$SRS_JSON" ]; then
    MTIME=$(stat -c %Y "$SRS_JSON" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    FILE_SIZE=$(stat -c %s "$SRS_JSON" 2>/dev/null || echo "0")
else
    FILE_SIZE="0"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "srs_modified": $FILE_MODIFIED,
    "srs_size": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json