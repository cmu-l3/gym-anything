#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

HAR_PATH="/home/ga/Documents/jwst_network.har"
TXT_PATH="/home/ga/Documents/slowest_asset.txt"

# Check HAR file
if [ -f "$HAR_PATH" ]; then
    HAR_EXISTS="true"
    HAR_SIZE=$(stat -c %s "$HAR_PATH" 2>/dev/null || echo "0")
    HAR_MTIME=$(stat -c %Y "$HAR_PATH" 2>/dev/null || echo "0")
    if [ "$HAR_MTIME" -ge "$TASK_START" ]; then
        HAR_CREATED_DURING_TASK="true"
    else
        HAR_CREATED_DURING_TASK="false"
    fi
else
    HAR_EXISTS="false"
    HAR_SIZE="0"
    HAR_CREATED_DURING_TASK="false"
fi

# Check TXT file
if [ -f "$TXT_PATH" ]; then
    TXT_EXISTS="true"
    TXT_SIZE=$(stat -c %s "$TXT_PATH" 2>/dev/null || echo "0")
    TXT_MTIME=$(stat -c %Y "$TXT_PATH" 2>/dev/null || echo "0")
    if [ "$TXT_MTIME" -ge "$TASK_START" ]; then
        TXT_CREATED_DURING_TASK="true"
    else
        TXT_CREATED_DURING_TASK="false"
    fi
else
    TXT_EXISTS="false"
    TXT_SIZE="0"
    TXT_CREATED_DURING_TASK="false"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "har_exists": $HAR_EXISTS,
    "har_size_bytes": $HAR_SIZE,
    "har_created_during_task": $HAR_CREATED_DURING_TASK,
    "txt_exists": $TXT_EXISTS,
    "txt_size_bytes": $TXT_SIZE,
    "txt_created_during_task": $TXT_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="