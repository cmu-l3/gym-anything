#!/bin/bash
set -euo pipefail

echo "=== Exporting Logit Marginal Effects results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Define output paths
OUTPUT_FILE="/home/ga/Documents/gretl_output/logit_mfx.txt"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check file status
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"
FILE_CONTENT_PREVIEW=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    # Check if created/modified after task start
    if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read first few lines for debug/context (base64 safe or just head)
    FILE_CONTENT_PREVIEW=$(head -n 20 "$OUTPUT_FILE" | base64 -w 0)
fi

# 4. Check application state
APP_RUNNING="false"
if is_gretl_running; then
    APP_RUNNING="true"
fi

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START_TIME,
    "timestamp": "$(date -Iseconds)",
    "output_file_exists": $FILE_EXISTS,
    "output_file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_file_size": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "output_content_b64": "$FILE_CONTENT_PREVIEW"
}
EOF

# 6. Move to final location
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"