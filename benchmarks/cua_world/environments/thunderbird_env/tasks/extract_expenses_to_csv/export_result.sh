#!/bin/bash
echo "=== Exporting result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_CSV="/home/ga/Documents/expense_summary.csv"

# Take final screenshot before checking data
take_screenshot /tmp/task_final.png

FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_CSV" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_CSV" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_CSV" 2>/dev/null || echo "0")
    
    # Anti-gaming: Ensure file was created AFTER task setup
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Copy CSV to /tmp for verifier access
    cp "$OUTPUT_CSV" /tmp/expense_summary.csv
    chmod 666 /tmp/expense_summary.csv
fi

TB_RUNNING="false"
if is_thunderbird_running; then
    TB_RUNNING="true"
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "thunderbird_running": $TB_RUNNING
}
EOF

# Save JSON result
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="