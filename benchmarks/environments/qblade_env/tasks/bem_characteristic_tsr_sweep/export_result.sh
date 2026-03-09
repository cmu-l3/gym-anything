#!/bin/bash
echo "=== Exporting BEM Characteristic TSR Sweep result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture Final State Screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather Task Metrics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/projects/cp_tsr_results.txt"

# Check output file
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Verify file was modified AFTER task start
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

# Check if QBlade is still running
if pgrep -f "[Qq][Bb]lade" > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 3. Create Result JSON
# Using a temp file to avoid permission issues, then moving
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "output_path": "$OUTPUT_PATH",
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="