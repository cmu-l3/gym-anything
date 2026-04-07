#!/bin/bash
echo "=== Exporting task result ==="

# Record end time & take final screenshot
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract basic file statistics 
ORDERS_FILE="/home/ga/Documents/supply_chain_orders.xlsx"
FILE_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"
FILE_MTIME="0"

if [ -f "$ORDERS_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$ORDERS_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# Write metadata to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "file_mtime": $FILE_MTIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="