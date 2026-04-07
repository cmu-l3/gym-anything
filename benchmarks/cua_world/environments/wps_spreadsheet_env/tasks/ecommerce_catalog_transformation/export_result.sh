#!/bin/bash
echo "=== Exporting task result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CATALOG_FILE="/home/ga/Documents/retail_catalog.xlsx"
RESULT_JSON="/tmp/task_result.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file modification
FILE_EXISTS="false"
FILE_MODIFIED="false"

if [ -f "$CATALOG_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$CATALOG_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Export metadata
cat > "$RESULT_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "task_start_time": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Export complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"