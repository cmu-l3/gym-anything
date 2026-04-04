#!/bin/bash
echo "=== Exporting audit_failed_login_attempt result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
RESULT_FILE="/home/ga/suspicious_ip.txt"
GROUND_TRUTH_FILE="/tmp/ground_truth_ip.txt"
TASK_START_FILE="/tmp/task_start_time.txt"

# Get Task Start Time
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

# 1. Check Agent's Output File
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    # Read content, trim whitespace
    FILE_CONTENT=$(cat "$RESULT_FILE" | tr -d '[:space:]')
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Get Ground Truth
GROUND_TRUTH_IP=""
if [ -f "$GROUND_TRUTH_FILE" ]; then
    GROUND_TRUTH_IP=$(cat "$GROUND_TRUTH_FILE" | tr -d '[:space:]')
fi

# 3. Check application state (did they navigate to logs?)
# We can't easily check navigation history, but we can check if they are logged in via screenshot or cookies if we wanted.
# For now, we rely on the file content.

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_content": "$FILE_CONTENT",
    "ground_truth_ip": "$GROUND_TRUTH_IP",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result with permissions suitable for copy_from_env
safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="