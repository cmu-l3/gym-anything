#!/bin/bash
echo "=== Exporting generate_web_to_lead_form results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot of the application state
take_screenshot /tmp/generate_web_to_lead_form_final.png

# Fetch timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# File verification variables
FILE_PATH="/home/ga/Documents/tradeshow_lead_form.html"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

# Check if the agent successfully saved the HTML file
if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FILE_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")

    # Anti-gaming: Ensure the file was actually created/modified after the task started
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Export metadata to JSON
RESULT_JSON=$(cat << JSONEOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "file_path": "$FILE_PATH",
  "file_exists": $FILE_EXISTS,
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "file_size_bytes": $FILE_SIZE
}
JSONEOF
)

# Use utility from task_utils.sh to safely write the JSON result
safe_write_result "/tmp/generate_web_to_lead_form_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/generate_web_to_lead_form_result.json"
echo "$RESULT_JSON"
echo "=== generate_web_to_lead_form export complete ==="