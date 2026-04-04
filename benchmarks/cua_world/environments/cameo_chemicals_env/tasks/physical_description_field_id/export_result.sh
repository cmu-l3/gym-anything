#!/bin/bash
# export_result.sh - Post-task hook for physical_description_field_id
set -e

echo "=== Exporting physical_description_field_id results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Paths
OUTPUT_FILE="/home/ga/Desktop/field_id_reference.txt"
RESULT_JSON="/tmp/task_result.json"

# Check output file status
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"
FILE_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    # Check anti-gaming timestamp
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content safely (limit size to avoid huge JSONs)
    FILE_CONTENT=$(head -c 10000 "$OUTPUT_FILE" | base64 -w 0)
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Capture browser history/state (optional, but good for debugging)
# We won't parse sqlite here, verifier will use VLM for trajectory,
# but we can check if firefox is still running.
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Create JSON result
# Note: writing to temp file first to handle permissions/json syntax safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "file_content_base64": "$FILE_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON"

echo "Result saved to $RESULT_JSON"
echo "=== Export complete ==="