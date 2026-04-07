#!/bin/bash
echo "=== Exporting task result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

OUTPUT_PATH="/home/ga/Documents/iowa_corn_production.xlsx"
FILE_EXISTS="false"
MODIFIED="false"
CURRENT_HASH=""

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    CURRENT_HASH=$(md5sum "$OUTPUT_PATH" | awk '{print $1}')
    INITIAL_HASH=$(cat /tmp/initial_file_hash.txt 2>/dev/null || echo "none")
    
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        MODIFIED="true"
    fi
fi

APP_RUNNING=$(pgrep -x "et" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $MODIFIED,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="