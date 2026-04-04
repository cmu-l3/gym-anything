#!/bin/bash
echo "=== Exporting analyze_email_headers result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check Submission File
SUBMISSION_FILE="/home/ga/submission/suspect_ip.txt"
SUBMISSION_EXISTS="false"
SUBMISSION_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$SUBMISSION_FILE" ]; then
    SUBMISSION_EXISTS="true"
    SUBMISSION_CONTENT=$(cat "$SUBMISSION_FILE" | head -n 1 | tr -d '\n\r') # Read first line only
    
    # Check creation time
    FILE_MTIME=$(stat -c %Y "$SUBMISSION_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Read Ground Truth (exported so we can verify without needing root in verifier if simple text)
# However, we will also leave the file for the verifier to copy if it wants.
GROUND_TRUTH_FILE="/var/lib/app/ground_truth/origin_ip.txt"
GROUND_TRUTH_VALUE=""
if [ -f "$GROUND_TRUTH_FILE" ]; then
    GROUND_TRUTH_VALUE=$(cat "$GROUND_TRUTH_FILE")
fi

# 5. Check if Firefox is running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "submission_exists": $SUBMISSION_EXISTS,
    "submission_content": "$SUBMISSION_CONTENT",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "ground_truth_value": "$GROUND_TRUTH_VALUE",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="