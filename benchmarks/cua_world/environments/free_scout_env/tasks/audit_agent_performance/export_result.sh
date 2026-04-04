#!/bin/bash
echo "=== Exporting audit_agent_performance result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Get the User's Answer
OUTPUT_PATH="/home/ga/Documents/marcus_closed_count.txt"
USER_ANSWER=""
FILE_EXISTS="false"
FILE_MTIME="0"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    # Read the file and extract the first number found
    CONTENT=$(cat "$OUTPUT_PATH")
    # Extract integer using grep/perl
    USER_ANSWER=$(echo "$CONTENT" | grep -oE '[0-9]+' | head -1)
    
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Get the Ground Truth (Actual DB Count)
# Find Marcus's ID again to be safe
MARCUS_ID=$(fs_query "SELECT id FROM users WHERE email='marcus@helpdesk.local' LIMIT 1" 2>/dev/null)

ACTUAL_COUNT="0"
if [ -n "$MARCUS_ID" ]; then
    # Count conversations where user_id = Marcus AND status = 3 (Closed)
    ACTUAL_COUNT=$(fs_query "SELECT COUNT(*) FROM conversations WHERE user_id = $MARCUS_ID AND status = 3" 2>/dev/null || echo "0")
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "user_answer": "${USER_ANSWER}",
    "actual_count": ${ACTUAL_COUNT},
    "marcus_user_id": "${MARCUS_ID}",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="