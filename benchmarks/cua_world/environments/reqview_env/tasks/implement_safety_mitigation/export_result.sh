#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Project Path
PROJECT_PATH="/home/ga/Documents/ReqView/safety_mitigation_project"

# Check if project files were modified
FILES_MODIFIED="false"
MOD_COUNT=0
for doc in "NEEDS" "SRS" "TESTS"; do
    FILE="$PROJECT_PATH/documents/$doc.json"
    if [ -f "$FILE" ]; then
        MTIME=$(stat -c %Y "$FILE" 2>/dev/null || echo "0")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            ((MOD_COUNT++))
        fi
    fi
done

if [ "$MOD_COUNT" -ge 1 ]; then
    FILES_MODIFIED="true"
fi

# Check if app is running
APP_RUNNING=$(pgrep -f "reqview" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files_modified": $FILES_MODIFIED,
    "modified_doc_count": $MOD_COUNT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "project_path": "$PROJECT_PATH"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="