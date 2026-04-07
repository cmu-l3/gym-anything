#!/bin/bash
echo "=== Exporting Clinical Mining Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/penicillin_safety_review.csv"

# 1. Check Output File
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    # Verify it was created during the task
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# 2. Check Database Query History (Anti-gaming / Process check)
# Check if agent accessed the Legacy_Observations table
HISTORY_CHECK=$(grep -i "Legacy_Observations" ~/.mysql_history 2>/dev/null | tail -1 || echo "")
if [ -n "$HISTORY_CHECK" ]; then
    USED_CORRECT_TABLE="true"
else
    USED_CORRECT_TABLE="false"
fi

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/mining_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "used_correct_table": $USED_CORRECT_TABLE,
    "task_timestamp": "$(date -Iseconds)"
}
EOF

# 5. Save result securely
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

# 6. Provide output file for verifier (copy to temp for access)
if [ "$FILE_EXISTS" = "true" ]; then
    cp "$OUTPUT_FILE" /tmp/agent_output.csv
    chmod 666 /tmp/agent_output.csv
fi

echo "=== Export Complete ==="