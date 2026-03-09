#!/bin/bash
echo "=== Exporting TSLS IV Estimation result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Collect timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check output file details
OUTPUT_PATH="/home/ga/Documents/gretl_output/tsls_results.txt"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT_PREVIEW=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read first 50 lines for preview (avoid massive JSONs)
    FILE_CONTENT_PREVIEW=$(head -n 50 "$OUTPUT_PATH" | base64 -w 0)
fi

# 4. Check if Gretl is still running
APP_RUNNING="false"
if is_gretl_running; then
    APP_RUNNING="true"
fi

# 5. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "output_content_base64": "$FILE_CONTENT_PREVIEW"
}
EOF

# 6. Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="