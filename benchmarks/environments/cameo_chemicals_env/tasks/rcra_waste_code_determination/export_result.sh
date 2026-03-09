#!/bin/bash
# export_result.sh - Post-task hook for rcra_waste_code_determination
set -e

echo "=== Exporting RCRA Task Results ==="

# 1. Capture Final State (Screenshot)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Collect Task Metrics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/home/ga/Documents/waste_classification.csv"

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
OUTPUT_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Verify file was modified/created after task start
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content (base64 encoded to safely transport via JSON)
    OUTPUT_CONTENT=$(base64 -w 0 "$OUTPUT_FILE")
fi

# Check if browser is still running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "output_content_b64": "$OUTPUT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Move to final location
# Ensure permissions allow the host verifier to read it
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="