#!/bin/bash
echo "=== Exporting task result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

INVENTORY_FILE="/home/ga/Documents/inventory_abc_analysis.xlsx"

# Check file modification
if [ -f "$INVENTORY_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$INVENTORY_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$INVENTORY_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_MODIFIED="false"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="