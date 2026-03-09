#!/bin/bash
echo "=== Exporting design_vawt_blade result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected output
OUTPUT_PATH="/home/ga/Documents/projects/urban_darrieus_vawt.wpa"

# 1. Check file existence and metadata
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created/modified during the task window
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
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

# 2. Check if QBlade is still running (good indicator of active session)
if is_qblade_running > /dev/null 2>&1; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 3. Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# 4. Create JSON result
# We use a temp file to avoid permission issues, then move it
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_path": "$OUTPUT_PATH",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Move to standard result location with broad permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="