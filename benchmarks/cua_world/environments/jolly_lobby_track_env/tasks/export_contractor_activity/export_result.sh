#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
OUTPUT_PATH="/home/ga/Documents/contractor_activity.csv"
FINAL_SCREENSHOT="/tmp/task_final.png"

# Take final screenshot
DISPLAY=:1 scrot "$FINAL_SCREENSHOT" 2>/dev/null || \
    DISPLAY=:1 import -window root "$FINAL_SCREENSHOT" 2>/dev/null || true

# Check Output File
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
CONTENT_SAMPLE=""
LINE_COUNT=0

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check timestamp
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content for verification (first 20 lines)
    CONTENT_SAMPLE=$(head -n 20 "$OUTPUT_PATH" | base64 -w 0)
    LINE_COUNT=$(wc -l < "$OUTPUT_PATH")
fi

# Check if application is still running
APP_RUNNING=$(pgrep -f "Lobby" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "line_count": $LINE_COUNT,
    "content_base64": "$CONTENT_SAMPLE",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "$FINAL_SCREENSHOT"
}
EOF

# Safe move to /tmp/task_result.json
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="