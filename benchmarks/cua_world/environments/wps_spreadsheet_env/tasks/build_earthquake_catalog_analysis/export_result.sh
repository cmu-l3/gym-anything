#!/bin/bash
echo "=== Exporting task result ==="

# Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gather timestamps and app state
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ORIGINAL_MTIME=$(cat /tmp/original_mtime.txt 2>/dev/null || echo "0")

DATA_FILE="/home/ga/Documents/earthquake_catalog.xlsx"

if [ -f "$DATA_FILE" ]; then
    CURRENT_MTIME=$(stat -c %Y "$DATA_FILE" 2>/dev/null || echo "0")
    if [ "$CURRENT_MTIME" -gt "$ORIGINAL_MTIME" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
    FILE_EXISTS="true"
else
    FILE_EXISTS="false"
    FILE_MODIFIED="false"
fi

APP_RUNNING=$(pgrep -f "et" > /dev/null && echo "true" || echo "false")

# Save results locally
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "app_running": $APP_RUNNING
}
EOF

cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="