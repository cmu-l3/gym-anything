#!/bin/bash
echo "=== Exporting task results ==="

# Source utilities if available, otherwise define basics
source /workspace/scripts/task_utils.sh 2>/dev/null || true

OUTPUT_PATH="/home/ga/Documents/ml_papers.csv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check file existence and timestamps
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
fi

# 2. Check if Zotero is still running
APP_RUNNING=$(pgrep -f "zotero" > /dev/null && echo "true" || echo "false")

# 3. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_path": "$OUTPUT_PATH",
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="