#!/bin/bash
set -e
echo "=== Exporting extract_connection_stats result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/jitsi_connection_stats.json"

# Take final screenshot of the state
take_screenshot /tmp/task_final.png

# Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
FILE_MTIME="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Anti-gaming: Check if file was modified after task start
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if Firefox is still running (app state)
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "file_mtime": $FILE_MTIME,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Copy the actual output file to /tmp for the verifier to read (via copy_from_env)
if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$OUTPUT_PATH" /tmp/jitsi_stats_verification.json
    chmod 666 /tmp/jitsi_stats_verification.json
fi

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="