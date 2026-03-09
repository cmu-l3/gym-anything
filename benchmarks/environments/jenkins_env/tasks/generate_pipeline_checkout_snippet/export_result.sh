#!/bin/bash
# Export script for Generate Pipeline Checkout Snippet task

echo "=== Exporting Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

RESULT_FILE="/home/ga/spring_checkout_snippet.groovy"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_TIMESTAMP=$(date +%s)

# Initialize variables
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"

# Check file status
if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$RESULT_FILE")
    FILE_MTIME=$(stat -c%Y "$RESULT_FILE")
    
    # Check if file was created/modified after task start
    if [ "$FILE_MTIME" -ge "$TASK_START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Read content (base64 encode to safely transport via JSON)
    FILE_CONTENT=$(cat "$RESULT_FILE" | base64 -w 0)
fi

# Check if Jenkins/Firefox is still running (sanity check)
APP_RUNNING="false"
if pgrep -f "jenkins" > /dev/null || pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result using jq
TEMP_JSON=$(mktemp /tmp/snippet_result.XXXXXX.json)
jq -n \
    --arg file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --arg file_content_b64 "$FILE_CONTENT" \
    --arg created_during_task "$FILE_CREATED_DURING_TASK" \
    --arg app_running "$APP_RUNNING" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: ($file_exists == "true"),
        file_size: $file_size,
        file_content_b64: $file_content_b64,
        created_during_task: ($created_during_task == "true"),
        app_running: ($app_running == "true"),
        export_timestamp: $timestamp
    }' > "$TEMP_JSON"

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export Complete ==="